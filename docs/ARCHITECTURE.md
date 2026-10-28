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
| `campaign/` | `TurnProcessor` (esqueleto), `CampaignController` (seleção e dados de exibição) | Fase 1 |
| `economy/` | receitas, despesas, construção, recrutamento | vazio (Fase 1) |
| `units/` | unidades, exércitos, generais | vazio (Fase 1/3) |
| `provinces/` | `MapGeometry` (geometria pura), `ProvinceMap` (polígonos, teste de clique, fronteiras) | Fase 1 |
| `battle/` | grade hexagonal, resolução de combate | vazio (Fase 2) |
| `ui/` | `MapView`, `ProvincePanel`, `TopBar`, `CampaignScreen` (somente leem o estado via controlador) | Fase 1 |

## Dados (`data/`)

| Arquivo | Conteúdo |
|---|---|
| `rules.json` | data inicial, recursos, terrenos, categorias de unidade, tipos de ligação |
| `countries.json` | id, nome, cor, capital, recursos iniciais |
| `provinces.json` | dono, vizinhos tipados, população, produção, terreno, cidade, construções, guarnição, valor estratégico |
| `units.json` | custos, manutenção, efetivo, ataque, defesa, mobilidade, alcance, moral, experiência, requisitos |
| `buildings.json` | custo, duração, efeitos, requisitos |

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

O executor roda os testes após o primeiro frame (para os testes de UI terem a árvore de cena) e aceita testes que aguardam frames. Um teste sem nenhuma asserção conta como falha. Limitação: um erro de script em tempo de execução não derruba o executor; confira também se o stderr está vazio.

Qualquer `tests/test_*.gd` que estenda `tests/test_case.gd` é descoberto automaticamente; métodos `test_*` são executados. Código de saída 0 = sucesso; nenhum teste executado conta como falha.
