# HANDOFF — ponto de retomada do projeto

Registro do estado **real** do projeto. Última atualização: 2026-10-29 (Git, arquivos e testes inspecionados e executados nesta sessão).
Instruções permanentes: `CLAUDE.md`. Desenho do jogo: `GAME_DESIGN.md`. Decisões técnicas e regras: `docs/ARCHITECTURE.md`.

## Projeto

- Jogo de estratégia histórica por turnos (Guerras Napoleônicas), inspirado em EU4, Civilization e Total War: Warhammer. Interface em português do Brasil.
- Raiz: `E:\Guerra Total - Brazil` · Godot **4.7.2** (executável na própria pasta, ignorado pelo Git) · GDScript · Windows.
- Git: branch `main`. O remoto `origin` (`https://github.com/joaorodrigues1994/game-guerra-total.git`) existe e, na última conferência (`git rev-parse`, auditoria das Etapas 5, 5.1 e 6), `origin/main` estava em `0ab3f8c`, igual ao `HEAD`: o usuário publicou tudo até a Etapa 4 (e os documentos). O assistente não consegue autenticar no GitHub; o push é feito pelo usuário (`git -c http.sslBackend=schannel push origin main` contorna o erro de certificado só no comando). Fim de linha: o Git avisa "LF will be replaced by CRLF" (normal no Windows; `core.autocrlf=true`, não há `.gitattributes`).

## Histórico de commits

| Commit | Conteúdo |
|---|---|
| `004e341` | Fase 0 — fundação |
| `0a3c834` | Fase 1 — mapa de campanha interativo |
| `fe02b57` | Campanha funcional — economia, construções, recrutamento, turnos |
| `6fa235f` | Exércitos, generais e movimentação estratégica |
| `8c4e6ce` | Docs: HANDOFF.md e CLAUDE.md |
| `1a5e409` | Batalha tática: primeira batalha jogável (independente da campanha) |
| `ff38999` | Batalha: corrige retirada bloqueada por unidades aliadas (Etapa 1 da integração) |
| `5bd1830` | Batalha: API de cenários em memória e sua validação (Etapa 2 da integração) |
| `81b0c28` | Integração: adaptador campanha → batalha e mapeamentos (Etapa 3) |
| (commit seguinte) | Revisão técnica das Etapas 2 e 3: efetivo/moral sem perda silenciosa, `source_id` repetido, executor de testes com detecção de erros de execução, decisões aprovadas |

**Estado do Git:** as Etapas 1 a 4 e as revisões técnicas estão commitadas e **publicadas** (`HEAD` = `origin/main` = `0ab3f8c`). **Nada posterior está commitado**: as Etapas 5 (fluxo campanha -> batalha tática), 5.1 (declaração de guerra) e 6 (aplicação dos resultados táticos), mais os ajustes feitos depois do teste manual (retirada sem rota destrói o exército, mesclar exércitos, recuo do defensor, fim da penalidade de moral por unidade destruída), estão implementados e testados, mas ficam misturados na árvore de trabalho (compartilham arquivos; `battle_flow.gd` e `test_battle_flow.gd` já contêm código das Etapas 5 e 6) e aguardam a revisão e a autorização do usuário (`git status` lista 39 itens na última conferência). Há um backup das alterações antes das correções da auditoria fora do repositório (`C:/Users/Paulo/Backups/GuerraTotal_etapas5-6_antes_das_correcoes`); ele NÃO cobre os ajustes pós-teste manual. Nada além disso foi iniciado (Etapa 7 não existe).

## Estado por funcionalidade

Legenda: **Validada** = testes automatizados passando *e* o usuário confirmou manualmente · **Testada** = testes automatizados passando + capturas de tela reais da janela, mas sem confirmação manual do usuário · **Planejada** = não implementada.

