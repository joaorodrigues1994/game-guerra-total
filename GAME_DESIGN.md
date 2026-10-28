# GAME_DESIGN.md
## Projeto: Estratégia Napoleônica

### 1. Visão do projeto

Desenvolver um jogo de estratégia histórica por turnos ambientado nas Guerras Napoleônicas, inspirado em Europa Universalis IV, Civilization e Total War: Warhammer.

O jogador controla uma nação europeia, administra seus recursos, desenvolve províncias, recruta exércitos, estabelece relações diplomáticas e disputa a hegemonia continental.

Quando exércitos inimigos se enfrentam, o jogador pode comandar uma batalha tática em um mapa separado. O resultado deve retornar à campanha e alterar os efetivos militares, o controle territorial e as condições estratégicas.

O projeto será desenvolvido progressivamente com Claude Code, priorizando sistemas funcionais, arquitetura modular, testes e evolução incremental.

### 2. Diretrizes de desenvolvimento

- Plataforma inicial: PC com Windows.
- Engine proposta: Godot 4.
- Linguagem proposta: GDScript.
- Gênero: estratégia histórica por turnos.
- Interface inicialmente em português brasileiro.
- Escopo inicial limitado a um protótipo jogável.
- Não implementar todos os sistemas simultaneamente.
- Utilizar dados configuráveis para países, províncias, unidades, construções e regras.
- Evitar dependências externas desnecessárias.
- Não instalar softwares, sobrescrever arquivos existentes ou realizar alterações destrutivas sem autorização.
- Antes de implementar funcionalidades extensas, apresentar um plano e dividir o trabalho em tarefas verificáveis.
- Ao finalizar cada etapa, executar os testes possíveis e explicar como validar o resultado.

### 3. Referências visuais

#### Mapa de campanha

Utilizar a imagem de referência fornecida pelo usuário como orientação para um mapa estratégico da Europa.

Características desejadas:
- Países identificados por cores distintas.
- Fronteiras e províncias claramente visíveis.
- Nomes de países e localidades.
- Terreno representando mares, rios, montanhas e planícies.
- Marcadores de exércitos e generais.
- Seleção de províncias por clique.
- Painéis com informações econômicas, militares e diplomáticas.
- Movimentação entre províncias conectadas.

A primeira versão pode utilizar polígonos e cores simples. A arte final não é necessária para validar as mecânicas.

#### Mapa de batalha

Utilizar a imagem de referência de batalha fornecida pelo usuário como inspiração para uma apresentação tática em perspectiva isométrica ou 2.5D.

Características desejadas:
- Terreno com campos, rios, estradas, florestas, colinas e cidades.
- Unidades militares representadas por miniaturas ou marcadores visuais.
- Retratos e identificação dos generais.
- Indicação das unidades selecionadas, movimentos possíveis e alcance dos ataques.
- Interface com efetivos, moral, experiência e ordens.
- Cenários com condições iniciais e objetivos específicos.

A primeira versão deve utilizar uma grade hexagonal para movimentação e combate, caso a implementação inicial confirme ser adequada.

### 4. Estrutura do mapa de campanha

O mapa será dividido em províncias.

Cada província deverá possuir:
- Identificador único.
- Nome.
- País controlador.
- Conexões com outras províncias.
- População.
- Produção de recursos.
- Valor econômico.
- Terreno predominante.
- Cidade principal ou capital, quando aplicável.
- Construções.
- Guarnição e presença militar.
- Valor estratégico.

As províncias serão conectadas por uma rede de movimentação. A distância, o terreno, os rios, as estradas e o controle inimigo poderão afetar o movimento.

Conquistar uma província poderá alterar a renda, o recrutamento, a posição estratégica e as relações diplomáticas.

### 5. Sistema de turnos

Cada turno representa inicialmente um mês.

Durante o turno, o jogador poderá:
1. Consultar a situação nacional.
2. Construir ou aprimorar edifícios.
3. Recrutar unidades.
4. Organizar e movimentar exércitos.
5. Executar ações diplomáticas.
6. Administrar os recursos.
7. Encerrar o turno.

Ao encerrar o turno, o jogo deverá processar:
- Receitas e despesas.
- Progresso das construções.
- Recrutamento.
- Abastecimento e manutenção militar.
- Ações dos países controlados pela IA.
- Movimentações militares.
- Eventos e consequências pendentes.

A ordem exata de processamento deverá ser documentada e permanecer consistente.

### 6. Economia

Recursos iniciais propostos:
- Ouro: construções, recrutamento, manutenção e diplomacia.
- Alimentos: sustentação da população e dos exércitos.
- Materiais militares: produção e manutenção de equipamentos.
- População recrutável: limite de expansão militar.
- Prestígio: reputação e influência internacional.

A economia deverá utilizar regras claras, com receitas e despesas consultáveis pelo jogador.

Construções iniciais:
- Fazendas: aumentam a produção de alimentos.
- Mercados: aumentam a renda comercial.
- Oficinas: melhoram a produção de materiais.
- Quartéis: ampliam a capacidade de recrutamento.
- Arsenais: apoiam a produção militar.
- Fortificações: melhoram a defesa de províncias.

Cada construção terá custo, duração, efeitos e eventuais requisitos.

### 7. Sistema militar

Categorias iniciais:

**Infantaria**
- Infantaria de linha.
- Infantaria leve.

**Cavalaria**
- Cavalaria ligeira.
- Cavalaria pesada.

