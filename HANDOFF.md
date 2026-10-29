# HANDOFF — ponto de retomada do projeto

Registro do estado **real** do projeto. Última atualização: 2026-10-29 (Git, arquivos e testes inspecionados e executados nesta sessão).
Instruções permanentes: `CLAUDE.md`. Desenho do jogo: `GAME_DESIGN.md`. Decisões técnicas e regras: `docs/ARCHITECTURE.md`.

## Projeto

- Jogo de estratégia histórica por turnos (Guerras Napoleônicas), inspirado em EU4, Civilization e Total War: Warhammer. Interface em português do Brasil.
- Raiz: `E:\Guerra Total - Brazil` · Godot **4.7.2** (executável na própria pasta, ignorado pelo Git) · GDScript · Windows.
- Git: branch `main`. O remoto `origin` (`https://github.com/joaorodrigues1994/game-guerra-total.git`) está **configurado, mas nada foi enviado**: o push falhou por falta de autenticação (o usuário precisa autenticar; ver "Pendências"). Fim de linha: o Git avisa "LF will be replaced by CRLF" (normal no Windows; não há `.gitattributes`).

## Histórico de commits

| Commit | Conteúdo |
|---|---|
| `004e341` | Fase 0 — fundação |
| `0a3c834` | Fase 1 — mapa de campanha interativo |
| `fe02b57` | Campanha funcional — economia, construções, recrutamento, turnos |
| `6fa235f` | Exércitos, generais e movimentação estratégica |
| `8c4e6ce` | Docs: HANDOFF.md e CLAUDE.md |
| `1a5e409` | Batalha tática: primeira batalha jogável (independente da campanha) |

**Alterações atuais NÃO commitadas (Etapa 1 da integração campanha↔batalha):** correção do defeito de retirada bloqueada por aliadas (`src/battle/battle_turns.gd`), testes novos (`tests/test_battle_retreat.gd`, 14 testes) e uma pequena robustez no executor de testes (`tests/run_tests.gd`). Aguardam a validação manual do usuário e a autorização de commit.

## Estado por funcionalidade

Legenda: **Validada** = testes automatizados passando *e* o usuário confirmou manualmente · **Testada** = testes automatizados passando + capturas de tela reais da janela, mas sem confirmação manual do usuário · **Planejada** = não implementada.

| Funcionalidade | Estado |
|---|---|
| Fundação (Registry com validação, GameState, EventBus, TurnProcessor, testes) | Testada |
| Mapa de campanha (polígonos, fronteiras, nomes, capitais, seleção) | **Validada** |
| Economia, construções, recrutamento de infantaria | **Validada** |
| Exércitos, generais, movimentação, encontros, marcadores no mapa | **Testada** (validação manual do usuário não registrada; o commit foi autorizado) |
| **Batalha tática** (hexágonos, terrenos, turnos, movimento, ataques, moral, retirada, vitória, IA básica, reinício, interface) | **Validada** (o usuário a testou manualmente e a considerou aceitável); commitada em `1a5e409` |
| Correção da retirada bloqueada por aliadas (Etapa 1 da integração) | **Testada** (14 testes novos; os novos falham no código antigo). **Aguarda validação manual; não commitada** |
| Integração campanha↔batalha (iniciar a batalha a partir de um encontro, aplicar baixas) | **Plano aprovado (decisões D1–D8, abaixo); Etapas 2 a 6 NÃO implementadas.** Só o contrato existe. Conquista/retirada do perdedor: fora de escopo |
| IA estratégica, diplomacia, guerra | Planejadas |
| Conteúdo histórico, eventos, mais províncias | Planejados |
| Salvar/carregar, polimento, áudio | Planejados |

## Batalha tática — o que foi feito

- Módulo **independente da campanha** (não toca `GameState`/`Registry`): `src/battle/` (`hex`, `battle_registry`, `battle_map`, `battle_state`, `battle_pathfinding`, `battle_movement`, `battle_combat`, `battle_morale`, `battle_turns`, `battle_ai`, `battle_controller`), interface em `src/ui/battle/`, dados em `data/battle/` (terrenos, tipos militares, regras, cenário `test_battle`), cena `scenes/battle.tscn`.
- Duas formas de abrir: **(a)** cena independente `res://scenes/battle.tscn`; **(b)** botão **"Batalha de teste"** na barra superior da campanha (camada sobre a campanha; "Voltar à campanha" restaura tudo intacto).
- Regras, fórmulas e valores: `docs/ARCHITECTURE.md`, seção "Batalha tática". Resumo: hex axial pointy-top; terrenos planície/floresta/colina/água; infantaria, cavalaria (carga) e artilharia (alcance 2–3, não atira depois de mover); combate corpo a corpo com retaliação e à distância; moral (firme/abalada/em retirada) com efeito real; retirada automática até a borda; vitória por eliminação, quebra (todos em retirada) ou limite de turnos; inimigo determinístico que joga ao fim do turno do jogador; reiniciar restaura tudo.
- Contrato futuro: `BattleState.result_summary()` (= `BattleResult`) e `BattleState.add_unit(..., {strength, morale, source_id})` (entrada). **Não** há ponte com a campanha ainda.

