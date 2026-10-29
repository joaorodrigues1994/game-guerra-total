# Arquitetura — Estratégia Napoleônica

Documento vivo. Estado atual: **Fase 0 (Fundação)**.

## Princípios

1. **Lógica separada de apresentação.** Regras são classes `RefCounted` sem nós; cenas apenas desenham o estado e enviam comandos.
2. **Dados separados de regras.** Definições estáticas vivem em `data/*.json`; estado mutável vive no `GameState`.
3. **IDs estáveis em texto** (`fra`, `prov_paris`, `unit_line_inf`, `barracks`). Nunca índices.
4. **Campanha e batalha não se importam.** Comunicam-se apenas por `BattleRequest` e `BattleResult` (Fase 2/3).
5. **Fonte única de verdade:** o `GameState`. Cenas não guardam estado próprio de jogo.
6. **Sem dependências externas.** Testes próprios, sem GUT.

## Módulos (`src/`)

| Pasta | Responsabilidade | Situação |
|---|---|---|
| `core/` | `GameState` (estado mutável), `EventBus` (autoload), `Registry` (carga e validação) | Fase 0/1 |
| `campaign/` | `TurnProcessor` (turno), `CampaignActions` (construir/recrutar), `CampaignController` (seleção, ações, dados de exibição) | Fase 1/campanha |
| `economy/` | `EconomyCalculator` (receitas, manutenção, bônus; só leitura) | campanha |
| `units/` | `ArmyActions` (exércitos, generais, movimentação, encontros) | exércitos |
| `provinces/` | `MapGeometry` (geometria pura), `ProvinceMap` (polígonos, teste de clique, fronteiras) | Fase 1 |
| `battle/` | batalha tática independente: `Hex`, `BattleRegistry`, `BattleMap`, `BattleState`, `BattlePathfinding`, `BattleMovement`, `BattleCombat`, `BattleMorale`, `BattleTurns`, `BattleAI`, `BattleController` | batalha tática |
| `integration/` | camada adaptadora campanha -> batalha: `BattleRequest`, `BattleScenarioBuilder` (somente leitura) e `BattleLifecycle` (registro, cancelamento e transições das batalhas; depende dos dois módulos) | integração (Etapas 3 e 4) |
| `ui/` | `MapView` (mapa e marcadores), `ProvincePanel`, `ArmyPanel`, `TopBar`, `StatusBar`, `CampaignScreen` (leem o estado e chamam o controlador); `ui/battle/`: `BattleScreen`, `BattleView`, `BattlePanel`, `BattleLogPanel`, `BattleResultPanel` | Fase 1/campanha/exércitos/batalha |

## Dados (`data/`)

| Arquivo | Conteúdo |
|---|---|
| `rules.json` | data inicial, recursos, terrenos, categorias, tipos de ligação, `max_concurrent_constructions`, `max_army_units`, `manpower_rate`, nomes de exibição (`resource_names`, `terrain_names`, `link_type_names`, `effect_names`) |
| `countries.json` | id, nome, cor, capital, recursos iniciais |
| `provinces.json` | dono, vizinhos tipados, população, produção, terreno, cidade, construções, guarnição, valor estratégico |
| `units.json` | custos, manutenção, efetivo, ataque, defesa, mobilidade, alcance, moral, experiência, requisitos, `recruitable`, `recruit_turns` |
| `buildings.json` | custo, duração (`build_turns`), efeitos, requisitos (`requires`), `buildable` |
| `generals.json` | id, nome, nacionalidade, `command` (habilidade), `experience` (informativos nesta etapa) |
| `armies.json` | exércitos iniciais: nome, dono, província própria, lista de tipos de unidade e general opcional |

Os arquivos atuais são **dados de exemplo** (3 países, 9 províncias, 3 unidades, 6 construções). O mapa é inspirado na Europa Central de 1805, mas **fronteiras e valores não são uma representação histórica rigorosa**.

### Esquema do mapa (Fase 1)

- `rules.json` ganhou `map_size` (`[largura, altura]` em unidades de mapa) e os nomes de exibição `resource_names`, `terrain_names` e `link_type_names` (todo id das listas correspondentes precisa ter nome).
- Cada província tem `map.polygon` (lista de `[x, y]`, polígono simples, dentro de `map_size`) e `map.label` (ponto dentro do polígono, onde ficam o nome e a estrela de capital).
- **Fronteiras compartilham vértices exatamente.** Duas províncias vizinhas precisam ter ao menos uma aresta idêntica; o `Registry` rejeita vizinhos que não se tocam. Não há tolerância para T-junctions: se uma aresta de A cobre dois segmentos de B, A deve listar o vértice intermediário.
- A ligação Estrasburgo–Viena da Fase 0 era um placeholder sem base geográfica e foi substituída pela adjacência real do mapa novo.

### Estado mutável vs. definição

O `GameState` copia do `Registry` apenas o que muda (dono, população, construções, guarnição, recursos do país). Nome, terreno, produção, vizinhos e geometria são sempre lidos do `Registry`. A interface nunca guarda cópia: pede ao `CampaignController` (`province_view`, `country_view`) e escuta `selection_changed`.

### Interface de campanha

`main.gd` carrega o `Registry`, cria o `GameState` (jogador: França, fixo na Fase 1), monta `ProvinceMap` e `CampaignController`, e instancia a `CampaignScreen`. O clique é convertido de tela para coordenadas de mapa e resolvido por `Geometry2D.is_point_in_polygon` sobre os polígonos reais. Clicar fora de qualquer província, botão direito, Esc ou o botão "Limpar seleção" limpam a seleção.

