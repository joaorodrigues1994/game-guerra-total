# HANDOFF — ponto de retomada do projeto

Registro do estado **real** do projeto, verificado em 2026-10-27 (Git, arquivos e testes inspecionados e executados nesta sessão).
Instruções permanentes ficam em `CLAUDE.md`; o desenho do jogo em `GAME_DESIGN.md`; as decisões técnicas em `docs/ARCHITECTURE.md`.

## Correção importante sobre o estado anterior

Foi dito, ao pedir este handoff, que os exércitos/movimentação "ainda não deveriam ser considerados implementados ou testados".
**Isso está desatualizado:** a etapa de exércitos, generais e movimentação **foi implementada, testada e commitada** (`6fa235f`) depois de o usuário autorizar o commit. O que **não** consta é uma validação manual dessa etapa pelo usuário (ver "Validação" abaixo).

## Projeto

- Jogo de estratégia histórica por turnos (Guerras Napoleônicas), inspirado em EU4, Civilization e Total War: Warhammer. Interface em português do Brasil.
- Raiz: `E:\Guerra Total - Brazil` · Godot **4.7.2** (executável na própria pasta, ignorado pelo Git) · GDScript · Windows.
- Git: branch `main`, **sem remoto** (nada foi enviado a lugar algum). Fim de linha: o Git avisa "LF will be replaced by CRLF" (normal no Windows; não há `.gitattributes`).

## Histórico de commits

| Commit | Conteúdo |
|---|---|
| `004e341` | Fase 0 — fundação: `project.godot`, `Registry`, `GameState`, `EventBus`, esqueleto do `TurnProcessor`, JSON de exemplo, testes headless |
| `0a3c834` | Fase 1 — mapa de campanha interativo (9 províncias, 3 países, seleção por clique, painéis) |
| `fe02b57` | Campanha funcional — economia, construções, recrutamento, turnos |
| `6fa235f` | Exércitos, generais e movimentação estratégica |

Árvore de trabalho limpa no momento da verificação (nenhuma alteração pendente antes deste handoff).

## Estado por funcionalidade

Legenda: **Validada** = testes automatizados passando *e* o usuário confirmou manualmente · **Testada** = testes automatizados passando + capturas de tela reais da janela, mas sem confirmação manual do usuário · **Planejada** = não implementada.

| Funcionalidade | Estado |
|---|---|
| Fundação (Registry com validação, GameState, EventBus, TurnProcessor, testes) | Testada |
| Mapa de campanha (polígonos, fronteiras, nomes, capitais, seleção por clique) | **Validada** (usuário confirmou) |
| Economia (receitas por província, manutenção, recursos nunca negativos) | **Validada** (usuário confirmou) |
| Construções (fila, custo, progresso por turnos, efeitos) | **Validada** (usuário confirmou) |
| Recrutamento de infantaria de linha | **Validada** (usuário confirmou) |
| Exércitos, generais, movimentação, encontros, marcadores no mapa | **Testada** (156 testes + capturas); **validação manual do usuário não registrada** |
| Batalha tática (grade hexagonal, combate, moral) | Planejada (Fase 2 do `GAME_DESIGN.md`) |
| Integração campanha↔batalha (conquista, retorno de resultados) | Planejada (Fase 3) |
| IA estratégica, diplomacia, guerra | Planejadas (Fase 4) |
| Conteúdo histórico, eventos, mais províncias | Planejados (Fase 5) |
| Salvar/carregar, polimento, áudio | Planejados (Fase 6) |

Observação de nomenclatura: o `GAME_DESIGN.md` numera as fases 0–6. Fase 0 e Fase 1 seguem essa numeração; "campanha funcional" e "exércitos" foram etapas pedidas à parte, que cobrem partes do que o documento chamava de Fases 1 e 3.

## Resultados de testes comprovados (execução desta sessão)

Comando (saída capturada, código de saída verificado):

```
"E:/Guerra Total - Brazil/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe" --headless --path "E:/Guerra Total - Brazil" --script res://tests/run_tests.gd
```

