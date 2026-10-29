-- ============================================================================
-- JOGA BONITO — CARGA DE DADOS ESSENCIAIS (SEED) · SQL SERVER
-- PIM IV · UNIP 2026/2
-- Executado a cada inicialização da API (ou manualmente). Idempotente e
-- incremental: só insere o que falta e nunca duplica categorias, produtos,
-- estoque ou cupons. Contas e pedidos de demonstração ficam em demo.sql,
-- que NÃO é carregado em produção.
-- ============================================================================

-- Índices filtrados exigem estas opções; o sqlcmd vem com QUOTED_IDENTIFIER OFF
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ----------------------------------------------------------------------------
-- 1. CATEGORIAS (insere as que faltam, pelo slug)
-- ----------------------------------------------------------------------------
INSERT INTO dbo.Categorias (Nome, Slug, Descricao)
SELECT N.Nome, N.Slug, N.Descricao
FROM (VALUES
    ('Temporada 2026', 'temporada-2026', 'Camisas oficiais de clubes e seleções da temporada 2026'),
    ('Camisas Retrô',  'retro',          'Camisas históricas de Copas do Mundo, finais e craques inesquecíveis'),
    ('Chuteiras',      'chuteiras',      'Chuteiras de campo, society e futsal')
) N(Nome, Slug, Descricao)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Categorias C WHERE C.Slug = N.Slug);
GO

-- <catalogo>  (gerado por ferramentas/gerar_catalogo.py — não edite à mão)
-- ----------------------------------------------------------------------------
-- 2. PRODUTOS E GALERIA — 36 itens: 12 Temporada 2026 · 12 Retrô · 12 Chuteiras
--    Carga INCREMENTAL e versionada:
--      * produtos que faltam são inseridos (banco novo ou banco antigo com menos itens);
--      * se a versão do catálogo mudou, os produtos 1-36 recebem nome, preço, imagens etc.
--        novos e a galeria é refeita; se não mudou, nada é alterado (edições do painel ficam);
--      * a versão fica numa propriedade estendida da tabela Produtos (CatalogoVersao).
-- ----------------------------------------------------------------------------
SET XACT_ABORT ON;
DECLARE @VersaoCatalogo NVARCHAR(20) = N'239056bfff27';
DECLARE @VersaoAtual NVARCHAR(20) = (
    SELECT CAST(value AS NVARCHAR(20)) FROM sys.extended_properties
    WHERE major_id = OBJECT_ID('dbo.Produtos') AND minor_id = 0 AND name = 'CatalogoVersao');
DECLARE @Temp INT  = (SELECT Id FROM dbo.Categorias WHERE Slug = 'temporada-2026');
DECLARE @Retro INT = (SELECT Id FROM dbo.Categorias WHERE Slug = 'retro');
DECLARE @Chut INT  = (SELECT Id FROM dbo.Categorias WHERE Slug = 'chuteiras');

DECLARE @Catalogo TABLE (
    Id INT PRIMARY KEY, CategoriaId INT, Nome VARCHAR(100), Modelo VARCHAR(100), Linha VARCHAR(20),
    Equipe VARCHAR(60), Ano SMALLINT, Marca VARCHAR(40), Solado VARCHAR(40), Descricao VARCHAR(1000),
    Preco DECIMAL(10,2), PrecoPromocional DECIMAL(10,2), Imagem VARCHAR(200), Destaque BIT);