O `Registry` valida ao carregar: ids únicos, referências existentes (dono, capital, vizinhos, construções), ligações recíprocas e do mesmo tipo, terrenos/categorias/recursos conhecidos, números não negativos. Erros ficam em `Registry.errors`.

Os JSON numéricos são lidos como `float` pelo Godot; ao usar valores como inteiros, converter explicitamente.

## Campanha funcional: economia, construções, recrutamento

### Estado (GameState)

Além do dono, população, construções concluídas e guarnição, cada província tem duas filas:
`constructions` (`[{building, remaining}]`) e `recruitments` (`[{unit, remaining}]`), com os turnos restantes.
Cada país tem `resources` (`gold`, `food`, `materials`, `manpower`, `prestige`, todos inteiros, nunca negativos).
Unidades, exércitos e generais estão descritos em "Exércitos, generais e movimentação" abaixo.

### Regras econômicas (EconomyCalculator)

- **Receita por turno de uma província** = produção base (`provinces.json`) + efeitos de recurso das construções **concluídas** + `população * rules.manpower_rate` (recrutáveis).
- **Receita do país** = soma das províncias que ele controla no momento. Províncias de outros países não contam.
- **Despesa do país** = soma da manutenção (`upkeep`) das unidades que ele possui.
- Efeitos que não são recursos: `recruit_capacity` (soma = recrutamentos simultâneos por província) e `defense_bonus` (exibido; o combate vem depois). `unlocks_artillery` existe nos dados, mas o Arsenal está com `buildable: false` até a artilharia ser implementada.
- **Quando calcula e quando credita:** o cálculo é feito sobre o estado no **início** do processamento do turno e creditado/debitado de uma vez na etapa `income_expenses`. A interface mostra a projeção por turno (barra superior) usando o mesmo cálculo.
- Se a manutenção superar o saldo, paga-se o que existe (recursos nunca ficam negativos) e o déficit entra em `report.shortfall`. Consequências do déficit (deserção etc.) ficam para fases futuras.

### Construções e recrutamento (CampaignActions)

Toda ação valida **antes** de alterar o estado; se falhar, nada muda e devolve `{ok, message}` com o motivo em português.

- **Construir:** província própria; construção `buildable`; ainda não construída nem em obras; fila com espaço (regra simples: `rules.max_concurrent_constructions` = 1 por província); requisitos (`requires`) concluídos na província; recursos suficientes. Depois: desconta o custo e entra na fila com `build_turns`. Não há melhoria por níveis (só construir uma vez cada tipo por província).
- **Recrutar:** província própria; unidade `recruitable` (só Infantaria de linha); construções exigidas (`requirements.buildings`, o Quartel) concluídas; capacidade livre (`recruit_capacity`: o Quartel dá 2 vagas); recursos suficientes (inclui `manpower`). Depois: desconta o custo e entra na fila com `recruit_turns`.
- Paris começa com Quartel para o recrutamento ficar disponível desde o turno 1; as demais províncias precisam construir um.

### Exércitos, generais e movimentação

**Estado (GameState)** — fonte única, sem cópias paralelas:

- `units`: **instâncias** de unidade `{id, type, owner, province, strength, morale, experience}`. `id` é inteiro, único e estável na campanha, distinto de `type` (o id da definição em `units.json`). Nome, ataque etc. **não** são copiados: vêm do `Registry`. `province` é a província de guarnição (só vale fora de exércitos; ao sair de um exército passa a ser a província dele).
- `armies`: `{id, name, owner, province, units, general, moved}`. `units` (ids de instâncias) é a **única** fonte de "quem está em qual exército"; `general` (id ou `""`) é a única fonte de "quem comanda qual exército". Efetivo total = soma de `strength` das unidades (calculado, nunca armazenado). `moved` marca o movimento do turno.
- `generals`: `{owner, experience}` por id; nome e comando vêm do Registry. Atributos apenas informativos (sem bônus de combate).
- `encounters`: contrato de encontro `{id, province, turn, initiator, armies, countries}`, base de um futuro `BattleRequest`.
- Consultas: `armies_in(província[, país])`, `army_of_unit`, `location_of_unit`, `units_in`, `garrison_units`, `army_strength`, `army_of_general`, `encounter_of_army`.
- O `garrison` numérico da província (guarnição abstrata do mapa) continua separado; "guarnição" no painel militar são as **unidades fora de exércitos**.

**Dados iniciais:** `armies.json` cria exércitos (e suas unidades-instância) de Áustria e Baviera; a França começa sem exército e forma o primeiro recrutando. `rules.max_army_units` (4) é o limite configurável de unidades por exército.

**Incorporação de recrutas:** a unidade concluída entra no primeiro exército (por id) do mesmo país, na mesma província, com vaga e fora de encontro; se não houver, forma-se um novo exército com ela ("Exército de <província>"). Nenhuma unidade fica sem exército nem desaparece. Unidades de guarnição (resultado de "Separar") podem ser incorporadas ou formar novo exército por ação do jogador.

**Organização (ArmyActions):** `add_unit_to_army` (mesma província, mesmo dono, unidade fora de exército, vaga), `detach_unit` (vai para a guarnição da província do exército; se o exército esvaziar, é desfeito e o general, liberado; exige território próprio e exército fora de encontro), `form_army`, `assign_general`/`unassign_general` (general do mesmo país, livre; exército sem general). Tudo valida antes de alterar o estado.