- **156 testes, 1065 asserções, 0 falhas**, código de saída 0, saída de erro vazia.
- Por arquivo: `test_armies` 27 · `test_army_movement` 17 · `test_army_ui` 14 · `test_campaign_controller` 23 · `test_campaign_ui` 14 · `test_construction` 12 · `test_economy` 6 · `test_map_data` 16 · `test_recruitment` 9 · `test_registry` 10 · `test_turn_order` 8.
- A cena principal também executa sem erros em modo headless (`--headless --path ... --quit-after 10`, código 0, sem stderr).
- Foi feita "mutação" manual (quebrar regras de propósito) nas etapas de economia e de exércitos: os testes falharam como esperado e voltaram a 0 falhas ao restaurar.
- **Limitação do executor de testes:** um erro de script em tempo de execução não derruba o executor (só testes sem nenhuma asserção contam como falha). Sempre confira também se o **stderr está vazio**.

## Validação visual

- Rodou-se o jogo em janela real 1280×720 (Vulkan, RTX 2060) e capturaram-se telas via script (`--script` fora do modo headless + `get_viewport().get_texture().get_image().save_png`). Isso valida o desenho e o layout, **mas os cliques foram simulados por código** (eventos injetados), não com o mouse.
- O usuário validou manualmente: mapa, economia, construções, recrutamento. **Não há registro de validação manual dos exércitos.** O marcador "!" de encontro foi coberto por teste de lógica, mas não aparece em nenhuma captura.

## O que existe (mapa do código)

- `src/core/`: `registry.gd` (carrega e valida `data/*.json`), `game_state.gd` (**única fonte do estado mutável**), `event_bus.gd` (autoload `EventBus`).
- `src/campaign/`: `turn_processor.gd` (ordem fixa de etapas), `campaign_actions.gd` (construir/recrutar, validam antes de alterar), `campaign_controller.gd` (seleção, ações do jogador, dados prontos para a interface, sinais `state_changed`, `selection_changed`, `army_selection_changed`, `turn_ended`, `message_posted`).
- `src/economy/economy_calculator.gd`: receitas, manutenção e bônus (só leitura).
- `src/units/army_actions.gd`: exércitos, generais, movimentação, encontros.
- `src/provinces/`: `map_geometry.gd` (geometria pura), `province_map.gd` (polígonos, teste de clique, fronteiras).
- `src/ui/`: `map_view` (mapa + marcadores), `province_panel`, `army_panel`, `top_bar`, `status_bar`, `campaign_screen`, `ui_style`.
- `scenes/main.tscn` + `main.gd`: carrega dados, cria estado e controlador, monta a tela. Jogador fixo: **França** (`fra`).
- `data/`: `rules`, `countries`, `provinces` (com `map.polygon`/`map.label`), `buildings`, `units`, `generals`, `armies` (exércitos iniciais).
- `src/battle/` e `src/core/commands/`: vazias (reservadas).

Dados atuais (de exemplo, **não são históricos**): 3 países (França, Baviera, Áustria), 9 províncias, 3 unidades (só infantaria de linha é recrutável), 6 construções (Arsenal com `buildable: false`), 5 generais, 3 exércitos iniciais (Áustria 2, Baviera 1; a França começa sem exército).

## Regras-chave já decididas (detalhes em `docs/ARCHITECTURE.md`)

- Ordem do turno (fixa e testada): `validate_state` → `income_expenses` → `construction_progress` → `recruitment` → `ai_actions` (vazia) → `military_movement` (vazia) → `advance_turn` → `army_reset` → `events`. Receita é calculada sobre o estado do início do turno (sem receita retroativa).
- Toda ação valida **antes** de alterar o estado; rejeitada = estado intacto + mensagem em português.
- Unidades são **instâncias** (`id` inteiro, `type` = definição); `armies[id].units` é a única fonte de pertencimento; efetivo do exército é calculado.
- Movimento: só por conexões do grafo lógico, 1 província por exército por turno, só em território **próprio** (sem guerra/diplomacia); encontro com exército estrangeiro vira registro em `state.encounters` e imobiliza os envolvidos.
- Recrutas concluídos entram no primeiro exército próprio da província com vaga, senão formam um novo. Limite: `rules.max_army_units` = 4.