**Artilharia**
- Artilharia de campanha.
- Artilharia pesada.

Cada unidade deverá possuir:
- Custo de recrutamento.
- Custo de manutenção.
- Efetivo.
- Poder de ataque.
- Defesa.
- Mobilidade.
- Alcance, quando aplicável.
- Moral.
- Experiência.
- Requisitos de recrutamento.

Exércitos serão compostos por unidades e comandados por generais. Limites de composição e capacidade de comando poderão ser adicionados posteriormente.

### 8. Generais

Cada general deverá ter:
- Nome.
- Nacionalidade.
- Retrato opcional.
- Habilidade de comando.
- Bônus táticos.
- Experiência.
- Características especiais.

Os atributos dos generais poderão influenciar a moral, a movimentação, a eficácia das unidades e o resultado das batalhas.

### 9. Sistema de batalha

As batalhas ocorrerão em mapas independentes da campanha.

Mecânicas previstas:
- Movimentação por turnos em grade hexagonal.
- Pontos de movimento.
- Ataques corpo a corpo e à distância.
- Alcance e munição da artilharia.
- Moral e possibilidade de retirada.
- Bônus e penalidades de terreno.
- Flanqueamento.
- Efeitos de rios, florestas, colinas e fortificações.
- Objetivos de batalha.
- Condições de vitória e derrota.

A primeira versão deverá conter apenas movimentação, ataque, dano, moral básica e encerramento do combate.

As unidades poderão ser representadas por marcadores simples. Animações e modelos detalhados ficam para etapas posteriores.

Após o combate, o resultado deverá atualizar o estado da campanha, incluindo baixas, unidades destruídas, sobreviventes, generais e controle territorial.

### 10. Diplomacia

Funcionalidades planejadas:
- Relações bilaterais entre países.
- Alianças.
- Tratados comerciais.
- Acordos de passagem militar.
- Declaração de guerra.
- Tratados de paz.
- Influência sobre países menores.
- Coalizões e equilíbrios de poder.

As ações diplomáticas deverão ter custos, requisitos e consequências. Nem toda ação deve ser aceita automaticamente.

O sistema será introduzido depois que a campanha básica e as batalhas estiverem funcionais.

### 11. Inteligência artificial

Os países não controlados pelo jogador serão administrados pela IA.

Inicialmente, a IA deverá:
- Avaliar suas receitas e despesas.
- Construir estruturas úteis.
- Recrutar unidades.
- Defender províncias.
- Avaliar ameaças próximas.
- Movimentar exércitos.
- Atacar quando houver condições favoráveis.

Posteriormente, poderá negociar, formar alianças, criar coalizões e definir objetivos estratégicos.

A IA deve utilizar as mesmas regras fundamentais aplicadas ao jogador, evitando vantagens arbitrárias não configuradas.

### 12. Objetivos e condições de vitória

O jogo deverá suportar diferentes objetivos nacionais, como:
- Conquistar territórios específicos.
- Controlar centros estratégicos.
- Alcançar determinado nível de prestígio.
- Formar alianças ou coalizões.
- Estabelecer hegemonia sobre a Europa.

As condições definitivas de vitória serão definidas após a implementação dos sistemas principais.

### 13. Plano de desenvolvimento

**Fase 0 — Fundação**
- Inspecionar o ambiente.
- Confirmar a instalação e a versão da engine.
- Criar a estrutura inicial do projeto.
- Apresentar a arquitetura e o plano técnico.
- Criar uma primeira cena executável.

**Fase 1 — Campanha básica**
- Mapa com poucas províncias.
- Seleção de províncias.
- Países e recursos.
- Construções simples.
- Recrutamento.
- Avanço dos turnos.

**Fase 2 — Batalha tática**
- Mapa de batalha.
- Grade hexagonal.
- Movimentação e ataques.
- Moral e baixas.
- Condições de vitória.

**Fase 3 — Integração**
- Movimentação de exércitos na campanha.
- Início de batalhas.
- Retorno dos resultados à campanha.
- Conquista de províncias.

**Fase 4 — IA e diplomacia**
- Decisões básicas da IA.
- Relações entre países.
- Alianças e guerras.

**Fase 5 — Conteúdo histórico**
- Mais províncias.
- Nações históricas.
- Generais.
- Eventos e objetivos nacionais.

**Fase 6 — Polimento**
- Interface.
- Arte.
- Animações.
- Áudio.
- Salvamento e carregamento.
- Balanceamento e otimização.

### 14. Requisitos de qualidade

- Manter os sistemas de campanha, combate, economia e diplomacia organizados em módulos.
- Evitar concentrar toda a lógica em um único arquivo.
- Separar dados de jogo e regras de processamento sempre que possível.
- Usar identificadores estáveis para países, províncias e unidades.
- Validar entradas e impedir recursos negativos indevidos.
- Testar as regras econômicas, os turnos e os resultados das batalhas.
- Documentar as decisões arquiteturais relevantes.
- Não implementar funcionalidades futuras antes de concluir os critérios de aceitação da fase atual.

### 15. Critério geral de conclusão do protótipo

O protótipo inicial será considerado funcional quando o jogador conseguir selecionar uma nação, administrar algumas províncias, construir, recrutar, movimentar um exército, participar de uma batalha tática e observar as consequências do resultado na campanha.

A prioridade é criar um ciclo de jogo completo, ainda que pequeno, antes de ampliar o mapa e o conteúdo histórico.