**Regras de movimentação** (sem guerra/diplomacia):

1. Só por conexões do grafo lógico de províncias (`neighbors`), nunca por coordenadas visuais.
2. No máximo **1 província por exército por turno** (`moved`); a ordem é imediata e só é executada uma vez.
3. Só se pode ordenar exércitos do próprio país, e só entrar em províncias do **próprio país** ("sem acesso ao território" caso contrário: não há guerra declarada nem acordos de passagem). Invasões ficam para quando houver guerra.
4. Ordem inválida (exército/destino inexistente, não conectado, estrangeiro, sem acesso, já movido, em encontro) não altera o estado e devolve o motivo.
5. **Encontros:** se, depois do movimento, há exército de outro país na província de destino, registra-se (ou amplia-se) um encontro em `state.encounters`. Os exércitos envolvidos ficam **parados** (não se movem nem se reorganizam) até o encontro deixar de existir. O movimento nunca é tratado como pacífico: a mensagem avisa e o marcador mostra "!". Sem guerra, isso só ocorre se um exército estrangeiro já estiver em território próprio; a resolução (batalha) virá depois.

**Interface:** marcadores (um por exército, número = unidades; borda dourada = seu, vermelha = estrangeiro, branca = selecionado, "!" = encontro; no máximo 6 por província, o último vira "+N") desenhados sobre o mapa; clique no marcador seleciona o exército e a província dele; a lista completa fica no painel da província. Clique na província mantém o exército só se ele estiver nela; clicar no mar, botão direito ou Esc limpam tudo. O `ArmyPanel` mostra composição, general, estado de movimento e botões de destino (com o motivo quando bloqueados); destinos livres do exército selecionado são realçados em verde no mapa.

### Ordem de processamento do turno

Fixa e coberta por `tests/test_turn_order.gd`. Qualquer mudança exige atualizar este documento e o teste. Cada etapa roda **uma vez** por chamada de `end_turn`; chamadas reentrantes (por exemplo, de um handler de sinal) são rejeitadas.

1. `validate_state` — verifica recursos (inteiros, >= 0), filas, referências, exércitos (dono/província, unidade em no máximo um exército, general válido e comandando um só exército); se houver erro, aborta **sem alterar nada** (`report.ok = false`).
2. `income_expenses` — credita receitas e debita manutenção de **todos** os países, sobre o estado do início do turno.
3. `construction_progress` — reduz `remaining`; ao chegar a 0, a construção é concluída.
4. `recruitment` — reduz `remaining`; ao chegar a 0, cria a instância em `state.units` e a incorpora a um exército (regra acima).
5. `ai_actions` — (futuro) ações dos países controlados pela IA; vazio.
6. `military_movement` — (futuro) ordens de movimento enfileiradas; hoje as ordens são imediatas (no momento em que o jogador as dá), então a etapa está vazia.
7. `advance_turn` — `state.turn += 1`.
8. `army_reset` — novo turno: `moved = false` em todos os exércitos e descarte dos encontros que já não se aplicam (menos de dois países na província).
9. `events` — emite `EventBus.turn_ended(novo_turno)`.

`army_reset` fica depois de `advance_turn` porque o reinício pertence ao **início do novo turno**; antes dela o exército já usou seu movimento, depois dela pode se mover de novo. Justificativas das mudanças em relação à ordem da Fase 0: `supply_upkeep` foi absorvida por `income_expenses` (receita e manutenção formam um único balanço do turno); foi adicionada `validate_state` no início e `advance_turn` antes de `events`, para a interface já receber o turno novo. Como a receita é calculada **antes** das etapas 3 e 4, uma construção concluída (ou unidade criada) neste turno só rende (ou custa manutenção) a partir do próximo: não há receita retroativa. Uma construção de N turnos iniciada no turno T conclui no N-ésimo encerramento e rende a partir do encerramento seguinte.

Eventos: `EventBus.turn_phase_processed(fase)` a cada etapa e `turn_ended`; o `CampaignController` emite `state_changed`, `turn_ended(relatório)` e `message_posted(texto, é_erro)` para a interface.

### Interface

- Barra superior: nação, data/turno, recursos, receitas e despesas por turno e o botão **Encerrar turno**.
- Painel lateral: dados da província; se ela for do jogador, botões **Construir** e **Recrutar** (desabilitados com o motivo visível quando inválidos), filas em andamento e unidades recrutadas.
- Barra de mensagens: resultado das ações, motivos de rejeição e o resumo do turno.
- Os botões chamam `CampaignController.build/recruit/end_turn`; a interface não replica regras nem guarda estado.

## Batalha tática (implementada; independente da campanha)

A batalha é um módulo **separado**: não lê nem altera o `GameState`, o `Registry` ou a campanha. Tem seus próprios dados (`data/battle/`), estado (`BattleState`) e controlador (`BattleController`). Roda sozinha (`scenes/battle.tscn`) ou como camada sobre a campanha (botão **Batalha de teste** na barra superior; a campanha continua viva por baixo e "Voltar à campanha" a mostra de novo, intacta).

### Dados (`data/battle/`, validados por `BattleRegistry`)