INSERT INTO @Catalogo VALUES
    (1, @Temp, 'Camisa Brasil 2026 Home', 'Torcedor · Temporada 2026', 'Seleção', 'Brasil', 2026, NULL, NULL, 'A amarelinha da temporada 2026: base canarinho, gola e punhos em verde e tecido leve de secagem rápida. Escudo bordado e modelagem regular.', 349.90, NULL, '../IMG/Produtos/1/1.jpg', 1),
    (2, @Temp, 'Camisa Argentina 2026 Home', 'Torcedor · Temporada 2026', 'Seleção', 'Argentina', 2026, NULL, NULL, 'As listras alvicelestes da campeã do mundo em versão 2026, com detalhes em azul-marinho e tecido respirável.', 349.90, NULL, '../IMG/Produtos/2/1.jpg', 0),
    (3, @Temp, 'Camisa Portugal 2026 Home', 'Torcedor · Temporada 2026', 'Seleção', 'Portugal', 2026, NULL, NULL, 'O vermelho da seleção portuguesa com acabamentos em verde, gola careca e tecido de alta ventilação.', 349.90, NULL, '../IMG/Produtos/3/1.jpg', 0),
    (4, @Temp, 'Camisa França 2026 Home', 'Torcedor · Temporada 2026', 'Seleção', 'França', 2026, NULL, NULL, 'O azul-marinho dos Bleus com detalhes em vermelho e branco. Tecido leve e caimento moderno.', 349.90, NULL, '../IMG/Produtos/4/1.jpg', 0),
    (5, @Temp, 'Camisa Espanha 2026 Home', 'Torcedor · Temporada 2026', 'Seleção', 'Espanha', 2026, NULL, NULL, 'O vermelho da Fúria em versão 2026, com mangas em azul-marinho e detalhes em amarelo. Tecido leve e respirável.', 329.90, NULL, '../IMG/Produtos/5/1.jpg', 0),
    (6, @Temp, 'Camisa Flamengo 2026 Home', 'Torcedor · Temporada 2026', 'Clube', 'Flamengo', 2026, NULL, NULL, 'O manto rubro-negro de listras horizontais da temporada 2026, com tecido de secagem rápida e escudo bordado.', 349.90, NULL, '../IMG/Produtos/6/1.jpg', 1),
    (7, @Temp, 'Camisa Corinthians 2026/27 Home', 'Torcedor · Temporada 2026', 'Clube', 'Corinthians', 2026, NULL, NULL, 'O manto alvinegro 2026/27: base branca, detalhes em preto e tecido de alta respirabilidade.', 349.90, NULL, '../IMG/Produtos/7/1.jpg', 1),
    (8, @Temp, 'Camisa Palmeiras 2026 Home', 'Torcedor · Temporada 2026', 'Clube', 'Palmeiras', 2026, NULL, NULL, 'O verde alviverde da temporada 2026 com detalhes em branco, gola careca e tecido leve.', 349.90, NULL, '../IMG/Produtos/8/1.jpg', 0),
    (9, @Temp, 'Camisa Real Madrid 2026/27 Home', 'Torcedor · Temporada 2026', 'Clube', 'Real Madrid', 2026, NULL, NULL, 'O branco merengue 2026/27 com acabamentos em dourado e tecido com controle de suor. Escudo termoaplicado.', 399.90, NULL, '../IMG/Produtos/9/1.jpg', 1),
    (10, @Temp, 'Camisa Barcelona 2026/27 Home', 'Torcedor · Temporada 2026', 'Clube', 'Barcelona', 2026, NULL, NULL, 'As listras azul-grená do Barça 2026/27 com detalhes dourados e tecido de secagem rápida.', 399.90, NULL, '../IMG/Produtos/10/1.jpg', 0),
    (11, @Temp, 'Camisa Al Nassr 2026/27 Home', 'Torcedor · Temporada 2026', 'Clube', 'Al Nassr', 2026, NULL, NULL, 'O amarelo do Al Nassr com detalhes em azul, gola careca e tecido leve de alta ventilação.', 349.90, NULL, '../IMG/Produtos/11/1.jpg', 0),
    (12, @Temp, 'Camisa Boca Juniors 2026 Home', 'Torcedor · Temporada 2026', 'Clube', 'Boca Juniors', 2026, NULL, NULL, 'O azul e ouro de La Bombonera com a faixa horizontal clássica, em versão 2026.', 329.90, NULL, '../IMG/Produtos/12/1.jpg', 0),
    (13, @Retro, 'Camisa Brasil 1994 Retrô', 'Coleção Retrô', 'Seleção', 'Brasil', 1994, NULL, NULL, 'Réplica retrô da amarelinha do tetracampeonato nos Estados Unidos, com gola verde e corte da época.', 299.90, NULL, '../IMG/Produtos/13/1.jpg', 1),
    (14, @Retro, 'Camisa Argentina 1986 Retrô', 'Coleção Retrô', 'Seleção', 'Argentina', 1986, NULL, NULL, 'Réplica retrô da alviceleste campeã no México em 1986, com listras verticais e escudo vintage.', 299.90, NULL, '../IMG/Produtos/14/1.jpg', 0),
    (15, @Retro, 'Camisa Manchester United 2007/08', 'Coleção Retrô', 'Clube', 'Manchester United', 2008, NULL, NULL, 'Réplica retrô do vermelho de Old Trafford na temporada 2007/08, a do título inglês e da Champions League conquistada em Moscou.', 329.90, NULL, '../IMG/Produtos/15/1.jpg', 0),
    (16, @Retro, 'Camisa Corinthians 2012 Retrô', 'Coleção Retrô', 'Clube', 'Corinthians', 2012, NULL, NULL, 'Réplica retrô do manto alvinegro de 2012, ano da Libertadores e do Mundial de Clubes.', 299.90, NULL, '../IMG/Produtos/16/1.jpg', 0),
    (17, @Retro, 'Camisa Barcelona 2005/06 Retrô', 'Coleção Retrô', 'Clube', 'Barcelona', 2006, NULL, NULL, 'Réplica retrô do Barça 2005/06, campeão espanhol e europeu, com as listras azul-grená da época.', 329.90, NULL, '../IMG/Produtos/17/1.jpg', 0),
    (18, @Retro, 'Camisa Real Madrid 2001/02 Retrô', 'Coleção Retrô', 'Clube', 'Real Madrid', 2002, NULL, NULL, 'Réplica retrô do branco do centenário merengue, a temporada da nona Champions League, conquistada em Glasgow.', 329.90, NULL, '../IMG/Produtos/18/1.jpg', 0),
    (19, @Retro, 'Camisa Milan 2006/07', 'Coleção Retrô', 'Clube', 'AC Milan', 2007, NULL, NULL, 'Réplica retrô do rossonero de listras vermelhas e pretas da temporada 2006/07, campeã europeia em Atenas.', 329.90, NULL, '../IMG/Produtos/19/1.jpg', 1),
    (20, @Retro, 'Camisa Inter de Milão 2009/10', 'Coleção Retrô', 'Clube', 'Inter de Milão', 2010, NULL, NULL, 'Réplica retrô do nerazzurro da tríplice coroa de 2009/10, com listras azuis e pretas.', 299.90, NULL, '../IMG/Produtos/20/1.jpg', 0),
    (21, @Retro, 'Camisa Boca Juniors 2000 Retrô', 'Coleção Retrô', 'Clube', 'Boca Juniors', 2000, NULL, NULL, 'Réplica retrô do Boca de 2000, campeão da Libertadores e do Intercontinental, com a faixa amarela no peito.', 299.90, NULL, '../IMG/Produtos/21/1.jpg', 0),
    (22, @Retro, 'Camisa Santos 2011 Retrô', 'Coleção Retrô', 'Clube', 'Santos', 2011, NULL, NULL, 'Réplica retrô do manto branco do Santos de 2011, tricampeão da Libertadores.', 329.90, NULL, '../IMG/Produtos/22/1.jpg', 1),
    (23, @Retro, 'Camisa Real Madrid 2017 Retrô', 'Coleção Retrô', 'Clube', 'Real Madrid', 2017, NULL, NULL, 'Réplica retrô do branco merengue da temporada 2016/17, campeã espanhola e bicampeã europeia seguida.', 329.90, NULL, '../IMG/Produtos/23/1.jpg', 1),
    (24, @Retro, 'Camisa Fiorentina 1998/99 Retrô', 'Coleção Retrô', 'Clube', 'Fiorentina', 1999, NULL, NULL, 'Réplica retrô do roxo da Fiorentina 1998/99, a Viola que brigou pelo título italiano.', 299.90, NULL, '../IMG/Produtos/24/1.jpg', 0),
    (25, @Chut, 'Umbro Pro 5 Bump', 'Futsal · Quadra', 'Futsal', NULL, NULL, 'Umbro', 'IC — quadra', 'Umbro Pro 5 Bump: Sola lisa de borracha que não marca o piso, com ponto de giro no antepé. Para quadra, salão e parquet. Numeração 37 a 44.', 499.90, NULL, '../IMG/Produtos/25/1.jpg', 1),
    (26, @Chut, 'Joma Top Flex Rebound', 'Futsal · Quadra', 'Futsal', NULL, NULL, 'Joma', 'Indoor — quadra', 'Joma Top Flex Rebound: Sola lisa de borracha que não marca o piso, com ponto de giro no antepé. Para quadra, salão e parquet. Numeração 37 a 44.', 449.90, NULL, '../IMG/Produtos/26/1.jpg', 0),
    (27, @Chut, 'Nike Lunar Gato', 'Futsal · Quadra', 'Futsal', NULL, NULL, 'Nike', 'IC — quadra', 'Nike Lunar Gato: Sola lisa de borracha que não marca o piso, com ponto de giro no antepé. Para quadra, salão e parquet. Numeração 37 a 44.', 399.90, NULL, '../IMG/Produtos/27/1.jpg', 0),
    (28, @Chut, 'Umbro Adamant ProBump', 'Futsal · Quadra', 'Futsal', NULL, NULL, 'Umbro', 'IC — quadra', 'Umbro Adamant ProBump: Sola lisa de borracha que não marca o piso, com ponto de giro no antepé. Para quadra, salão e parquet. Numeração 37 a 44.', 399.90, NULL, '../IMG/Produtos/28/1.jpg', 0),
    (29, @Chut, 'Nike Mercurial Vapor TF', 'Society · Grama sintética', 'Society', NULL, NULL, 'Nike', 'TF — society', 'Nike Mercurial Vapor TF: Solado com dezenas de travas baixas de borracha que espalham o peso. Para grama sintética (society e fut7). Numeração 37 a 44.', 599.90, NULL, '../IMG/Produtos/29/1.jpg', 1),
    (30, @Chut, 'Nike Tiempo Legend TF', 'Society · Grama sintética', 'Society', NULL, NULL, 'Nike', 'TF — society', 'Nike Tiempo Legend TF: Solado com dezenas de travas baixas de borracha que espalham o peso. Para grama sintética (society e fut7). Numeração 37 a 44.', 549.90, NULL, '../IMG/Produtos/30/1.jpg', 0),
    (31, @Chut, 'adidas Predator TF', 'Society · Grama sintética', 'Society', NULL, NULL, 'adidas', 'TF — society', 'adidas Predator TF: Solado com dezenas de travas baixas de borracha que espalham o peso. Para grama sintética (society e fut7). Numeração 37 a 44.', 499.90, NULL, '../IMG/Produtos/31/1.jpg', 0),
    (32, @Chut, 'adidas F50 TF', 'Society · Grama sintética', 'Society', NULL, NULL, 'adidas', 'TF — society', 'adidas F50 TF: Solado com dezenas de travas baixas de borracha que espalham o peso. Para grama sintética (society e fut7). Numeração 37 a 44.', 499.90, NULL, '../IMG/Produtos/32/1.jpg', 0),
    (33, @Chut, 'Nike Mercurial Vapor FG', 'Campo · Grama natural', 'Campo', NULL, NULL, 'Nike', 'FG — campo', 'Nike Mercurial Vapor FG: Travas altas para gramado natural firme, com tração na arrancada e na frenagem. Não use em grama sintética. Numeração 37 a 44.', 899.90, NULL, '../IMG/Produtos/33/1.jpg', 1),
    (34, @Chut, 'Nike Phantom FG', 'Campo · Grama natural', 'Campo', NULL, NULL, 'Nike', 'FG — campo', 'Nike Phantom FG: Travas altas para gramado natural firme, com tração na arrancada e na frenagem. Não use em grama sintética. Numeração 37 a 44.', 849.90, NULL, '../IMG/Produtos/34/1.jpg', 0),
    (35, @Chut, 'adidas Predator FG', 'Campo · Grama natural', 'Campo', NULL, NULL, 'adidas', 'FG — campo', 'adidas Predator FG: Travas altas para gramado natural firme, com tração na arrancada e na frenagem. Não use em grama sintética. Numeração 37 a 44.', 799.90, NULL, '../IMG/Produtos/35/1.jpg', 0),
    (36, @Chut, 'adidas F50 FG', 'Campo · Grama natural', 'Campo', NULL, NULL, 'adidas', 'FG — campo', 'adidas F50 FG: Travas altas para gramado natural firme, com tração na arrancada e na frenagem. Não use em grama sintética. Numeração 37 a 44.', 799.90, NULL, '../IMG/Produtos/36/1.jpg', 0);

