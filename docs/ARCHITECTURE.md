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
| `core/` | `GameState`, `EventBus` (autoload), `Registry` | Fase 0 |
| `campaign/` | `TurnProcessor`, grafo de províncias | esqueleto de turnos |
| `economy/` | receitas, despesas, construção, recrutamento | vazio (Fase 1) |
| `units/` | unidades, exércitos, generais | vazio (Fase 1/3) |
| `provinces/` | modelo de província | vazio (Fase 1) |
| `battle/` | grade hexagonal, resolução de combate | vazio (Fase 2) |
| `ui/` | painéis e HUD (somente leitura do estado) | vazio (Fase 1) |

## Dados (`data/`)

| Arquivo | Conteúdo |
|---|---|
| `rules.json` | data inicial, recursos, terrenos, categorias de unidade, tipos de ligação |
| `countries.json` | id, nome, cor, capital, recursos iniciais |
| `provinces.json` | dono, vizinhos tipados, população, produção, terreno, cidade, construções, guarnição, valor estratégico |
| `units.json` | custos, manutenção, efetivo, ataque, defesa, mobilidade, alcance, moral, experiência, requisitos |
| `buildings.json` | custo, duração, efeitos, requisitos |

Os arquivos atuais são **dados de exemplo** (2 países, 3 províncias, 3 unidades, 6 construções) apenas para validar o carregamento. Polígonos de mapa serão adicionados na Fase 1.

O `Registry` valida ao carregar: ids únicos, referências existentes (dono, capital, vizinhos, construções), ligações recíprocas e do mesmo tipo, terrenos/categorias/recursos conhecidos, números não negativos. Erros ficam em `Registry.errors`.

Os JSON numéricos são lidos como `float` pelo Godot; ao usar valores como inteiros, converter explicitamente.

## Ordem de processamento do turno

Fixa e coberta por `tests/test_turn_order.gd`. Qualquer mudança exige atualizar este documento e o teste.

1. `income_expenses` — receitas e despesas
2. `construction_progress` — progresso das construções
3. `recruitment` — recrutamento
4. `supply_upkeep` — abastecimento e manutenção militar
5. `ai_actions` — ações dos países controlados pela IA
6. `military_movement` — movimentações militares
7. `events` — eventos e consequências pendentes

Na Fase 0 o `TurnProcessor` apenas percorre as etapas e emite `EventBus.turn_phase_processed`; nenhuma regra é executada.

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

Qualquer `tests/test_*.gd` que estenda `tests/test_case.gd` é descoberto automaticamente; métodos `test_*` são executados. Código de saída 0 = sucesso; nenhum teste executado conta como falha.