| Arquivo | Conteúdo |
|---|---|
| `terrain.json` | `plains` (custo 1, +0%), `forest` (custo 2, +30% defesa), `hills` (custo 2, +20%), `water` (intransponível); cor e caractere de legenda |
| `unit_types.json` | `infantry`, `cavalry`, `artillery`: ataque, defesa, `move_range`, `attack_range`, `min_range`, `melee`, `can_retaliate`, `can_attack_after_move`, `charge_bonus`, `max_strength`, `max_morale`, `campaign_category` (ponte para os tipos da campanha) |
| `battle_rules.json` | taxas de dano, variação, limites de moral, recuperação, raio de queda de aliado etc. |
| `scenarios/test_battle.json` | mapa 12×9 em texto (`.` planície, `f` floresta, `h` colina, `~` água), semente, limite de turnos, lados e as 10 unidades (5 por lado) |

Os dados de teste ficam em `data/battle/`, separados dos dados permanentes da campanha (`data/*.json`).

### API de cenários em memória (Etapa 2 da integração)

Uma batalha pode ser iniciada a partir de um cenário **fornecido como dicionário**, sem cadastrá-lo em `data/battle/scenarios/`. O formato é exatamente o dos arquivos de cenário (`id`, `name`, `seed`, `max_turns`, `map.rows`, `sides`, `units`); a única adição é o campo **opcional** `source_id` por unidade (inteiro >= 0, referência à unidade de origem; vai para `unit["source_id"]` e volta no `result_summary()`).

```gdscript
var registry := BattleRegistry.new(); registry.load_from_dir()          # terrenos, tipos e regras
var problems := registry.validate_scenario(scenario)                      # PackedStringArray; vazio = válido (não altera o registro)
var state := BattleState.new()
if not state.setup_from_scenario(registry, scenario):                     # valida ANTES de alterar o estado
    print(state.setup_errors)                                             # motivos legíveis, todos de uma vez
```

- `BattleState.setup_from_scenario(registry, scenario: Dictionary) -> bool`: valida, e só então monta o estado. Se o cenário for inválido devolve `false`, preenche `setup_errors` e **o estado permanece exatamente como estava** (um estado novo continua vazio; uma batalha em andamento não é afetada). O estado copia o cenário (`duplicate(true)`): alterar o dicionário depois não muda a batalha.
- `BattleState.setup(registry, id)` continua igual para quem o usa: busca o cenário **cadastrado** e delega a `setup_from_scenario`; id desconhecido devolve `false` com `setup_errors = ["Cenário não cadastrado: ..."]`. Os dois caminhos usam a mesma lógica (nada duplicado) e produzem estados idênticos.
- `BattleRegistry.validate_scenario(scenario: Variant) -> PackedStringArray` é a mesma validação aplicada aos arquivos ao carregar o registro. Rejeita: valor que não é dicionário; registro sem terrenos/tipos/regras carregados; `id`/`name`/`seed`/`max_turns` ausentes ou com tipo/valor inválido; `map.rows` ausente, vazio, com linha que não é texto ou de largura diferente, ou com caractere de terreno desconhecido; `sides` sem `player`/`enemy`, com nome vazio, cor ou `home_edge` inválidos, ou com a mesma borda para os dois lados; `units` que não é lista; unidade que não é objeto, sem nome, com lado inválido, tipo desconhecido, `at` ausente/mal formado/fracionário/fora do mapa/em terreno intransponível/repetido, `strength`/`morale` fora de [1, máximo do tipo], `source_id` inválido; lado sem unidades.
- Diferença em relação à interface sugerida (`setup_from_scenario(registry, scenario)`): o formato é o mesmo; apenas o retorno é `bool` (padrão do projeto) e os motivos ficam em `setup_errors`.
- Fora de escopo desta etapa (Etapas 3 a 6): gerar o cenário a partir de exércitos/províncias, converter tipos/efetivo/moral da campanha, aplicar o resultado na campanha, bloquear o turno da campanha.

### Geometria (`Hex`, único lugar com contas de hexágono)

Coordenadas **axiais** (q, r) em `Vector2i`, hexágonos **pointy-top**. Vizinhos: (+1,0) (+1,-1) (0,-1) (-1,0) (-1,+1) (0,+1). Distância = (|dq| + |dq+dr| + |dr|)/2. Pixels: `x = s·(√3·q + √3/2·r)`, `y = s·3/2·r`; o inverso usa arredondamento cúbico (`axial_round`). Os cenários usam **offset odd-r** (coluna, linha), convertido por `offset_to_axial`/`axial_to_offset`. A escolha axial mantém vizinhança e distância sem tabelas por paridade; offset só existe nas bordas (dados e exibição de "coluna, linha").

### Unidade tática (`BattleState.units`)

Dicionário por instância: `id` (inteiro), `name`, `type`, `side` (`player`/`enemy`), `pos`, `strength`/`max_strength`, `attack`, `defense`, `move_range`, `attack_range`, `min_range`, `melee`, `morale`/`max_morale`, `moved`, `attacked`, `moved_steps`, `routing`, `fled`, `destroyed`, `source_id`. Os atributos são **copiados do tipo na criação** (a campanha poderá injetar modificadores, por exemplo de general). `status_of`: `firm` (moral > 50), `shaken` (<= 50), `routing`, `fled`, `destroyed`.

### Turnos e movimento