DECLARE @Galeria TABLE (ProdutoId INT, Url VARCHAR(300), Ordem INT);
INSERT INTO @Galeria VALUES
    (1, '../IMG/Produtos/1/1.jpg', 1),
    (1, '../IMG/Produtos/1/2.jpg', 2),
    (1, '../IMG/Produtos/1/3.jpg', 3),
    (1, '../IMG/Produtos/1/4.jpg', 4),
    (1, '../IMG/Produtos/1/5.jpg', 5),
    (1, '../IMG/Produtos/1/6.jpg', 6),
    (1, '../IMG/Produtos/1/7.jpg', 7),
    (1, '../IMG/Produtos/1/8.jpg', 8),
    (1, '../IMG/Produtos/1/9.jpg', 9),
    (1, '../IMG/Produtos/1/10.jpg', 10),
    (2, '../IMG/Produtos/2/1.jpg', 1),
    (2, '../IMG/Produtos/2/2.jpg', 2),
    (2, '../IMG/Produtos/2/3.jpg', 3),
    (2, '../IMG/Produtos/2/4.jpg', 4),
    (2, '../IMG/Produtos/2/5.jpg', 5),
    (2, '../IMG/Produtos/2/6.jpg', 6),
    (2, '../IMG/Produtos/2/7.jpg', 7),
    (2, '../IMG/Produtos/2/8.jpg', 8),
    (2, '../IMG/Produtos/2/9.jpg', 9),
    (2, '../IMG/Produtos/2/10.jpg', 10),
    (3, '../IMG/Produtos/3/1.jpg', 1),
    (3, '../IMG/Produtos/3/2.jpg', 2),
    (3, '../IMG/Produtos/3/3.jpg', 3),
    (3, '../IMG/Produtos/3/4.jpg', 4),
    (3, '../IMG/Produtos/3/5.jpg', 5),
    (3, '../IMG/Produtos/3/6.jpg', 6),
    (3, '../IMG/Produtos/3/7.jpg', 7),
    (3, '../IMG/Produtos/3/8.jpg', 8),
    (3, '../IMG/Produtos/3/9.jpg', 9),
    (3, '../IMG/Produtos/3/10.jpg', 10),
    (4, '../IMG/Produtos/4/1.jpg', 1),
    (4, '../IMG/Produtos/4/2.jpg', 2),
    (4, '../IMG/Produtos/4/3.jpg', 3),
    (4, '../IMG/Produtos/4/4.jpg', 4),
    (4, '../IMG/Produtos/4/5.jpg', 5),
    (4, '../IMG/Produtos/4/6.jpg', 6),
    (4, '../IMG/Produtos/4/7.jpg', 7),
    (4, '../IMG/Produtos/4/8.jpg', 8),
    (4, '../IMG/Produtos/4/9.jpg', 9),
    (4, '../IMG/Produtos/4/10.jpg', 10),
    (4, '../IMG/Produtos/4/11.jpg', 11),
    (4, '../IMG/Produtos/4/12.jpg', 12),
    (5, '../IMG/Produtos/5/1.jpg', 1),
    (5, '../IMG/Produtos/5/2.jpg', 2),
    (5, '../IMG/Produtos/5/3.jpg', 3),
    (5, '../IMG/Produtos/5/4.jpg', 4),
    (5, '../IMG/Produtos/5/5.jpg', 5),
    (5, '../IMG/Produtos/5/6.jpg', 6),
    (5, '../IMG/Produtos/5/7.jpg', 7),
    (5, '../IMG/Produtos/5/8.jpg', 8),
    (5, '../IMG/Produtos/5/9.jpg', 9),
    (5, '../IMG/Produtos/5/10.jpg', 10),
    (5, '../IMG/Produtos/5/11.jpg', 11),
    (5, '../IMG/Produtos/5/12.jpg', 12),
    (5, '../IMG/Produtos/5/13.jpg', 13),
    (5, '../IMG/Produtos/5/14.jpg', 14),
    (6, '../IMG/Produtos/6/1.jpg', 1),
    (6, '../IMG/Produtos/6/2.jpg', 2),
    (6, '../IMG/Produtos/6/3.jpg', 3),
    (6, '../IMG/Produtos/6/4.jpg', 4),
    (6, '../IMG/Produtos/6/5.jpg', 5),
    (6, '../IMG/Produtos/6/6.jpg', 6),
    (6, '../IMG/Produtos/6/7.jpg', 7),
    (6, '../IMG/Produtos/6/8.jpg', 8),
    (6, '../IMG/Produtos/6/9.jpg', 9),
    (7, '../IMG/Produtos/7/1.jpg', 1),
    (7, '../IMG/Produtos/7/2.jpg', 2),
    (7, '../IMG/Produtos/7/3.jpg', 3),
    (7, '../IMG/Produtos/7/4.jpg', 4),
    (7, '../IMG/Produtos/7/5.jpg', 5),
    (7, '../IMG/Produtos/7/6.jpg', 6),
    (7, '../IMG/Produtos/7/7.jpg', 7),
    (7, '../IMG/Produtos/7/8.jpg', 8),
    (7, '../IMG/Produtos/7/9.jpg', 9),
    (7, '../IMG/Produtos/7/10.jpg', 10),
    (8, '../IMG/Produtos/8/1.jpg', 1),
    (8, '../IMG/Produtos/8/2.jpg', 2),
    (8, '../IMG/Produtos/8/3.jpg', 3),
    (8, '../IMG/Produtos/8/4.jpg', 4),
    (8, '../IMG/Produtos/8/5.jpg', 5),
    (8, '../IMG/Produtos/8/6.jpg', 6),
    (8, '../IMG/Produtos/8/7.jpg', 7),
    (8, '../IMG/Produtos/8/8.jpg', 8),
    (8, '../IMG/Produtos/8/9.jpg', 9),
    (8, '../IMG/Produtos/8/10.jpg', 10),
    (9, '../IMG/Produtos/9/1.jpg', 1),
    (9, '../IMG/Produtos/9/2.jpg', 2),
    (9, '../IMG/Produtos/9/3.jpg', 3),
    (9, '../IMG/Produtos/9/4.jpg', 4),
    (9, '../IMG/Produtos/9/5.jpg', 5),
    (9, '../IMG/Produtos/9/6.jpg', 6),
    (9, '../IMG/Produtos/9/7.jpg', 7),
    (9, '../IMG/Produtos/9/8.jpg', 8),
    (9, '../IMG/Produtos/9/9.jpg', 9),
    (9, '../IMG/Produtos/9/10.jpg', 10),
    (10, '../IMG/Produtos/10/1.jpg', 1),
    (10, '../IMG/Produtos/10/2.jpg', 2),
    (10, '../IMG/Produtos/10/3.jpg', 3),
    (10, '../IMG/Produtos/10/4.jpg', 4),
    (10, '../IMG/Produtos/10/5.jpg', 5),
    (10, '../IMG/Produtos/10/6.jpg', 6),
    (10, '../IMG/Produtos/10/7.jpg', 7),
    (10, '../IMG/Produtos/10/8.jpg', 8),
    (10, '../IMG/Produtos/10/9.jpg', 9),
    (10, '../IMG/Produtos/10/10.jpg', 10),
    (10, '../IMG/Produtos/10/11.jpg', 11),
    (10, '../IMG/Produtos/10/12.jpg', 12),
    (11, '../IMG/Produtos/11/1.jpg', 1),
    (11, '../IMG/Produtos/11/2.jpg', 2),
    (11, '../IMG/Produtos/11/3.jpg', 3),
    (11, '../IMG/Produtos/11/4.jpg', 4),
    (11, '../IMG/Produtos/11/5.jpg', 5),
    (11, '../IMG/Produtos/11/6.jpg', 6),
    (12, '../IMG/Produtos/12/1.jpg', 1),
    (12, '../IMG/Produtos/12/2.jpg', 2),
    (12, '../IMG/Produtos/12/3.jpg', 3),
    (12, '../IMG/Produtos/12/4.jpg', 4),
    (12, '../IMG/Produtos/12/5.jpg', 5),
    (12, '../IMG/Produtos/12/6.jpg', 6),
    (12, '../IMG/Produtos/12/7.jpg', 7),
    (12, '../IMG/Produtos/12/8.jpg', 8),
    (12, '../IMG/Produtos/12/9.jpg', 9),
    (12, '../IMG/Produtos/12/10.jpg', 10),
    (12, '../IMG/Produtos/12/11.jpg', 11),
    (12, '../IMG/Produtos/12/12.jpg', 12),
    (13, '../IMG/Produtos/13/1.jpg', 1),
    (13, '../IMG/Produtos/13/2.jpg', 2),
    (13, '../IMG/Produtos/13/3.jpg', 3),
    (13, '../IMG/Produtos/13/4.jpg', 4),
    (13, '../IMG/Produtos/13/5.jpg', 5),
    (13, '../IMG/Produtos/13/6.jpg', 6),
    (13, '../IMG/Produtos/13/7.jpg', 7),
    (13, '../IMG/Produtos/13/8.jpg', 8),
    (14, '../IMG/Produtos/14/1.jpg', 1),
    (14, '../IMG/Produtos/14/2.jpg', 2),
    (14, '../IMG/Produtos/14/3.jpg', 3),
    (14, '../IMG/Produtos/14/4.jpg', 4),
    (14, '../IMG/Produtos/14/5.jpg', 5),
    (14, '../IMG/Produtos/14/6.jpg', 6),
    (14, '../IMG/Produtos/14/7.jpg', 7),
    (14, '../IMG/Produtos/14/8.jpg', 8),
    (14, '../IMG/Produtos/14/9.jpg', 9),
    (15, '../IMG/Produtos/15/1.jpg', 1),
    (15, '../IMG/Produtos/15/2.jpg', 2),
    (15, '../IMG/Produtos/15/3.jpg', 3),
    (15, '../IMG/Produtos/15/4.jpg', 4),
    (15, '../IMG/Produtos/15/5.jpg', 5),
    (15, '../IMG/Produtos/15/6.jpg', 6),
    (15, '../IMG/Produtos/15/7.jpg', 7),
    (15, '../IMG/Produtos/15/8.jpg', 8),
    (15, '../IMG/Produtos/15/9.jpg', 9),
    (16, '../IMG/Produtos/16/1.jpg', 1),
    (16, '../IMG/Produtos/16/2.jpg', 2),
    (16, '../IMG/Produtos/16/3.jpg', 3),
    (16, '../IMG/Produtos/16/4.jpg', 4),
    (16, '../IMG/Produtos/16/5.jpg', 5),
    (16, '../IMG/Produtos/16/6.jpg', 6),
    (16, '../IMG/Produtos/16/7.jpg', 7),
    (16, '../IMG/Produtos/16/8.jpg', 8),
    (16, '../IMG/Produtos/16/9.jpg', 9),
    (16, '../IMG/Produtos/16/10.jpg', 10),
    (16, '../IMG/Produtos/16/11.jpg', 11),
    (16, '../IMG/Produtos/16/12.jpg', 12),
    (16, '../IMG/Produtos/16/13.jpg', 13),
    (16, '../IMG/Produtos/16/14.jpg', 14),
    (17, '../IMG/Produtos/17/1.jpg', 1),
    (17, '../IMG/Produtos/17/2.jpg', 2),
    (17, '../IMG/Produtos/17/3.jpg', 3),
    (17, '../IMG/Produtos/17/4.jpg', 4),
    (17, '../IMG/Produtos/17/5.jpg', 5),
    (17, '../IMG/Produtos/17/6.jpg', 6),
    (17, '../IMG/Produtos/17/7.jpg', 7),
    (18, '../IMG/Produtos/18/1.jpg', 1),
    (18, '../IMG/Produtos/18/2.jpg', 2),
    (18, '../IMG/Produtos/18/3.jpg', 3),
    (18, '../IMG/Produtos/18/4.jpg', 4),
    (18, '../IMG/Produtos/18/5.jpg', 5),
    (18, '../IMG/Produtos/18/6.jpg', 6),
    (18, '../IMG/Produtos/18/7.jpg', 7),
    (18, '../IMG/Produtos/18/8.jpg', 8),
    (18, '../IMG/Produtos/18/9.jpg', 9),
    (18, '../IMG/Produtos/18/10.jpg', 10),
    (19, '../IMG/Produtos/19/1.jpg', 1),
    (19, '../IMG/Produtos/19/2.jpg', 2),
    (19, '../IMG/Produtos/19/3.jpg', 3),
    (19, '../IMG/Produtos/19/4.jpg', 4),
    (19, '../IMG/Produtos/19/5.jpg', 5),
    (19, '../IMG/Produtos/19/6.jpg', 6),
    (19, '../IMG/Produtos/19/7.jpg', 7),
    (19, '../IMG/Produtos/19/8.jpg', 8),
    (19, '../IMG/Produtos/19/9.jpg', 9),
    (20, '../IMG/Produtos/20/1.jpg', 1),
    (20, '../IMG/Produtos/20/2.jpg', 2),
    (20, '../IMG/Produtos/20/3.jpg', 3),
    (20, '../IMG/Produtos/20/4.jpg', 4),
    (20, '../IMG/Produtos/20/5.jpg', 5),
    (20, '../IMG/Produtos/20/6.jpg', 6),
    (20, '../IMG/Produtos/20/7.jpg', 7),
    (20, '../IMG/Produtos/20/8.jpg', 8),
    (20, '../IMG/Produtos/20/9.jpg', 9),
    (20, '../IMG/Produtos/20/10.jpg', 10),
    (20, '../IMG/Produtos/20/11.jpg', 11),
    (21, '../IMG/Produtos/21/1.jpg', 1),
    (21, '../IMG/Produtos/21/2.jpg', 2),
    (21, '../IMG/Produtos/21/3.jpg', 3),
    (21, '../IMG/Produtos/21/4.jpg', 4),
    (21, '../IMG/Produtos/21/5.jpg', 5),
    (21, '../IMG/Produtos/21/6.jpg', 6),
    (21, '../IMG/Produtos/21/7.jpg', 7),
    (21, '../IMG/Produtos/21/8.jpg', 8),
    (21, '../IMG/Produtos/21/9.jpg', 9),
    (22, '../IMG/Produtos/22/1.jpg', 1),
    (22, '../IMG/Produtos/22/2.jpg', 2),
    (22, '../IMG/Produtos/22/3.jpg', 3),
    (22, '../IMG/Produtos/22/4.jpg', 4),
    (22, '../IMG/Produtos/22/5.jpg', 5),
    (22, '../IMG/Produtos/22/6.jpg', 6),
    (22, '../IMG/Produtos/22/7.jpg', 7),
    (22, '../IMG/Produtos/22/8.jpg', 8),
    (22, '../IMG/Produtos/22/9.jpg', 9),
    (23, '../IMG/Produtos/23/1.jpg', 1),
    (23, '../IMG/Produtos/23/2.jpg', 2),
    (23, '../IMG/Produtos/23/3.jpg', 3),
    (23, '../IMG/Produtos/23/4.jpg', 4),
    (23, '../IMG/Produtos/23/5.jpg', 5),
    (23, '../IMG/Produtos/23/6.jpg', 6),
    (23, '../IMG/Produtos/23/7.jpg', 7),
    (23, '../IMG/Produtos/23/8.jpg', 8),
    (24, '../IMG/Produtos/24/1.jpg', 1),
    (24, '../IMG/Produtos/24/2.jpg', 2),
    (24, '../IMG/Produtos/24/3.jpg', 3),
    (24, '../IMG/Produtos/24/4.jpg', 4),
    (24, '../IMG/Produtos/24/5.jpg', 5),
    (24, '../IMG/Produtos/24/6.jpg', 6),
    (24, '../IMG/Produtos/24/7.jpg', 7),
    (24, '../IMG/Produtos/24/8.jpg', 8),
    (24, '../IMG/Produtos/24/9.jpg', 9),
    (24, '../IMG/Produtos/24/10.jpg', 10),
    (24, '../IMG/Produtos/24/11.jpg', 11),
    (24, '../IMG/Produtos/24/12.jpg', 12),
    (24, '../IMG/Produtos/24/13.jpg', 13),
    (24, '../IMG/Produtos/24/14.jpg', 14),
    (24, '../IMG/Produtos/24/15.jpg', 15),
    (24, '../IMG/Produtos/24/16.jpg', 16),
    (24, '../IMG/Produtos/24/17.jpg', 17),
    (24, '../IMG/Produtos/24/18.jpg', 18),
    (24, '../IMG/Produtos/24/19.jpg', 19),
    (25, '../IMG/Produtos/25/1.jpg', 1),
    (25, '../IMG/Produtos/25/2.jpg', 2),
    (25, '../IMG/Produtos/25/3.jpg', 3),
    (25, '../IMG/Produtos/25/4.jpg', 4),
    (25, '../IMG/Produtos/25/5.jpg', 5),
    (25, '../IMG/Produtos/25/6.jpg', 6),
    (25, '../IMG/Produtos/25/7.jpg', 7),
    (25, '../IMG/Produtos/25/8.jpg', 8),
    (25, '../IMG/Produtos/25/9.jpg', 9),
    (26, '../IMG/Produtos/26/1.jpg', 1),
    (26, '../IMG/Produtos/26/2.jpg', 2),
    (26, '../IMG/Produtos/26/3.jpg', 3),
    (26, '../IMG/Produtos/26/4.jpg', 4),
    (26, '../IMG/Produtos/26/5.jpg', 5),
    (26, '../IMG/Produtos/26/6.jpg', 6),
    (26, '../IMG/Produtos/26/7.jpg', 7),
    (26, '../IMG/Produtos/26/8.jpg', 8),
    (27, '../IMG/Produtos/27/1.jpg', 1),
    (27, '../IMG/Produtos/27/2.jpg', 2),
    (27, '../IMG/Produtos/27/3.jpg', 3),
    (27, '../IMG/Produtos/27/4.jpg', 4),
    (27, '../IMG/Produtos/27/5.jpg', 5),
    (27, '../IMG/Produtos/27/6.jpg', 6),
    (27, '../IMG/Produtos/27/7.jpg', 7),
    (27, '../IMG/Produtos/27/8.jpg', 8),
    (28, '../IMG/Produtos/28/1.jpg', 1),
    (28, '../IMG/Produtos/28/2.jpg', 2),
    (28, '../IMG/Produtos/28/3.jpg', 3),
    (28, '../IMG/Produtos/28/4.jpg', 4),
    (28, '../IMG/Produtos/28/5.jpg', 5),
    (28, '../IMG/Produtos/28/6.jpg', 6),
    (28, '../IMG/Produtos/28/7.jpg', 7),
    (28, '../IMG/Produtos/28/8.jpg', 8),
    (28, '../IMG/Produtos/28/9.jpg', 9),
    (29, '../IMG/Produtos/29/1.jpg', 1),
    (29, '../IMG/Produtos/29/2.jpg', 2),
    (29, '../IMG/Produtos/29/3.jpg', 3),
    (29, '../IMG/Produtos/29/4.jpg', 4),
    (29, '../IMG/Produtos/29/5.jpg', 5),
    (29, '../IMG/Produtos/29/6.jpg', 6),
    (29, '../IMG/Produtos/29/7.jpg', 7),
    (29, '../IMG/Produtos/29/8.jpg', 8),
    (29, '../IMG/Produtos/29/9.jpg', 9),
    (29, '../IMG/Produtos/29/10.jpg', 10),
    (29, '../IMG/Produtos/29/11.jpg', 11),
    (29, '../IMG/Produtos/29/12.jpg', 12),
    (29, '../IMG/Produtos/29/13.jpg', 13),
    (29, '../IMG/Produtos/29/14.jpg', 14),
    (30, '../IMG/Produtos/30/1.jpg', 1),
    (30, '../IMG/Produtos/30/2.jpg', 2),
    (30, '../IMG/Produtos/30/3.jpg', 3),
    (30, '../IMG/Produtos/30/4.jpg', 4),
    (30, '../IMG/Produtos/30/5.jpg', 5),
    (30, '../IMG/Produtos/30/6.jpg', 6),
    (30, '../IMG/Produtos/30/7.jpg', 7),
    (31, '../IMG/Produtos/31/1.jpg', 1),
    (31, '../IMG/Produtos/31/2.jpg', 2),
    (31, '../IMG/Produtos/31/3.jpg', 3),
    (31, '../IMG/Produtos/31/4.jpg', 4),
    (31, '../IMG/Produtos/31/5.jpg', 5),
    (31, '../IMG/Produtos/31/6.jpg', 6),
    (31, '../IMG/Produtos/31/7.jpg', 7),
    (32, '../IMG/Produtos/32/1.jpg', 1),
    (32, '../IMG/Produtos/32/2.jpg', 2),
    (32, '../IMG/Produtos/32/3.jpg', 3),
    (32, '../IMG/Produtos/32/4.jpg', 4),
    (32, '../IMG/Produtos/32/5.jpg', 5),
    (32, '../IMG/Produtos/32/6.jpg', 6),
    (32, '../IMG/Produtos/32/7.jpg', 7),
    (32, '../IMG/Produtos/32/8.jpg', 8),
    (32, '../IMG/Produtos/32/9.jpg', 9),
    (32, '../IMG/Produtos/32/10.jpg', 10),
    (32, '../IMG/Produtos/32/11.jpg', 11),
    (32, '../IMG/Produtos/32/12.jpg', 12),
    (32, '../IMG/Produtos/32/13.jpg', 13),
    (32, '../IMG/Produtos/32/14.jpg', 14),
    (33, '../IMG/Produtos/33/1.jpg', 1),
    (33, '../IMG/Produtos/33/2.jpg', 2),
    (33, '../IMG/Produtos/33/3.jpg', 3),
    (33, '../IMG/Produtos/33/4.jpg', 4),
    (33, '../IMG/Produtos/33/5.jpg', 5),
    (33, '../IMG/Produtos/33/6.jpg', 6),
    (33, '../IMG/Produtos/33/7.jpg', 7),
    (34, '../IMG/Produtos/34/1.jpg', 1),
    (34, '../IMG/Produtos/34/2.jpg', 2),
    (34, '../IMG/Produtos/34/3.jpg', 3),
    (34, '../IMG/Produtos/34/4.jpg', 4),
    (34, '../IMG/Produtos/34/5.jpg', 5),
    (34, '../IMG/Produtos/34/6.jpg', 6),
    (34, '../IMG/Produtos/34/7.jpg', 7),
    (35, '../IMG/Produtos/35/1.jpg', 1),
    (35, '../IMG/Produtos/35/2.jpg', 2),
    (35, '../IMG/Produtos/35/3.jpg', 3),
    (35, '../IMG/Produtos/35/4.jpg', 4),
    (35, '../IMG/Produtos/35/5.jpg', 5),
    (35, '../IMG/Produtos/35/6.jpg', 6),
    (35, '../IMG/Produtos/35/7.jpg', 7),
    (35, '../IMG/Produtos/35/8.jpg', 8),
    (35, '../IMG/Produtos/35/9.jpg', 9),
    (35, '../IMG/Produtos/35/10.jpg', 10),
    (35, '../IMG/Produtos/35/11.jpg', 11),
    (35, '../IMG/Produtos/35/12.jpg', 12),
    (35, '../IMG/Produtos/35/13.jpg', 13),
    (35, '../IMG/Produtos/35/14.jpg', 14),
    (36, '../IMG/Produtos/36/1.jpg', 1),
    (36, '../IMG/Produtos/36/2.jpg', 2),
    (36, '../IMG/Produtos/36/3.jpg', 3),
    (36, '../IMG/Produtos/36/4.jpg', 4),
    (36, '../IMG/Produtos/36/5.jpg', 5),
    (36, '../IMG/Produtos/36/6.jpg', 6),
    (36, '../IMG/Produtos/36/7.jpg', 7);