| Funcionalidade | Estado |
|---|---|
| Fundação (Registry com validação, GameState, EventBus, TurnProcessor, testes) | Testada |
| Mapa de campanha (polígonos, fronteiras, nomes, capitais, seleção) | **Validada** |
| Economia, construções, recrutamento de infantaria | **Validada** |
| Exércitos, generais, movimentação, encontros, marcadores no mapa | **Testada** (validação manual do usuário não registrada; o commit foi autorizado) |
| **Batalha tática** (hexágonos, terrenos, turnos, movimento, ataques, moral, retirada, vitória, IA básica, reinício, interface) | **Validada** (o usuário a testou manualmente e a considerou aceitável); commitada em `1a5e409` |
| Correção da retirada bloqueada por aliadas (Etapa 1 da integração) | **Validada** (o usuário validou manualmente); commitada em `ff38999` |
| API de cenários em memória (Etapa 2: `setup_from_scenario`, `validate_scenario`) | **Testada** (18 testes novos; falham sem a validação); revisada e commitada em `5bd1830` |
| Revisão técnica das Etapas 2 e 3 (efetivo/moral sem perda silenciosa, `source_id` repetido, executor de testes) | **Testada** (+6 testes); aprovada pelo usuário e commitada (commit seguinte a `81b0c28`) |
| Camada adaptadora campanha→batalha (Etapa 3: encontro -> cenário tático) | **Testada** (30 testes novos, incluindo mutação). **Revisada e commitada em `81b0c28`.** Somente leitura: não inicia batalha nem altera a campanha |
| **Registro e ciclo de vida das batalhas (Etapa 4):** `GameState.battles`, `BattleLifecycle` (registrar, cancelar, transições), bloqueio dos exércitos participantes, bloqueio do turno | **Testada** (25 testes novos, mutação; revisão técnica da Etapa 4 corrigiu a validação do registro). **Revisada e commitada (`87e2ca6`); push pendente (do usuário).** Sem interface; não aplica resultados |
| **Fluxo campanha→batalha tática (Etapa 5):** `BattleFlow`, botões "Iniciar/Cancelar batalha" no painel da província, cena tática com o cenário registrado, resultado tático registrado | **Testada** (17 testes novos, 3 mutações detectadas). **Não commitada; aguarda revisão.** Sem validação manual do usuário. (Na Etapa 5 o resultado só era registrado; desde a Etapa 6 ele é aplicado ao fim da cena.) |
| Integração campanha↔batalha (registro de batalhas, bloqueios, interface, aplicação do resultado) | **Plano aprovado (decisões D1–D8, abaixo); Etapas 1 a 6 feitas (5.1 incluída). Falta apenas a validação manual do usuário.** A retirada do perdedor foi implementada na Etapa 6 (hoje: destino mais próximo; sem rota o exército é destruído); conquista de província: fora de escopo |
| **Aplicação dos resultados táticos (Etapa 6):** `BattleResolution` (plano somente leitura + aplicação atômica com desfazer), efetivo/moral por `source_id`, remoção de destruídas e de exércitos vazios, retirada determinística (sem rota: exército destruído), `applied` único, botões "Aplicar resultado"/"Cancelar" só em caso de falha | **Testada** (24 testes novos, 5 mutações detectadas; testes da Etapa 5 adaptados). **Não commitada; aguarda revisão.** Sem validação manual do usuário |
| **Declaração de guerra e acesso ao território inimigo (Etapa 5.1):** `GameState.wars`, `WarActions`, `check_move` e encontros só entre países em guerra, botão no painel da província | **Testada** (15 testes novos, 3 mutações detectadas; fixtures antigos passaram a declarar guerra). **Não commitada; aguarda revisão.** Sem validação manual do usuário |
| **Mesclar exércitos** (`ArmyActions.merge_armies`, seção "Mesclar com outro exército" no painel do exército) | **Testada** (5 testes em `tests/test_merge_and_withdraw.gd`, incluindo clique no botão). **Não commitada.** Sem validação manual do usuário |
| **Recuo do defensor sem batalha** (`EncounterRetreat`, botão "Recuar sem batalha" no painel da província) | **Testada** (5 testes no mesmo arquivo). **Não commitada.** Sem validação manual e **inalcançável na partida real**: sem IA de campanha o inimigo nunca entra na província do jogador, então o jogador nunca é o defensor |
| IA estratégica, paz/alianças e demais diplomacia | Planejadas |
| Conteúdo histórico, eventos, mais províncias | Planejados |
| Salvar/carregar, polimento, áudio | Planejados |

## Batalha tática — o que foi feito

- Módulo **independente da campanha** (não toca `GameState`/`Registry`): `src/battle/` (`hex`, `battle_registry`, `battle_map`, `battle_state`, `battle_pathfinding`, `battle_movement`, `battle_combat`, `battle_morale`, `battle_turns`, `battle_ai`, `battle_controller`), interface em `src/ui/battle/`, dados em `data/battle/` (terrenos, tipos militares, regras, cenário `test_battle`), cena `scenes/battle.tscn`.
- Duas formas de abrir: **(a)** cena independente `res://scenes/battle.tscn`; **(b)** botão **"Batalha de teste"** na barra superior da campanha (camada sobre a campanha; "Voltar à campanha" restaura tudo intacto).
- Regras, fórmulas e valores: `docs/ARCHITECTURE.md`, seção "Batalha tática". Resumo: hex axial pointy-top; terrenos planície/floresta/colina/água; infantaria, cavalaria (carga) e artilharia (alcance 2–3, não atira depois de mover); combate corpo a corpo com retaliação e à distância; moral (firme/abalada/em retirada) com efeito real; retirada automática até a borda; vitória por eliminação, quebra (todos em retirada) ou limite de turnos; inimigo determinístico que joga ao fim do turno do jogador; reiniciar restaura tudo.
- Contrato: `BattleState.result_summary()` (saída: por unidade `source_id`, efetivo, moral, `max_morale` e situação) e `BattleState.setup_from_scenario` / `add_unit(..., {strength, morale, source_id})` (entrada). Desde as Etapas 3 a 6 a campanha usa os dois por `src/integration/` (cenário gerado, registro, aplicação do resultado); o módulo da batalha continua sem acessar a campanha.