- Rodada: jogador, depois inimigo; o número do turno sobe quando o inimigo termina. No **início do turno de um lado**: ações restauradas; moral recuperada (só sem inimigo adjacente) e reagrupamento; retirada forçada das unidades ainda em fuga; verificação de vitória.
- Movimento (`BattleMovement`/`BattlePathfinding`): Dijkstra pelo custo do terreno **entrado**; orçamento = `move_range`; água e hexágonos ocupados (por qualquer unidade) não podem ser atravessados nem ocupados; 1 movimento por unidade por turno; só unidades do lado ativo e fora de retirada. Toda recusa devolve o motivo e não altera o estado.
- Inimigo (`BattleAI`, determinística): ataca se alcança alguém (alvo de menor efetivo); senão move para um hexágono de onde possa atacar (maior bônus de terreno, menor custo); senão se aproxima (mapa de distância por terreno, contorna a água; artilharia para a distância do alcance). Usa as mesmas funções validadas do jogador. Ao fim do turno do jogador o `BattleController` roda o turno inimigo inteiro e devolve o controle.

### Combate (`BattleCombat`) — fórmula e valores

```
poder     = ataque × (efetivo / efetivo_máx) × mult_moral_atacante × (1 + carga)
defesa_ef = defesa_alvo × (1 + bônus_terreno_do_alvo) × mult_moral_alvo
fração    = clamp(taxa × (poder / defesa_ef) × fator × variação, 0, 0,6)
baixas    = clamp(ceil(efetivo_alvo × fração), 1, efetivo_alvo)     # dano mínimo 1
taxa      = 0,22 (corpo a corpo) ou 0,14 (à distância); fator = 1 (ataque) ou 0,5 (retaliação)
variação  = 1 ± 10% com RNG de semente configurável (o cenário define a semente; 0 = sem sorteio)
```

- **Infantaria**: ataque 6, defesa 6, move 3, alcance 1, 500 homens. **Cavalaria**: ataque 8, defesa 4, move 5, alcance 1, 200 homens; **carga** (+35% de poder) se andou >= 2 hexágonos no turno e ataca corpo a corpo. **Artilharia**: ataque 9, defesa 3, move 2, alcance 2–3 (não ataca adjacente), 80 homens; só à distância, **não atira no turno em que se moveu** e não retalia.
- Corpo a corpo gera **retaliação** (uma vez, fator 0,5) se o alvo sobrevive, não está em retirada e pode retaliar. Tiro à distância não gera retaliação. Aliados não podem ser atacados; uma ação de ataque por unidade por turno.
- Alvo destruído: marcado `destroyed`, efetivo 0, hexágono liberado.

### Moral (`BattleMorale`)

Moral em [0, máx=100]. Ao receber um ataque: `queda = ceil(baixas/efetivo_máx × 100) + 3` (+2 em corpo a corpo). Destruição de uma unidade tira 10 de moral dos aliados a até 2 hexágonos. Limites: **abalada** <= 50 (ataque ×0,8, defesa ×0,9); **em retirada** <= 25 (não ataca, não retalia, defesa ×0,5, não recebe ordens); reagrupa ao chegar a >= 40 (só longe de inimigos). Recuperação no início do turno do lado: +5 (+8 em retirada), nunca adjacente a inimigo. **Retirada**: no início do turno do lado a unidade recua sozinha pelo caminho de menor custo até a borda de origem (oeste para o jogador, leste para o inimigo), até seu `move_range`; ao chegar à borda **abandona o campo** (`fled`). Regras da retirada (correção do defeito "presa por aliadas"): (1) **atravessa unidades aliadas**; só **inimigos** e terreno intransponível barram o caminho; (2) **nunca para sobre outra unidade**: se não alcança a borda neste turno, para no **último hexágono livre** do caminho dentro do alcance; (3) chegar a uma borda ocupada por aliada também a faz sair do campo (ela não para ali); (4) sem caminho (cercada por inimigos/água) ou sem hexágono livre à frente, **fica parada**, com o motivo no registro ("cercada…" / "não encontra espaço livre…"), sem teletransporte e sem travar a interface. Cada turno recalcula a rota e anda para mais perto da borda ou espera, então não há ciclo; o limite de turnos é a rede de segurança final. As regras de movimento das unidades que **não** estão em retirada não mudaram (aliadas e inimigas continuam bloqueando e não podem ser ocupadas).

### Vitória (`BattleTurns.evaluate_victory`, após cada ataque e no início de cada turno)

Um lado está **quebrado** quando não tem unidade **efetiva** (em campo e fora de retirada). Ter gasto as ações não conta. Só um lado quebrado: o outro vence, por `elimination` (o derrotado não tem mais ninguém em campo: destruídos ou fugidos) ou `rout` (restam unidades dele, todas em retirada). Os dois quebrados: empate (`mutual_break`). Ao terminar o turno `max_turns` (40) do inimigo: vence quem tem mais efetivo efetivo (`turn_limit`; igual = empate). Depois do fim, toda ação é recusada com "A batalha terminou."

### Interface e reinício

`BattleScreen`: barra superior (turno, lado ativo, **Encerrar turno**, **Reiniciar batalha**, **Voltar à campanha** quando aberta pela campanha), mapa (`BattleView`: terreno com marcas, hexágonos alcançáveis em azul, alvos válidos em vermelho, unidade/hexágono selecionados, formas por tipo, barras de efetivo e moral, marcas de ação gasta), painel da unidade e do hexágono, registro de combate e painel de resultado (vencedor, motivo, sobreviventes por lado, **Jogar novamente**). Cliques: unidade própria seleciona; hexágono azul move; inimigo vermelho ataca; clique em inimigo sem unidade própria selecionada só consulta; botão direito/Esc limpa. `BattleController.restart()` recria o `BattleState` do cenário (mesma semente) e mantém as mesmas conexões de sinal: nada é duplicado.