## Resultados de testes comprovados (execução desta sessão)

Comando (saída capturada, código de saída verificado):

```
"E:/Guerra Total - Brazil/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe" --headless --path "E:/Guerra Total - Brazil" --script res://tests/run_tests.gd
```

- **279 testes, 6394 asserções, 0 falhas**, código de saída 0, saída de erro vazia. Comparação com a linha de base anterior (265 testes, 6257 asserções, 0 falhas): os 265 testes anteriores continuam passando sem alteração de conteúdo; somam-se 14 testes e 137 asserções novos (`test_battle_retreat`).
- Com o código ANTIGO de `battle_turns.gd` (antes da correção), a mesma suíte dá 6 falhas, todas nos testes novos da retirada: eles de fato detectam o defeito.
- Testes da batalha em `tests/` (inclui `test_battle_retreat`, 14, da correção da retirada): `test_hex` (9), `test_battle_map` (dados, mapa, caminhos), `test_battle_turns` (movimento, seleção, turnos), `test_battle_combat` (ataques, terreno, tipos, moral), `test_battle_victory` (retirada, vitória, reinício), `test_battle_ai` (IA, controlador), `test_battle_ui` (interface e integração com a campanha). Base compartilhada: `tests/battle_case.gd` (não começa com `test_`, então o executor não a roda como teste).
- A cena principal e a cena da batalha executam sem erros em modo headless (`--quit-after`, sem stderr).
- Foi feita "mutação" manual (quebrar regras de propósito: terreno ignorado, hexágono ocupado aceito, retirada podendo atacar, ações não restauradas, moral inerte): os testes falharam (10 falhas) e voltaram a 0 ao restaurar.
- Simulações IA contra IA (8 sementes): todas terminam em 9–10 turnos; o lado que joga primeiro (jogador) venceu todas — equilíbrio do cenário de teste não foi ajustado.
- **Limitação do executor de testes:** um erro de script em tempo de execução não derruba o executor (só testes sem nenhuma asserção contam como falha). Sempre confira também se o **stderr está vazio**. Um arquivo de teste com erro de sintaxe agora vira uma falha explícita (antes o executor ficava pendurado sem terminar); mesmo assim rode a suíte com limite de tempo (`timeout 240 ...`).

## Validação visual

- Rodou-se o jogo e a batalha em janela real 1280×720 (Vulkan, RTX 2060) e capturaram-se telas via script (`--script` fora do modo headless + `save_png`). Foram inspecionadas: batalha inicial, unidade selecionada com alcance destacado, movimentos e turno inimigo (registro de combate), painel de resultado. Isso valida desenho e layout, **mas os cliques foram simulados por código**, não com o mouse.
- O usuário validou manualmente: mapa, economia, construções, recrutamento. **Não há validação manual dos exércitos nem da batalha.** O marcador "!" de encontro (campanha) não aparece em nenhuma captura.
- A captura achou e corrigiu: registro de combate invisível (rótulo cortado) — corrigido.

## O que existe (mapa do código)

- `src/core/`: `registry.gd`, `game_state.gd` (**única fonte do estado mutável da campanha**), `event_bus.gd` (autoload).
- `src/campaign/`: `turn_processor.gd`, `campaign_actions.gd`, `campaign_controller.gd`.
- `src/economy/economy_calculator.gd`; `src/units/army_actions.gd`; `src/provinces/` (`map_geometry`, `province_map`).
- `src/battle/`: ver acima (batalha tática).
- `src/ui/`: campanha (`map_view`, `province_panel`, `army_panel`, `top_bar`, `status_bar`, `campaign_screen`, `ui_style`); `src/ui/battle/`: `battle_screen`, `battle_view`, `battle_panel`, `battle_log_panel`, `battle_result_panel`.
- `scenes/`: `main.tscn`/`main.gd` (campanha; jogador fixo: França; `open_test_battle()`/`close_battle()`), `battle.tscn`/`battle.gd` (batalha independente).
- `data/`: `rules`, `countries`, `provinces`, `buildings`, `units`, `generals`, `armies` (campanha) e `data/battle/` (batalha, separado).