## Resultados de testes comprovados (execução desta sessão)

Comando (saída capturada, código de saída verificado):

```
"E:/Guerra Total - Brazil/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe" --headless --path "E:/Guerra Total - Brazil" --script res://tests/run_tests.gd
```

- **426 testes, 9034 asserções, 0 falhas** (execução desta sessão de documentação, código de saída 0, stderr vazio): os 416 de antes mais os 10 de `tests/test_merge_and_withdraw.gd` (85 asserções), com o teste da retirada sem rota e os de moral/vitória ajustados às regras atuais (`ally_death_morale_penalty` = 0). Resultado anterior: **416 testes, 8950 asserções, 0 falhas** (após as correções da auditoria das Etapas 5, 5.1 e 6: +2 testes do aviso de falha de aplicação e asserções novas no teste de interface; 2 mutações do aviso detectadas), código de saída 0, saída de erro vazia. Resultado anterior, da Etapa 6: **414 testes, 8914 asserções, 0 falhas** (Etapa 6), código de saída 0, saída de erro vazia. Antes dela: 390 testes e 8421 asserções; a diferença são os 24 testes de `test_battle_resolution` (482 asserções) menos asserções que os testes da Etapa 5 deixaram de ter ao serem adaptados (os que afirmavam "resultado só registrado" passaram à camada de registro; ver `tests/test_battle_flow.gd`). Mutações da Etapa 6 (destruídas não removidas, desempate da retirada invertido, falha final sem desfazer, estado da batalha ignorado, piso de moral removido): as 5 detectadas; restauradas, 0 falhas. Resultado anterior, da Etapa 5.1: **390 testes, 8421 asserções, 0 falhas** (Etapa 5.1; antes dela: 375 testes, 8134 asserções; a diferença são os 15 testes de `test_war`, 172 asserções, mais 115 asserções que os fixtures de guerra acrescentaram aos testes antigos; mutações da 5.1: acesso sem guerra, encontro sem guerra e guerra que não libera o acesso, as 3 detectadas). Resultado anterior, da Etapa 5: **375 testes, 8134 asserções, 0 falhas** (antes dela: 358 testes, 7936 asserções), código de saída 0, saída de erro vazia. A diferença são os 17 testes de `test_battle_flow` (197 asserções) mais 1 asserção do teste que varre `src/` à procura de caminhos absolutos (agora lê também `battle_flow.gd`). Mutação (Etapa 5): sem cancelar na falha de inicialização, sem cancelar ao sair antes do fim e marcando `applied` ao registrar o resultado, as 3 mutações foram detectadas; restauradas, 0 falhas. Resultado anterior, da Etapa 4: **358 testes, 7936 asserções, 0 falhas**, código de saída 0, saída de erro vazia. Comparação com a referência (333 testes, 7485 asserções, 0 falhas, confirmada por nova execução antes de começar a Etapa 4): os 333 continuam passando; somam-se 25 testes novos (`test_battle_lifecycle`; 2 vieram da revisão técnica) e 388 asserções (387 deles + 1 do teste que varre `src/` à procura de caminhos absolutos, que agora também lê `battle_lifecycle.gd`; confirmado comparando as asserções por teste entre o commit anterior e a árvore atual: a única diferença nos testes antigos foi essa).
- Mutação (Etapa 4): sem o bloqueio no movimento, sem o bloqueio do turno, sem a revalidação do pedido, com recrutas entrando em exército bloqueado, e com transições inválidas aceitas, as 5 mutações foram detectadas (falhas nos testes correspondentes); restauradas, 0 falhas.
- Mutação (Etapa 3): com a semente constante, o efetivo trocado pelo máximo e a colisão de ids ignorada, 3 funções de teste falham; restauradas, 0 falhas. (A mutação "limite ignorado" gera erro de índice em tempo de execução; ANTES da revisão o executor a deixava passar com código 0; agora ela é reportada como FALHA, código 1.) Com a validação desligada em `setup_from_scenario` (Etapa 2), 9 funções falham; com o código antigo da retirada, 6.
- Testes da batalha em `tests/` (inclui `test_battle_retreat`, 14, `test_battle_scenario`, 18, e `test_battle_integration`, 30, da camada adaptadora): `test_hex` (9), `test_battle_map` (dados, mapa, caminhos), `test_battle_turns` (movimento, seleção, turnos), `test_battle_combat` (ataques, terreno, tipos, moral), `test_battle_victory` (retirada, vitória, reinício), `test_battle_ai` (IA, controlador), `test_battle_ui` (interface e integração com a campanha). Base compartilhada: `tests/battle_case.gd` (não começa com `test_`, então o executor não a roda como teste).
- A cena principal e a cena da batalha executam sem erros em modo headless (`--quit-after`, sem stderr).
- Foi feita "mutação" manual (quebrar regras de propósito: terreno ignorado, hexágono ocupado aceito, retirada podendo atacar, ações não restauradas, moral inerte): os testes falharam (10 falhas) e voltaram a 0 ao restaurar.
- Simulações IA contra IA (8 sementes): todas terminam em 9–10 turnos; o lado que joga primeiro (jogador) venceu todas — equilíbrio do cenário de teste não foi ajustado.
- **Executor de testes (corrigido na revisão):** erros de execução dentro de um teste agora contam como FALHA (Logger da engine), arquivo que não compila vira falha, e há relógio de segurança (900 s, código 2). Provado por `tests/test_runner_detects_errors.gd` (executa o executor em outro processo contra uma fixture que quebra). Resta: um **laço infinito** dentro de um teste trava o processo; rode sempre com `timeout 300 ...`. Continue conferindo código de saída e stderr.