## Integração campanha ↔ batalha (contrato pronto, integração NÃO implementada)

O que existe: `BattleState.setup(registry, scenario)` monta tudo a partir de **dados**; `BattleState.add_unit(type, nome, lado, pos, {strength, morale, source_id})` aceita efetivo, moral e o id da unidade de campanha de origem; `BattleState.result_summary()` devolve o `BattleResult`: `{scenario_id, winner, reason, text, turns, units: {lado: [{unit_id, source_id, name, type, strength, max_strength, morale, status}]}}`. O contrato de encontro da campanha (`GameState.encounters`: província, exércitos e países) é o gatilho natural.

O que falta (próxima etapa): (1) montar um cenário a partir de um encontro: mapa a partir do terreno da província (`terrains` da campanha -> terrenos táticos), unidades de cada exército (`campaign_category` liga o tipo da campanha ao tipo tático; efetivo/moral/experiência das instâncias; `source_id` = id da instância); general como modificador; (2) aplicar o `BattleResult` à campanha **depois** da batalha (baixas por `source_id`, destruídas, fugidas, controle da província); a batalha nunca altera o `GameState` diretamente; (3) resolução automática para IA contra IA reutilizando as mesmas regras (`BattleAI` já joga os dois lados em testes).

### Camada adaptadora `src/integration/` (Etapa 3; sem efeito na campanha)

Converte um **encontro pendente** (`GameState.encounters`) em um **cenário tático** (dicionário aceito por `BattleState.setup_from_scenario`). É **somente leitura**: não inicia batalha, não consome o encontro, não trava exércitos e não altera força, moral, províncias nem turnos (testado comparando `GameState.to_dict()` antes e depois). Fica fora de `battle/` e `campaign/` porque depende dos dois.

```gdscript
var mapping := BattleScenarioBuilder.load_mapping()["mapping"]            # data/battle/campaign_mapping.json
var r := BattleScenarioBuilder.build(registry, state, battle_registry, mapping, encounter_id)
# r = {ok, scenario, request, conversion, errors: PackedStringArray, message: String}   (mesma convenção {ok, message}; message = erros unidos)
if r["ok"]:
    var battle := BattleState.new()
    battle.setup_from_scenario(battle_registry, r["scenario"])
```

- **`BattleRequest.build(registry, state, encounter_id)`** valida e devolve o pedido: encontro e província existentes; **exatamente 2 países** (D1), existentes, um deles o do jogador; exércitos existentes, na província do encontro, de países participantes, sem listar o mesmo exército duas vezes nem constar de outro encontro pendente; exércitos com unidades; unidades existentes, do dono do exército, de tipo conhecido, **ids >= 1, sem repetição entre exércitos e sem colisão no estado** (mais de uma instância com o mesmo id é erro). O `request` guarda o instantâneo para etapas futuras: `sides` (país, exércitos e unidades ordenados), `unit_army` (unidade -> exército de origem) e `units` (tipo, categoria, dono, efetivo e moral ANTES da batalha).
- **`BattleScenarioBuilder.build(...)`** valida o mapeamento, o pedido e as categorias, converte as unidades, gera o mapa, posiciona, monta o cenário e o passa pelo `BattleRegistry.validate_scenario` existente (erros viram "Cenário gerado inválido: ..."). Nenhuma unidade é descartada em silêncio: qualquer problema devolve `ok = false` com todos os motivos e **nenhum cenário parcial**.
- Desvio do plano: o mapeamento de **tipos** não foi duplicado em `campaign_mapping.json`; usa-se o `campaign_category` que já existe em `unit_types.json` (validado: cada categoria de campanha precisa ter exatamente um tipo tático). O JSON contém o mapeamento de **terrenos**, o tamanho do mapa e a implantação.

**Conversões e decisões**

| Dado | Regra |
|---|---|
| Tipo | categoria da unidade de campanha (`units.json` `category`) -> tipo tático com o mesmo `campaign_category`: infantry -> infantaria, cavalry -> cavalaria, artillery -> artilharia. Categoria sem tipo (ou ambígua) é erro |
| Efetivo | efetivo **atual** da instância, copiado **sem alteração**. `< 1` é erro (destruída não entra) e **acima do `max_strength` do tipo tático é erro** (nunca é reduzido em silêncio: o resultado tático sempre pode ser comparado com o instantâneo do pedido, sem perda oculta). Hoje a campanha não cria efetivo acima do da definição (500/200/80 = máximos táticos), então o erro só ocorre com dados incoerentes, e a mensagem diz qual unidade e quais valores. `conversion[]` traz o efetivo convertido |
| Moral | moral **atual** da instância, **sem reescalar** (60–70 permanece 60–70 na escala 0–100). `< 1` ou acima de `max_morale` é erro (nunca reduzida em silêncio) |
| Ataque, defesa, alcance, mobilidade | dos dados táticos (a batalha é a autoridade); os valores de campanha não são usados. Experiência e generais: sem efeito |
| `source_id` | id da instância de unidade da campanha. **Suficiente** para identificar a participante: o `GameState` o atribui por `next_unit_id`, que só cresce (**nunca reaproveita** ids, nem depois que unidades forem removidas; testado); o construtor **verifica** a unicidade (repetição entre exércitos, colisão de instâncias, id < 1) e o validador de cenário **rejeita `source_id` repetido** (0 = sem origem, pode repetir). Durante a batalha a unidade tática guarda o `source_id` (unidades destruídas continuam no registro, então o id tático também nunca é reaproveitado) e `BattleState.result_summary()` devolve, por unidade, `unit_id`, `source_id`, estado e efetivo/moral finais: o exército de origem é recuperado por `request.unit_army[source_id]`, **nunca pela posição no array**. O exército de origem não vai no cenário |
| Nome | `"<nome da unidade> #<id>"` |
| Semente | `seed_salt + id do encontro` (cenário e mapa): mesmo encontro e dados = mesmo cenário |
| Limite | `columns x altura` unidades por lado (2 x 9 = 18); acima disso erro, sem descartar |

