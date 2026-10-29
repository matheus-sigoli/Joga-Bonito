# PRD-001 — Rebranding e Reestruturação: Joga Bonito (Futebol & Artigos Esportivos)

## 1. Contexto & Problema
O projeto acadêmico PIM IV (UNIP 2026.2) anteriormente utilizava o estudo de caso "Froggy Streetwear". O Operador definiu um novo direcionamento estratégico e reposicionamento de mercado para uma marca focada em **futebol e artigos esportivos**, denominada **Joga Bonito**.
A transição visa capturar a paixão nacional pelo futebol, o retorno das camisas históricas e a febre do vestuário esportivo urbano ("blokecore"), mantendo toda a arquitetura técnica já estabelecida (Front Vanilla, Back .NET 8, SQL Server Express, JWT e mobile planejado).

## 2. Público-Alvo & Personas
- **Apaixonados por Futebol & Torcedores (16-45 anos)**: Buscam mantos oficiais da temporada 2026 para torcer e colecionar.
- **Entusiastas da Cultura Retrô & Nostalgia**: Admiradores de camisas históricas (Copas do Mundo, finais memoráveis, lendas como Ronaldinho, Romário, Ronaldo, Zidane).
- **Praticantes de Esporte Amador & Futsal/Society**: Buscam artigos funcionais (bolas profissionais, chuteiras, corta-ventos, meias e acessórios de jogo).

## 3. Identidade Visual & Cores Oficiais
- **Cores Oficiais**:
  - Verde Campo / Gramado Real: `#0E552A`
  - Amarelo Canarinho / Ouro: `#FCCA0F`
  - Escuro de Fundo / Estádio Noturno: `#060d09` a `#0d2315`
  - Contrastes: Branco Puro `#FFFFFF`, Cinza Neutro `#E2E8F0`
- **Assets de Marca (Localizados em `Site/IMG/`)**:
  - `LOGO.png`: Logotipo Principal (Escudo JB + Coroa Ouro + Bola + "JOGABONITO ARTIGOS ESPORTIVOS").
  - `LOGO 2.png`: Emblema/Brasão isolado para Favicon, avatares e ícones.
  - `LOGO 3.png`: Tipografia/Wordmark horizontal ("JOGA BONITO" em verde e amarelo).

## 4. Reestruturação do Catálogo de Produtos
O catálogo substitui as antigas categorias da Froggy pelas 3 macrocategorias de futebol:

### Categoria 1: Camisetas Atuais (Temporada 2026)
- Camisa Seleção Brasileira 2026 - Manto Mandante Amarelo Canarinho
- Camisa Real Madrid 2026 - Home Oficial Branca e Dourada
- Camisa Arsenal 2026 - Home Edição Especial Vermelha e Branca

### Categoria 2: Camisetas Retrô (Clássicas & Históricas)
- Camisa Brasil Retrô 1998 / 2002 - O Manto da Conquista
- Camisa Milan Retrô 2007 - Clássica Rubro-Negra Lendária
- Camisa Boca Juniors Retrô 1995 - Ícone Sul-Americano Azul e Ouro

### Categoria 3: Artigos Esportivos & Acessórios
- Bola de Futebol Oficial Joga Bonito Pro (Termocolada FIFA Quality)
- Jaqueta Corta-Vento Treino Pro - Verde e Amarela com zíper selado
- Chuteira Society Pro Grip - Conforto e tração para grama sintética

## 5. Escopo da Entrega
- [x] Atualização da documentação central do projeto (`contexto-projeto.md` em Maestro e Site).
- [x] Criação do Design System oficial no padrão Verde `#0E552A` e Amarelo `#FCCA0F`.
- [x] Atualização de todos os CSS do portal (`inicial.css`, `produtos.css`, `carrinho.css`, `pedidos.css`, `auth.css`, `banco-dashboard.css`).
- [x] Atualização das páginas HTML com novos logos, títulos, seções e produtos.
- [x] Atualização da base de dados e seed (`seed.sql` e fallback da API) com o catálogo de futebol.
- [x] Manutenção integral das regras de negócio (carrinho, autenticação, pedidos e dashboard de estoque).

## 6. KPIs & Critérios de Sucesso
- 100% de consistência na identidade visual Verde e Amarela em todas as telas.
- Eliminação de qualquer menção legada à marca antiga no frontend da loja.
- Carregamento e renderização fluida no catálogo e nos detalhes de produto.