## Validação visual

- Rodou-se o jogo e a batalha em janela real 1280×720 (Vulkan, RTX 2060) e capturaram-se telas via script (`--script` fora do modo headless + `save_png`). Foram inspecionadas: batalha inicial, unidade selecionada com alcance destacado, movimentos e turno inimigo (registro de combate), painel de resultado. Isso valida desenho e layout, **mas os cliques foram simulados por código**, não com o mouse.
- O usuário validou manualmente: mapa, economia, construções, recrutamento. **Não há validação manual dos exércitos nem da batalha.** O marcador "!" de encontro (campanha) não aparece em nenhuma captura.
- A captura achou e corrigiu: registro de combate invisível (rótulo cortado) — corrigido.

## O que existe (mapa do código)

- `src/core/`: `registry.gd`, `game_state.gd` (**única fonte do estado mutável da campanha**), `event_bus.gd` (autoload).
- `src/campaign/`: `turn_processor.gd`, `campaign_actions.gd`, `war_actions.gd` (declaração de guerra), `campaign_controller.gd`.
- `src/economy/economy_calculator.gd`; `src/units/army_actions.gd`; `src/provinces/` (`map_geometry`, `province_map`).
- `src/battle/`: ver acima (batalha tática).
- `src/integration/`: `battle_request.gd` (valida o encontro e gera o pedido), `battle_scenario_builder.gd` (conversão, mapa, implantação, mapeamento; somente leitura), `battle_lifecycle.gd` (registro/cancelamento/transições), `battle_flow.gd` (encontro -> cena tática -> resultado), `battle_resolution.gd` (aplica o resultado à campanha, com retirada) e `encounter_retreat.gd` (recuo do defensor sem batalha); dados em `data/battle/campaign_mapping.json`.
- `src/ui/`: campanha (`map_view`, `province_panel`, `army_panel`, `top_bar`, `status_bar`, `campaign_screen`, `ui_style`); `src/ui/battle/`: `battle_screen`, `battle_view`, `battle_panel`, `battle_log_panel`, `battle_result_panel`.
- `scenes/`: `main.tscn`/`main.gd` (campanha; jogador fixo: França; `open_test_battle()`/`close_battle()`), `battle.tscn`/`battle.gd` (batalha independente).
- `data/`: `rules`, `countries`, `provinces`, `buildings`, `units`, `generals`, `armies` (campanha) e `data/battle/` (batalha, separado).

## Regras-chave já decididas (detalhes em `docs/ARCHITECTURE.md`)

- Campanha: ordem do turno fixa e testada (`validate_state` → `income_expenses` → `construction_progress` → `recruitment` → `ai_actions` → `military_movement` → `advance_turn` → `army_reset` → `events`); toda ação valida antes de alterar o estado; unidades são instâncias; movimento só por conexões do grafo, 1 por turno, em território próprio ou de país em guerra com o jogador; encontros viram registro em `state.encounters` (só entre países em guerra); exércitos podem ser mesclados (máx. 4 unidades); o defensor de um encontro pode recuar sem batalha se todos os seus exércitos tiverem rota até território próprio; após a batalha o perdedor recua ou, sem rota, é destruído. Batalha tática: perde o lado cujas unidades restantes estão todas em fuga ou fora do campo (eliminação total não é exigida); a destruição de uma unidade não tira moral das aliadas.
- Batalha: ver "Batalha tática" no `docs/ARCHITECTURE.md`.

## Limitações e pendências conhecidas