**Terreno estratégico -> mapa tático** (`data/battle/campaign_mapping.json`, validado contra os dois registros; terreno sem entrada é erro, nunca vira planície): `plains` -> planície com 10% de floresta e 6% de colinas; `hills` -> colinas (12% planície, 5% floresta); `mountains` -> colinas (8% floresta); `forest` -> floresta (12% planície, 4% colinas); `river_valley` -> planície (5% floresta) com **rio** na coluna 6 e **vaus** nas linhas 3 e 6. Cada hexágono consome um sorteio, linha a linha, então o resultado é reproduzível. O rio nunca invade as zonas de implantação (validado).

**Implantação:** jogador a oeste, adversário a leste, nas 2 primeiras colunas de cada borda (`deployment_slots`: coluna mais interna primeiro; em cada coluna do centro para as pontas). Unidades ordenadas por **id do exército e id da unidade** (nunca pela ordem de iteração de dicionários). Os cenários de teste existentes não mudam.

**Exemplo** (encontro em Alsácia, `river_valley`): infantaria francesa #8 (efetivo 320, moral 55) -> `{"side":"player","type":"infantry","at":[1,4],"source_id":8,"strength":320,"morale":55}`; cavalaria #9 (200/65) -> `at [1,3]`; infantaria austríaca #6 (500/70) -> `{"side":"enemy","at":[10,4],"source_id":6}`; artilharia #7 (80/60) -> `at [10,3]`; semente 1001; mapa com rio na coluna 6.

**Decisões e limitações conhecidas (aprovadas na revisão das Etapas 2 e 3):**
- Efetivo ou moral acima do máximo do tipo tático é **erro explícito**, nunca limitado em silêncio. **Não** se introduz `max_strength` por unidade; revisitar só se a campanha passar a criar efetivo acima do máximo tático.
- Uma unidade que entra em batalha com moral <= `rout_threshold` (25) nasce **abalada**, não em retirada; a retirada só começa quando a moral cai por um golpe. Comportamento mantido; **decisão futura:** avaliar se deveria nascer em retirada (não ocorre hoje: a moral inicial da campanha é 60–70).
- `BattleState.add_unit` chamado **diretamente** limita o efetivo ao máximo do tipo sem avisar. Limitação conhecida; não afeta o fluxo por cenário (`setup_from_scenario` valida antes).

### Registro e ciclo de vida das batalhas (Etapa 4; sem interface e sem aplicar resultados)

Prepara um ciclo de vida seguro para as etapas seguintes. **Não** inicia a cena tática, **não** aplica baixas/moral, **não** remove unidades destruídas nem dissolve exércitos, **não** conquista províncias.

**Registro (`GameState.battles`, `next_battle_id`)** — dicionário `id -> registro`, com id inteiro **sequencial** (só é consumido junto com o registro; falha não gasta id; ids nunca são reaproveitados). Cada registro: `id`, `encounter_id`, `province`, `turn` (da campanha), `status`, `countries` [jogador, adversário], `sides` (país, exércitos e unidades por lado), `armies` (todos os participantes, ordenados), `units` (instantâneo **antes** da batalha: `army`, `type`, `category`, `owner`, `strength`, `morale` por id de unidade), `scenario_id` e `scenario` (cópia do cenário tático gerado, para a Etapa 5 iniciar exatamente o que foi validado), `result` (vazio até a Etapa 6) e `history` (`[{status, turn}]`). **Nunca se apaga** uma batalha.

**Estados e transições** (`BattleLifecycle.transition`, a única porta): `active -> applied | cancelled`; `applied` e `cancelled` são **finais**. Constantes em `GameState` (`BATTLE_ACTIVE`, `BATTLE_APPLIED`, `BATTLE_CANCELLED`). Cancelar duas vezes, cancelar uma aplicada, aplicar uma cancelada/aplicada ou usar um estado desconhecido é recusado sem alterar nada (nem o histórico). `check_can_apply(state, id)` é o guarda que a Etapa 6 deve consultar antes de aplicar um resultado: só uma batalha ativa passa, o que impede aplicação duplicada. `applied` existe no ciclo, mas nada o usa ainda.

**Registrar (`BattleLifecycle.register(registry, state, built)`)**, com `built` = resultado ok de `BattleScenarioBuilder.build`: (1) valida que `built` tem `request` e `scenario`; (2) **refaz** `BattleRequest.build` sobre o estado ATUAL (pega encontro inexistente/usado, exército já em batalha e **pedido desatualizado**: o pedido recomputado precisa ser igual ao recebido); (3) confere que o cenário corresponde ao pedido (mesmas unidades por `source_id`, lados, efetivo e moral); (4) confere que o próximo id está livre. **Só depois** de tudo validar faz as atribuições (registro, `next_battle_id`, vínculo no encontro): transacional, sem estado parcial.