BEGIN TRANSACTION;
    -- (a) insere os produtos que ainda não existem, mantendo os IDs da planilha
    SET IDENTITY_INSERT dbo.Produtos ON;
    INSERT INTO dbo.Produtos (Id, CategoriaId, Nome, Modelo, Linha, Equipe, Ano, Marca, Solado, Descricao,
                              Preco, PrecoPromocional, Imagem, Destaque)
    SELECT C.Id, C.CategoriaId, C.Nome, C.Modelo, C.Linha, C.Equipe, C.Ano, C.Marca, C.Solado, C.Descricao,
           C.Preco, C.PrecoPromocional, C.Imagem, C.Destaque
    FROM @Catalogo C
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Produtos P WHERE P.Id = C.Id);
    SET IDENTITY_INSERT dbo.Produtos OFF;

    -- (b) catálogo novo: atualiza os produtos existentes, refaz a galeria e
    --     remove tamanhos que não pertencem mais ao tipo do produto (camisa x chuteira)
    IF ISNULL(@VersaoAtual, N'') <> @VersaoCatalogo
    BEGIN
        UPDATE P SET
            CategoriaId = C.CategoriaId, Nome = C.Nome, Modelo = C.Modelo, Linha = C.Linha, Equipe = C.Equipe,
            Ano = C.Ano, Marca = C.Marca, Solado = C.Solado, Descricao = C.Descricao, Preco = C.Preco,
            PrecoPromocional = C.PrecoPromocional, Imagem = C.Imagem, Destaque = C.Destaque, Ativo = 1,
            AtualizadoEm = SYSDATETIME()
        FROM dbo.Produtos P INNER JOIN @Catalogo C ON C.Id = P.Id;

        DELETE FROM dbo.ProdutoImagens WHERE ProdutoId IN (SELECT Id FROM @Catalogo);
        INSERT INTO dbo.ProdutoImagens (ProdutoId, Url, Ordem) SELECT ProdutoId, Url, Ordem FROM @Galeria;

        DELETE E FROM dbo.Estoque E
        INNER JOIN @Catalogo C ON C.Id = E.ProdutoId
        WHERE (C.CategoriaId = @Chut AND E.Tamanho NOT IN ('37','38','39','40','41','42','43','44'))
           OR (C.CategoriaId <> @Chut AND E.Tamanho NOT IN ('P','M','G','GG','XG'));

        IF @VersaoAtual IS NULL
            EXEC sys.sp_addextendedproperty @name = N'CatalogoVersao', @value = @VersaoCatalogo,
                 @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'Produtos';
        ELSE
            EXEC sys.sp_updateextendedproperty @name = N'CatalogoVersao', @value = @VersaoCatalogo,
                 @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'Produtos';
    END