- **Etapas 5, 5.1 e 6 pendentes de revisão e commit** (misturadas na árvore de trabalho). Os commits até `0ab3f8c` já estão publicados. O assistente não tem credenciais do GitHub (um push anterior falhou com "Invalid username or token"): o push é do usuário.
- Validação manual do usuário ainda não registrada para exércitos e batalha.
- Batalha (integrada à campanha desde as Etapas 3 a 6): a rotina do inimigo é básica; o jogador sempre começa; sem animações, sons, flanqueamento, ordens de formação nem cerco; mapa e cenário únicos (de teste); equilíbrio não ajustado; a artilharia pode ficar sem alvo por ter alcance mínimo 2.
- Aplicação do resultado (Etapa 6): sem conquista/ocupação, sem perseguição nem baixas na retirada, sem experiência/morte de general, sem reposição de tropas; retirada limitada à rota contígua determinística (ver ARCHITECTURE) e, sem rota, o exército é destruído; a moral final inclui a recuperação tática do turno 1; o resultado é aplicado imediatamente ao fim da cena tática; encontro com 3 ou mais países não vira batalha.
- Recuo do defensor: só o jogador o usa e, sem IA de campanha, ele nunca é o defensor numa partida real (só os testes exercitam o botão). Mesclar: depende de o jogador ter dois exércitos na mesma província (o recrutamento incorpora novos recrutas no primeiro exército com vaga; um segundo exército nasce ao separar uma unidade para a guarnição e usar "Formar exército", ou quando o primeiro está cheio).
- Campanha: sem salvar/carregar, sem IA estratégica (outros países não agem), sem seleção de nação (França fixa), sem desfazer/cancelar ordens; sem IA, o inimigo nunca se move (encontro só quando o jogador entra onde há exército inimigo); só existe a declaração de guerra (sem paz); generais só informativos; painel lateral apertado com dois painéis abertos.
- Mapa de campanha quase retangular, sem mar/rios/relevo; fronteiras vizinhas precisam compartilhar vértices exatos.

## Próximos passos sugeridos (a decidir pelo usuário)

1. O usuário revisar as Etapas 5, 5.1 e 6 (misturadas na árvore de trabalho; combinar se vão em 1 ou 3 commits) e autorizar o commit; publicar os commits (push).
2. Depois: paz e demais diplomacia, IA estratégica (inimigos que se movem), conquista/ocupação, reposição e experiência. **Nada disso foi iniciado.** (Texto histórico do plano da integração, já cumprido:)
   **Etapa 4** (plano aprovado, com as decisões D1–D8 abaixo; as Etapas 2 e 3 já existem; a camada `src/integration/` já tem `BattleRequest` e `BattleScenarioBuilder`): registro `GameState.battles`, bloqueio de exércitos e do turno, aplicação do resultado. Descrição original das etapas: camada `src/integration/` (`battle_request`, `battle_scenario_builder`, `data/battle/campaign_mapping.json`); Etapa 4 registro `GameState.battles` + aplicação transacional e idempotente do resultado; Etapa 5 botão "Iniciar batalha" e fluxo de interface; Etapa 6 testes e docs. Resumo do objetivo:
   **integração campanha↔batalha** (Fase 3 do `GAME_DESIGN.md`): a partir de um encontro, montar o cenário (terreno da província, exércitos), jogar a batalha (ou resolver automaticamente) e aplicar o `BattleResult` na campanha (baixas por `source_id`, destruição, controle da província). Antes de implementar, apresentar plano e critérios, como nas etapas anteriores.

### Revisão técnica das Etapas 2 e 3 (resultado)

- **Efetivo acima do máximo tático:** risco CONFIRMADO e corrigido. Antes o construtor limitava o efetivo (900 -> 500) mantendo `ok = true`, enquanto o pedido guardava 900: ao voltar à campanha a unidade pareceria perder 400 homens sem batalha. Agora efetivo ou moral acima do máximo do tipo tático é **erro explícito** (nada é reduzido em silêncio) e a conversão copia os valores exatos. Hoje a campanha não gera esses valores (máximos de campanha = máximos táticos), então só dados incoerentes disparam o erro. Preservar efetivos maiores que o máximo exigiria um `max_strength` por unidade no cenário tático (mudança de modelo): **decidido pelo usuário: NÃO introduzir agora**; manter o erro explícito (revisitar só se a campanha passar a criar efetivo acima do máximo tático).
- **Moral:** sempre cabe (campanha 60–70, máximo 100); `< 1` ou `> max` é erro.
- **IDs:** o mecanismo atual é **suficiente** (instâncias com `next_unit_id` que só cresce; id tático idem; `result_summary` traz `source_id` por unidade). Acrescentado: o validador de cenário agora **rejeita `source_id` repetido** (antes só o construtor checava). Testado: correspondência por `source_id` após mover/destruir/embaralhar, e não reutilização de ids.
- **Executor de testes:** defeito CONFIRMADO (um teste com uma asserção seguida de erro de execução saía "ok", código 0, "0 falhas") e corrigido (Logger + fixture + teste).
- **Verificações da seção de cenários:** terreno desconhecido é erro; geração determinística; cenário validado antes de ser devolvido; campanha intocada em sucesso e falha; excesso de unidades recusado sem erro de execução (agora o teste falha de forma detectável se a checagem for removida). Nenhum defeito novo.
- **Decisões aprovadas pelo usuário sobre as observações (sem alterar regras):** (1) `BattleState.add_unit` chamado **diretamente** continua limitando o efetivo ao máximo do tipo sem avisar; é uma limitação conhecida e documentada, que **não afeta** o fluxo por cenário validado (o validador recusa efetivo acima do máximo antes de `add_unit`). (2) **Moral baixa na entrada:** mantém-se o comportamento atual: uma unidade criada com moral <= 25 nasce "abalada", **não** em retirada (a retirada só começa quando a moral cai por um golpe). **Decisão futura registrada:** avaliar se unidades que já entram abaixo do limite de retirada deveriam nascer em retirada; hoje não ocorre (moral inicial da campanha: 60–70).