**Encontro pendente (decisão):** **não é consumido** ao registrar. Continua em `state.encounters` com o campo `battle_id`. Motivos: (a) se a batalha for cancelada, os exércitos continuam em encontro (estrangeiros na mesma província) sem precisar recriar nada; (b) o vínculo impede uma segunda batalha ativa para o mesmo encontro (`GameState.battle_of_encounter`, recusado em `BattleRequest`); (c) nada a desfazer se algo falhar. Ao cancelar, `battle_id` é removido e o encontro pode iniciar uma nova batalha (id novo). Quando o resultado for aplicado (Etapa 6), o encontro será resolvido/removido. O encontro de uma batalha ativa fica **congelado**: `refresh_encounters` não o descarta e nenhum exército pode entrar na província.

**Bloqueio dos exércitos (somente os participantes, nunca o país inteiro)** — `GameState.battle_of_army` / `ArmyActions.battle_lock_reason`. Todos os pontos de entrada que alteram exércitos passam por `ArmyActions.check_*`, então a regra não depende da interface: `check_move` (exército bloqueado não se move; **nenhum** exército entra na província de uma batalha ativa, para não estender o encontro congelado), `check_add_unit` (incorporar), `check_detach` (separar/remover unidade), `check_assign_general` e `check_unassign_general` (o general faz parte da composição; bloqueio ampliado de propósito), e `incorporate_new_unit` (recruta concluído nunca entra em exército bloqueado; forma outro). `destinations()` e as ações do painel herdam as recusas, com a mensagem "batalha ativa #N". `BattleRequest` recusa encontro com batalha ativa e exército já em batalha ativa, o que impede o mesmo exército em duas batalhas. Fora dos participantes tudo continua livre (recrutar, organizar outros exércitos, formar exércitos).

**Turno:** `TurnProcessor.turn_blockers` (usado na etapa `validate_state`) recusa o encerramento enquanto houver batalha ativa, citando cada uma ("Há uma batalha ativa (#1 em Alsácia): conclua ou cancele..."). A falha usa o mesmo caminho das validações existentes: `ok = false`, `phases = [validate_state]`, **nenhuma alteração** (turno, recursos, filas, exércitos, registro intactos) e o `CampaignController.end_turn` apenas posta a mensagem. Depois de cancelar (ou aplicar) todas as batalhas ativas, o turno volta a avançar. `validate_state` também valida a **integridade** do registro: ids coerentes, estado válido, para batalhas ativas: participantes existentes e na província da batalha, nenhum exército em duas batalhas ativas, composição igual à do instantâneo e encontro ainda vinculado. Revisão técnica: a validação também confere o sentido inverso (todo `battle_id` de um encontro aponta para uma batalha ATIVA daquele encontro; vínculo órfão é erro), exige que o encontro vinculado seja o `encounter_id` da batalha e reporta registros incompletos em vez de falhar em tempo de execução.

**Interface:** só informativa. O painel do exército mostra "Em batalha ativa #N: bloqueado..." e os botões de ação ficam desabilitados com o motivo. Não há botão para iniciar/cancelar batalhas (Etapa 5).

**Limitações conhecidas:** `form_army` (formar exército com unidade da guarnição) e a fila de recrutamento continuam permitidos na província da batalha (não alteram os participantes); o instantâneo e o cenário ficam copiados no registro (cresce com o número de batalhas, o que é aceitável); `applied` ainda não é usado; o bloqueio vale para a campanha do jogador (nenhuma IA move exércitos).

**Fora de escopo (Etapas 5 e 6):** botão/fluxo na interface para iniciar e encerrar a batalha, aplicação de baixas e sobreviventes, dissolução de exércitos vazios, cancelamento, conquista.

## Decisões em aberto

- Grade hexagonal na batalha: **decidido** (axial, pointy-top); ver a seção da batalha tática.
- Equilíbrio da batalha de teste: nas simulações IA contra IA o lado que joga primeiro venceu sempre; ajustar quando houver conteúdo real.
- Formato de salvamento: Fase 6 (o `GameState` já expõe `to_dict()`).

## Testes

```
godot --headless --path . --script res://tests/run_tests.gd
```

O executor roda os testes após o primeiro frame (para os testes de UI terem a árvore de cena) e aceita testes que aguardam frames. Um teste sem nenhuma asserção conta como falha. **Erros de execução contam como falha:** GDScript não tem try/catch e um erro de execução (índice fora do limite, chamada em null, assert) apenas aborta a função do teste, o que antes podia deixar o teste "ok" se ele já tivesse feito alguma asserção. O executor registra um `Logger` (`OS.add_logger`) durante a execução e marca como FALHA, com a mensagem da engine, qualquer teste durante o qual a engine tenha emitido um erro (avisos são ignorados). Um arquivo de teste que não compila, ou que erra ao carregar, também vira falha. Há um relógio de segurança (`WATCHDOG_SECONDS`, 900 s): se a execução passar disso, imprime "tempo esgotado" e sai com código 2. `-- --only=<arquivo em tests/>` roda um único arquivo (usado por `tests/test_runner_detects_errors.gd`, que executa o executor em outro processo contra `tests/fixtures/runtime_error_fixture.gd` para provar que um teste que quebra nunca é reportado como sucesso). Um laço infinito dentro de um teste ainda bloqueia o processo (o relógio não pode interrompê-lo): rode sempre com `timeout 300 ...`.

Qualquer `tests/test_*.gd` que estenda `tests/test_case.gd` é descoberto automaticamente; métodos `test_*` são executados. Código de saída 0 = sucesso; nenhum teste executado conta como falha.
