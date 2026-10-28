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
| `battle/` | grade hexagonal, resolução de combate | vazio (Fase 2) |
| `ui/` | `MapView` (mapa e marcadores), `ProvincePanel`, `ArmyPanel`, `TopBar`, `StatusBar`, `CampaignScreen` (leem o estado e chamam o controlador) | Fase 1/campanha/exércitos |

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

## Integração campanha ↔ batalha (planejada)

- `BattleRequest`: exércitos participantes (unidades e efetivos), generais, terreno da província, clima, seed.
- `BattleResult`: vencedor, baixas por unidade, moral final, unidades em retirada, generais mortos/feridos.
- A campanha aplica o resultado **depois** da batalha; a batalha nunca altera o `GameState` diretamente.
- Uma resolução automática usará as mesmas estatísticas, para batalhas entre IAs.

## Decisões em aberto

- Grade hexagonal na batalha: confirmar com protótipo na Fase 2.
- Formato de salvamento: Fase 6 (o `GameState` já expõe `to_dict()`).

## Testes

```
godot --headless --path . --script res://tests/run_tests.gd
```

O executor roda os testes após o primeiro frame (para os testes de UI terem a árvore de cena) e aceita testes que aguardam frames. Um teste sem nenhuma asserção conta como falha. Limitação: um erro de script em tempo de execução não derruba o executor; confira também se o stderr está vazio.

Qualquer `tests/test_*.gd` que estenda `tests/test_case.gd` é descoberto automaticamente; métodos `test_*` são executados. Código de saída 0 = sucesso; nenhum teste executado conta como falha.