### Decisões aprovadas para a integração (D1–D8)

- D1 encontro pendente = gatilho; só 2 países, um deles o do jogador; outros casos recusados. D2 mapa gerado de forma determinística (semente = id do encontro) a partir do terreno da província, via `data/battle/campaign_mapping.json` (montanha → colina; vale fluvial → planície com rio e vaus; sem fortificação). D3 jogador a oeste, inimigo a leste, nas 2 primeiras colunas; limite de 18 unidades por lado. D4 tipo por `campaign_category`; efetivo atual limitado ao máximo; moral da instância sem reescalar; ataque/defesa/alcance dos dados táticos; sem efeito de experiência/general. D5 sobreviventes devolvem efetivo e moral; destruídas são removidas (exército vazio é desfeito, general liberado); fugidas continuam no exército. D6 sem conquista (a retirada forçada do perdedor foi adicionada na Etapa 6); o encontro é resolvido e removido. D7 voltar antes do fim cancela sem efeito. D8 o turno da campanha fica bloqueado durante batalha ativa. Um botão "Criar encontro de teste" rotulado como ferramenta de teste foi proposto para a validação manual.

### Como validar a aplicação do resultado (Etapa 6; ainda NÃO validado pelo usuário)

Parta do roteiro da Etapa 5.1 até o encontro em Baviera (ou Suábia) e **Iniciar batalha**. Anote antes, no painel dos exércitos, o efetivo e a moral de cada unidade (clique no exército).

1. **Vitória com sobreviventes dos dois lados:** jogue a batalha e vença deixando algumas unidades inimigas fugirem (a debandada deixa sobreviventes). No painel de resultado, a nota informa o que mudou: o seu exército permanece; o inimigo "recuou para ...". Volte à campanha: o seu exército continua na província com o efetivo/moral finais; o inimigo está na província dele (clique nela).
2. **Derrota com sobreviventes que recuam:** na batalha, apenas **Encerrar turno** repetidamente (o inimigo ataca). Se restarem unidades suas que fugiram, o exército recua para a província francesa mais próxima (a nota mostra "recuou para ..."); se não houver nenhuma rota até província francesa (todas bloqueadas por exército inimigo ou sem acesso), o exército é destruído ("sem rota de retirada… destruído") e some da campanha.
3. **Derrota com todas as tropas eliminadas:** use um exército de **uma única unidade** (recrute apenas 1 infantaria em Île-de-France e não recrute outra enquanto ela estiver lá: uma segunda unidade seria incorporada ao mesmo exército) e perca a batalha: o exército some da campanha (o painel do exército fecha) e a unidade deixa de existir.
4. **Efetivos visíveis:** em qualquer caso, clique no exército depois: a lista de unidades mostra o efetivo/moral novos; unidades destruídas não aparecem.
5. **Liberação e turno:** os exércitos deixam de aparecer como "Em batalha ativa"; **Encerrar turno** funciona sem cancelar nada.
6. **Falha (opcional, só por teste automatizado):** a falha de aplicação não é reproduzível pela interface sem dados corrompidos; quando ocorre, o painel de resultado da cena mostra o erro em vermelho ("NÃO foi aplicado", "a batalha continua pendente" e as ações "Aplicar resultado"/"Cancelar batalha") e o botão de voltar vira "Voltar à campanha (resultado pendente)". Está coberta por `tests/test_battle_flow.gd` e `tests/test_battle_resolution.gd`. Para ver o painel de nova tentativa, edite temporariamente um resultado num script fora do repositório; não altere os dados da campanha.

Cenário controlado sem tocar nos dados históricos: os testes automatizados criam exércitos e fixam desfechos por `source_id` (`set_outcome` em `tests/integration_case.gd`), sem alterar `data/`.

### Como validar a declaração de guerra e o encontro real (Etapa 5.1; ainda NÃO validado pelo usuário)

Nomes no jogo: a província de Paris chama-se **Île-de-France** (`prov_paris`, tem quartel) e a de Estrasburgo, **Alsácia** (`prov_strasbourg`, SEM quartel: não dá para recrutar infantaria nela). **Suábia** e **Baviera** (a província; o país também se chama Baviera) são bávaras. A França começa sem exércitos; o Exército Bávaro está na província Baviera. Caminho: Île-de-France -> Alsácia -> Suábia -> Baviera.