COMMIT TRANSACTION;
GO
-- </catalogo>

-- ----------------------------------------------------------------------------
-- 3. ESTOQUE POR TAMANHO — cria só as combinações produto/tamanho que faltam
--    Camisas: P, M, G, GG, XG · Chuteiras: 37 a 44
--    Quantidades variadas (inclui alguns tamanhos esgotados para demonstração)
-- ----------------------------------------------------------------------------
EXEC sys.sp_set_session_context @key = N'origem', @value = N'Carga inicial (seed)';

INSERT INTO dbo.Estoque (ProdutoId, Tamanho, Quantidade)
SELECT P.Id, T.Tamanho,
       CASE WHEN (P.Id + T.Ordem) % 9 = 0 THEN 0                 -- esgotado
            WHEN (P.Id + T.Ordem) % 7 = 0 THEN 3                 -- estoque baixo
            ELSE 8 + ((P.Id * 7 + T.Ordem * 5) % 22) END
FROM dbo.Produtos P
INNER JOIN dbo.Categorias C ON C.Id = P.CategoriaId
CROSS APPLY (
    SELECT Tamanho, Ordem FROM (VALUES ('P',1),('M',2),('G',3),('GG',4),('XG',5)) Cam(Tamanho, Ordem)
    WHERE C.Slug <> 'chuteiras'
    UNION ALL
    SELECT Tamanho, Ordem FROM (VALUES ('37',1),('38',2),('39',3),('40',4),('41',5),('42',6),('43',7),('44',8)) Chu(Tamanho, Ordem)
    WHERE C.Slug = 'chuteiras'
) T
WHERE P.Ativo = 1
  AND NOT EXISTS (SELECT 1 FROM dbo.Estoque E WHERE E.ProdutoId = P.Id AND E.Tamanho = T.Tamanho);

EXEC sys.sp_set_session_context @key = N'origem', @value = NULL;
GO

-- ----------------------------------------------------------------------------
-- 4. CUPONS (insere os que faltam, pelo código)
-- ----------------------------------------------------------------------------
INSERT INTO dbo.Cupons (Codigo, PercentualDesconto, ValorMinimo, ValidoAte)
SELECT N.Codigo, N.Percentual, N.Minimo, N.Validade
FROM (VALUES
    ('BEMVINDO10', 10.00,   0.00, CAST(NULL AS DATE)),   -- primeira compra
    ('RETRO15',    15.00, 500.00, CAST('2026-12-31' AS DATE)),  -- pedidos acima de R$ 500
    ('HEXA2026',    5.00,   0.00, CAST('2026-12-31' AS DATE))
) N(Codigo, Percentual, Minimo, Validade)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Cupons C WHERE C.Codigo = N.Codigo);
GO