## Limitações e pendências conhecidas

- Validação manual do usuário para a etapa de exércitos ainda **não registrada**.
- Sem guerra/diplomacia, encontros só surgem se um exército estrangeiro já estiver em território próprio (não acontece na partida inicial).
- Sem salvar/carregar, sem IA (outros países não agem), sem seleção de nação (jogador fixo na França), sem desfazer/cancelar ordens.
- Generais são só informativos (sem bônus), sem recrutamento nem progressão.
- Painel lateral fica apertado quando painel da província e do exército estão abertos (rola).
- Mapa quase retangular, sem mar/rios/relevo desenhados; polígonos feitos à mão (fronteiras vizinhas precisam compartilhar vértices exatos).
- Sem remoto Git; nada de push.

## Próximos passos sugeridos (a decidir pelo usuário)

1. O usuário validar manualmente os exércitos (roteiro na resposta da etapa; resumo: recrutar → 2 turnos → clicar no marcador → mover para Alsácia → tentar mover de novo → encerrar turno → mover de novo; separar/incorporar unidades; atribuir general).
2. Corrigir o que a validação manual apontar (ainda dentro desta etapa).
3. Só então, a próxima etapa do `GAME_DESIGN.md`: **batalha tática** (Fase 2) — grade hexagonal, movimento, ataque, moral, condições de vitória — consumindo o contrato de encontro (`state.encounters`) e devolvendo um `BattleResult`. Antes de implementar, apresentar plano e critérios, como nas etapas anteriores.

## Restrições do usuário (valem para toda sessão)

- Etapas pequenas; testes e resultado visual verificados antes de avançar; apresentar plano antes de mudanças extensas.
- Não implementar batalhas, guerra, diplomacia ou IA até o usuário pedir.
- Não instalar software, não mudar o renderizador, não sobrescrever arquivos importantes sem inspeção.
- **Nunca commitar sem autorização explícita** do usuário (sempre apresentar o resumo e pedir).
- Preservar `GAME_DESIGN.md`, `docs/ARCHITECTURE.md` (só acréscimos justificados) e as imagens de referência.
- Nunca declarar testes aprovados sem ver o resultado real; nunca chamar de "validado manualmente" o que só foi testado por código.

## Como retomar

```
cd "E:/Guerra Total - Brazil"
git status                      # deve estar limpo (exceto este HANDOFF.md/CLAUDE.md, se ainda não commitados)
git log --oneline               # topo: 6fa235f
```

Rodar os testes: comando acima (esperado: 156 testes, 0 falhas, stderr vazio).

Abrir no editor: `"E:/Guerra Total - Brazil/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64.exe" --path "E:/Guerra Total - Brazil" --editor`
Jogar direto: o mesmo executável com `--path "E:/Guerra Total - Brazil"` (sem `--editor`).

## Dicas técnicas aprendidas (evitam retrabalho)

- Sem `class_name`: scripts se referenciam por `const X := preload("res://...")` (o cache de classes globais só existe depois de importar o projeto).
- `Control.set_anchors_preset` **mantém os offsets** (tamanho 0). Para ocupar a área toda use `set_anchors_and_offsets_preset`.
- Valores de JSON chegam como `float`; estado usa `int` (converter explicitamente). Inferência `:=` falha com `Variant`: declare o tipo (`var x: int = ...`).
- `Array.append_array` não aceita `PackedStringArray` (use laço); `String.join` quer `PackedStringArray`.
- Botões e rótulos são reconstruídos a cada atualização; remova com `remove_child` + `queue_free` (o botão pode estar emitindo `pressed`).
- Testes: `tests/test_case.gd` tem `new_game()` (partida real) e `units_of(state, país)` (Áustria e Baviera já começam com unidades). O executor roda após o 1º frame e aceita `await`.
- Verificação visual: script temporário (fora do projeto) com `--script` em modo **não** headless, chamando `save_png`; nunca deixe esses scripts no repositório.
- Ao editar com Python/heredoc no bash, prefira gravar o script num arquivo (heredocs com aspas/acentos já falharam uma vez).