1. **Turno 1:** clique em Île-de-France, seção "Recrutar": **Infantaria de linha (500 homens) — 2 turnos** (custa 60 de ouro, 20 de materiais e 500 de mão de obra; a França começa com 500/200/1000). **Encerrar turno** duas vezes: no início do turno 3 a unidade conclui e forma um exército em Île-de-France (aparece em "Exércitos na província").
2. **Turno 3:** clique em **Suábia**: o painel mostra "Controlada por Baviera. Em paz com Baviera." e o botão "Declarar guerra a Baviera" (não clique ainda).
3. Selecione o exército (botão na lista de Île-de-France) e mova-o para **Alsácia** (uma província por turno). **Encerrar turno** (turno 4).
4. Selecione o exército em Alsácia: o destino **Suábia** aparece desabilitado com "Sem acesso ao território de Baviera: não há guerra declarada...". Confirme a recusa.
5. Clique em Suábia e **Declarar guerra a Baviera**: a mensagem aparece na barra de status, o painel passa a "Em guerra com Baviera" e o botão some.
6. Selecione o exército de novo: Suábia está habilitada. Mova. **Encerrar turno** (turno 5). Suábia não tem exército bávaro, então ainda não há encontro.
7. Mova o exército de Suábia para **Baviera** (onde está o Exército Bávaro): a mensagem avisa "Encontro pendente" (o marcador "!" no mapa ainda não foi confirmado visualmente).
8. Clique na província **Baviera**: no painel, seção "Encontro #N", **Iniciar batalha**. Jogue até a vitória ou a derrota e use **Voltar à campanha**.
9. Conferir: a guerra continua; a província continua da Baviera (sem conquista); o resultado foi **aplicado** ao terminar a cena (ver o roteiro da Etapa 6 acima para o que observar).

(Outro adversário: Île-de-France -> Francônia -> Boêmia também exige guerra à Baviera, dona da Francônia, e depois à Áustria, dona da Boêmia; por isso o caminho recomendado é o da Baviera.)

### Como validar o fluxo campanha -> batalha manualmente (Etapa 5; ainda NÃO validado pelo usuário)

1. Chegue ao encontro seguindo a seção "Como validar a declaração de guerra e o encontro real" (acima): recrutar em Île-de-France, declarar guerra e mover até a província Baviera; não é preciso nenhum cenário artificial.
2. Clicar na província do encontro: no painel, na seção do encontro, **Iniciar batalha**. A tela tática abre sobre a campanha, com "(batalha #N da campanha)" no título e sem "Reiniciar batalha".
3. Conferir que os exércitos participantes aparecem como "Em batalha ativa #N" e que "Encerrar turno" da campanha recusa.
4. **Cancelar no meio:** "Cancelar batalha e voltar" -> campanha de volta, exércitos livres, o encontro pode iniciar outra batalha.
5. **Jogar até o fim:** o painel de resultado não tem "Jogar novamente" e mostra o que mudou na campanha (Etapa 6); "Voltar à campanha" não cancela nada.

### Como validar a correção da retirada manualmente

Na batalha de teste, deixar uma unidade ficar em retirada (atacá-la repetidamente até a moral cair a 25 ou menos) com aliadas coladas a ela: no início do turno do lado dela, ela deve atravessar as aliadas e seguir para a borda (ou parar no último hexágono livre), sem a mensagem "cercada" quando houver caminho. Inimigos e água continuam barrando.

### Como validar a batalha manualmente (resumo)

1. Abrir o jogo e clicar em **Batalha de teste** na barra superior (ou rodar `res://scenes/battle.tscn`).
2. Clicar numa unidade azul: ver destinos em azul e o painel; clicar num destino para mover; clicar em água/longe para ver a recusa com o motivo.
3. Aproximar-se do inimigo e atacar clicando num alvo vermelho; conferir registro, baixas e moral; **Encerrar turno** para ver o inimigo jogar.
4. Jogar até o resultado; **Jogar novamente**; **Voltar à campanha** confirma que a campanha está intacta.

## Restrições do usuário (valem para toda sessão)

- Etapas pequenas; testes e resultado visual verificados antes de avançar; apresentar plano antes de mudanças extensas.
- Não implementar guerra, diplomacia ou IA estratégica até o usuário pedir; não implementar a integração campanha↔batalha sem pedido.
- Não instalar software, não mudar o renderizador, não sobrescrever arquivos importantes sem inspeção.
- **Nunca commitar nem fazer push sem autorização explícita do usuário** (sempre apresentar o resumo e pedir).
- Preservar `GAME_DESIGN.md`, `docs/ARCHITECTURE.md` (só acréscimos justificados) e as imagens de referência.
- Só adicionar modificações quando explicitamente solicitadas; não iniciar etapa nova sem pedido.
- Nunca declarar testes aprovados sem ver o resultado real; nunca chamar de "validado manualmente" o que só foi testado por código.

