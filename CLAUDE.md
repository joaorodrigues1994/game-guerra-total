# CLAUDE.md — instruções permanentes

Jogo de estratégia histórica por turnos (Guerras Napoleônicas) em **Godot 4.7.2 + GDScript**, interface em **português do Brasil**.
**Antes de qualquer trabalho, leia `HANDOFF.md`** (estado real, pendências, próximos passos), depois `GAME_DESIGN.md` e `docs/ARCHITECTURE.md`.

## Regras de trabalho

- Etapas pequenas e verificáveis. Para mudanças extensas, apresente um plano antes. Não implemente sistemas de fases futuras (batalha tática, guerra, diplomacia, IA) sem pedido.
- **Nunca faça commit sem autorização explícita do usuário.** Apresente o resumo das alterações e peça. Não faça push.
- Não instale software, não mude o renderizador, não sobrescreva arquivos sem inspecioná-los.
- Preserve `GAME_DESIGN.md`, `docs/ARCHITECTURE.md` (apenas acréscimos justificados) e as imagens de referência.
- Relate resultados reais: nunca diga que testes passaram sem ver a saída, e não chame de "validado manualmente" o que só foi testado por código.
- Ao fim de cada etapa: rodar testes, conferir o resultado visual quando houver interface, atualizar `docs/ARCHITECTURE.md` (decisões) e `HANDOFF.md` (progresso).

## Comandos

Testes headless (esperado: 0 falhas **e stderr vazio** — o executor não detecta erro de script em tempo de execução):

```
"E:/Guerra Total - Brazil/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe" --headless --path "E:/Guerra Total - Brazil" --script res://tests/run_tests.gd
```

Abrir no editor: `Godot_v4.7.2-stable_win64.exe --path "E:/Guerra Total - Brazil" --editor` · jogar: mesmo executável sem `--editor`.

## Arquitetura (resumo; detalhes em `docs/ARCHITECTURE.md`)

- Dados em `data/*.json`, carregados e validados pelo `Registry`. Estado mutável **só** no `GameState` (única fonte da verdade). Regras em módulos sem nós; a interface lê o estado via `CampaignController` e envia ações — não guarda estado nem regras.
- Toda ação valida antes de alterar o estado e devolve `{ok, message}`; rejeição deixa o estado intacto.
- IDs estáveis em texto (países/províncias/definições) e inteiros para instâncias (unidades, exércitos). Sem `class_name`: use `const X := preload("res://...")`.
- A batalha tática (`src/battle/`, `src/ui/battle/`, `data/battle/`) é um módulo independente da campanha: não acessa `GameState`/`Registry`; a integração futura usa `BattleState.add_unit` (entrada) e `result_summary()` (saída).
- A ordem das etapas do turno é fixa, documentada e testada (`tests/test_turn_order.gd`); mudá-la exige atualizar o doc e o teste.
- Novos testes: `tests/test_*.gd` estendendo `tests/test_case.gd` (métodos `test_*`; helpers `new_game()` e `units_of()`).