## Regras-chave já decididas (detalhes em `docs/ARCHITECTURE.md`)

- Campanha: ordem do turno fixa e testada (`validate_state` → `income_expenses` → `construction_progress` → `recruitment` → `ai_actions` → `military_movement` → `advance_turn` → `army_reset` → `events`); toda ação valida antes de alterar o estado; unidades são instâncias; movimento só por conexões do grafo, 1 por turno, só em território próprio; encontros viram registro em `state.encounters`.
- Batalha: ver "Batalha tática" no `docs/ARCHITECTURE.md`.

## Limitações e pendências conhecidas

- **Commit da batalha pendente de autorização.** **Push pendente:** `git push -u origin main` falhou com "Invalid username or token" (e antes com erro de certificado SSL: foi contornado só no comando com `-c http.sslBackend=schannel`, sem mudar a configuração). O usuário precisa autenticar (login do Git Credential Manager ou token com permissão `repo`) e rodar o push, ou autorizar a repetição depois de autenticar.
- Validação manual do usuário ainda não registrada para exércitos e batalha.
- Batalha: sem integração com a campanha (nenhum exército real entra em batalha; nada volta para a campanha); a rotina do inimigo é básica; o jogador sempre começa; sem animações, sons, flanqueamento, ordens de formação nem cerco; mapa e cenário únicos (de teste); equilíbrio não ajustado; a artilharia pode ficar sem alvo por ter alcance mínimo 2.
- Campanha: sem salvar/carregar, sem IA estratégica (outros países não agem), sem seleção de nação (França fixa), sem desfazer/cancelar ordens; encontros só surgem com um estrangeiro já em território próprio; generais só informativos; painel lateral apertado com dois painéis abertos.
- Mapa de campanha quase retangular, sem mar/rios/relevo; fronteiras vizinhas precisam compartilhar vértices exatos.

## Próximos passos sugeridos (a decidir pelo usuário)

1. O usuário validar manualmente a correção da retirada (roteiro abaixo) e os exércitos da campanha.
2. Autorizar o commit da Etapa 1 e resolver a autenticação do push.
3. Só então a **Etapa 2** da integração (plano aprovado, com as decisões D1–D8 abaixo): cenário a partir de dados (`setup_from_scenario`, `source_id`); Etapa 3 camada `src/integration/` (`battle_request`, `battle_scenario_builder`, `data/battle/campaign_mapping.json`); Etapa 4 registro `GameState.battles` + aplicação transacional e idempotente do resultado; Etapa 5 botão "Iniciar batalha" e fluxo de interface; Etapa 6 testes e docs. Resumo do objetivo:
   **integração campanha↔batalha** (Fase 3 do `GAME_DESIGN.md`): a partir de um encontro, montar o cenário (terreno da província, exércitos), jogar a batalha (ou resolver automaticamente) e aplicar o `BattleResult` na campanha (baixas por `source_id`, destruição, controle da província). Antes de implementar, apresentar plano e critérios, como nas etapas anteriores.

### Decisões aprovadas para a integração (D1–D8)

- D1 encontro pendente = gatilho; só 2 países, um deles o do jogador; outros casos recusados. D2 mapa gerado de forma determinística (semente = id do encontro) a partir do terreno da província, via `data/battle/campaign_mapping.json` (montanha → colina; vale fluvial → planície com rio e vaus; sem fortificação). D3 jogador a oeste, inimigo a leste, nas 2 primeiras colunas; limite de 18 unidades por lado. D4 tipo por `campaign_category`; efetivo atual limitado ao máximo; moral da instância sem reescalar; ataque/defesa/alcance dos dados táticos; sem efeito de experiência/general. D5 sobreviventes devolvem efetivo e moral; destruídas são removidas (exército vazio é desfeito, general liberado); fugidas continuam no exército. D6 sem conquista nem retirada forçada; o encontro é resolvido e removido. D7 voltar antes do fim cancela sem efeito. D8 o turno da campanha fica bloqueado durante batalha ativa. Um botão "Criar encontro de teste" rotulado como ferramenta de teste foi proposto para a validação manual.

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
- Nunca declarar testes aprovados sem ver o resultado real; nunca chamar de "validado manualmente" o que só foi testado por código.

## Como retomar

```
cd "E:/Guerra Total - Brazil"
git status                      # alterações da Etapa 1 (retirada) podem estar não commitadas
git log --oneline               # topo: 1a5e409
```

Rodar os testes: comando acima (esperado: 279 testes, 0 falhas, stderr vazio).

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