## Como retomar

```
cd "E:/Guerra Total - Brazil"
git status                      # Etapas 5, 5.1, 6 e ajustes pós-teste pendentes de commit (39 itens na última conferência)
git log --oneline               # topo: 0ab3f8c (Etapa 4 + docs)
```

Rodar os testes: comando acima (esperado: 426 testes, 9034 asserções, 0 falhas, código de saída 0, stderr vazio).

- Abrir no editor: `"E:/Guerra Total - Brazil/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64.exe" --path "E:/Guerra Total - Brazil" --editor`
- Jogar a campanha: o mesmo executável com `--path "E:/Guerra Total - Brazil"` (sem `--editor`).
- Jogar só a batalha: `"E:/Guerra Total - Brazil/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64.exe" --path "E:/Guerra Total - Brazil" res://scenes/battle.tscn`

## Dicas técnicas aprendidas (evitam retrabalho)

- Sem `class_name`: scripts se referenciam por `const X := preload("res://...")` (o cache de classes globais só existe depois de importar o projeto). Constante de classe-base de teste (`Registry`, `GameState`, `BattleRegistry`...) não pode ser redeclarada na subclasse.
- `Control.set_anchors_preset` **mantém os offsets** (tamanho 0). Para ocupar a área toda use `set_anchors_and_offsets_preset`.
- Rótulos com `autowrap` **e** `clip_text` ficam com altura 0 e somem: não combine os dois.
- Valores de JSON chegam como `float`; estado usa `int`. Em testes, dados montados no código usam `int`: validadores devem aceitar os dois. `:=` não infere tipo de `Variant`: declare (`var x: int = ...`).
- Arredondamento de baixas/moral usa `ceili(x - 0.000001)` para evitar erro de ponto flutuante (110.00000000000001 viraria 111).
- `Array.append_array` não aceita `PackedStringArray` (use laço); `String.join` quer `PackedStringArray`.
- Botões e rótulos dinâmicos: remova com `remove_child` + `queue_free` (o botão pode estar emitindo `pressed`).
- Testes: `tests/test_case.gd` tem `new_game()` e `units_of()`; `tests/battle_case.gd` tem `new_battle()` (campo vazio, variação 0), `put()`, `hx()` e `new_controller()`. O executor roda após o 1º frame e aceita `await`.
- Verificação visual: script temporário (fora do projeto) com `--script` em modo **não** headless chamando `save_png`; nunca deixe esses scripts no repositório.
- Ao editar com Python/heredoc no bash, prefira gravar o script num arquivo (heredocs com aspas/acentos já falharam uma vez).


## Ajustes pós-teste manual (não commitados)

Pedidos pelo usuário depois de testar as Etapas 5, 5.1 e 6 (regras em `GAME_DESIGN.md`; implementação em `docs/ARCHITECTURE.md`, seção "Mesclar exércitos e recuo do defensor"):

- **Retirada sem rota:** o exército derrotado sem província própria alcançável é **destruído** (antes ficava parado e o encontro continuava).
- **Mesclar exércitos** na mesma província (painel do exército).
- **Recuar sem batalha** (painel da província; só o defensor, só com rota para todos os seus exércitos; hoje só alcançável em testes).
- **Moral:** a penalidade para aliadas quando uma unidade é destruída foi zerada (`ally_death_morale_penalty` = 0 em `data/battle/battle_rules.json`; o mecanismo continua no código).
- **Fim da batalha:** a regra original foi mantida (lado perde quando todas as suas unidades restantes estão em fuga ou fora do campo; motivo `rout`), por decisão do usuário para as batalhas não ficarem longas. Uma alternativa "só ao eliminar" foi implementada e **desfeita** a pedido.
- Testes: 426 testes, 9034 asserções, 0 falhas (`tests/test_merge_and_withdraw.gd` tem 10).

### Como validar a mesclagem manualmente (ainda NÃO validada pelo usuário)

1. Recrute duas infantarias em Île-de-France (60 de ouro, 20 de materiais e 500 de mão de obra cada; 2 turnos): elas entram no MESMO exército (limite 4). Para ter dois exércitos: selecione o exército, **Separar para a guarnição** uma unidade e, no painel da província, **Formar exército** com ela.
2. Selecione um dos exércitos: no painel aparece "Mesclar com outro exército" com um botão para o outro. Clique: o outro some, o selecionado fica com todas as unidades. Com general atribuído a ambos, o do absorvido fica livre.
3. Recusas esperadas (botão desabilitado com o motivo): soma acima de 4 unidades, exércitos em encontro ou em batalha.

### Recuo do defensor: como validar

Não é possível na partida real (nenhum país além do jogador se move). Está coberto por `tests/test_merge_and_withdraw.gd` (encontro criado pelo movimento real de um exército austríaco para a Alsácia, onde está o exército francês). Validação manual exigiria IA de campanha ou uma ferramenta de teste: **não implementadas**.
