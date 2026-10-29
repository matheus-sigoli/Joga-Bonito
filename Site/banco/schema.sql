-- ============================================================================
-- JOGA BONITO — SCRIPT COMPLETO DO BANCO DE DADOS (SQL SERVER 2019+)
-- PIM IV · UNIP 2026/2 · Disciplina: Programação de Banco de Dados
-- ----------------------------------------------------------------------------
-- Conteúdo:  13 tabelas · 12 índices · 2 funções · 3 views
--            10 stored procedures · 3 triggers
-- Versão 5: segurança dos dados pessoais — endereço e telefone cifrados pela API
--            (colunas ampliadas), mascaramento dinâmico de e-mail e IP e expurgo
--            do log de acessos após 180 dias (sp_ExpurgarRegistrosAntigos).
-- Versão 4: moderação de avaliações (Status, ModeradoPor...), contribuição
--            Joga Junto por pedido (fn_CalcularJogaJunto) e anonimização LGPD
--            (sp_AnonimizarUsuario).
-- Versão 3: VersaoToken em Usuarios (revogação de sessões ao trocar a senha
--            ou ao "sair de todos os aparelhos").
-- Versão 2 (PRD-002): Marca/Solado em Produtos, bloqueio de login em Usuarios,
--            tabela LogAcessos e sp_RegistrarTentativaLogin. Bancos criados
--            pela versão 1 são migrados pelo bloco "MIGRAÇÕES" (ALTER TABLE).
-- Uso:       executado automaticamente pela API na inicialização (lotes
--            separados por GO) ou manualmente no SSMS/Azure Data Studio.
-- Idempotente: pode ser executado várias vezes sem perder dados.
-- ============================================================================

-- Índices filtrados exigem estas opções; o sqlcmd vem com QUOTED_IDENTIFIER OFF
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- PARTE 1 — TABELAS (MODELO FÍSICO)
-- ============================================================================

-- 1. USUARIOS — clientes e administradores (senha sempre em hash BCrypt)
IF OBJECT_ID('dbo.Usuarios', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Usuarios (
        Id            INT IDENTITY(1,1) CONSTRAINT PK_Usuarios PRIMARY KEY,
        Nome          VARCHAR(100) NOT NULL,
        Email         VARCHAR(120) NOT NULL CONSTRAINT UQ_Usuarios_Email UNIQUE,
        SenhaHash     VARCHAR(100) NOT NULL,
        Telefone      VARCHAR(100) NULL,           -- cifrado pela API (AES-256-GCM)
        Role          VARCHAR(20)  NOT NULL CONSTRAINT DF_Usuarios_Role DEFAULT 'Cliente',
        Ativo         BIT          NOT NULL CONSTRAINT DF_Usuarios_Ativo DEFAULT 1,
        AceiteLgpdEm  DATETIME2    NULL,            -- consentimento LGPD (Lei 13.709/2018)
        TentativasFalhas INT       NOT NULL CONSTRAINT DF_Usuarios_Tentativas DEFAULT 0,
        BloqueadoAte  DATETIME2    NULL,            -- bloqueio após 5 senhas erradas
        VersaoToken   INT          NOT NULL CONSTRAINT DF_Usuarios_VersaoToken DEFAULT 1, -- muda = tokens antigos param de valer
        CriadoEm      DATETIME2    NOT NULL CONSTRAINT DF_Usuarios_CriadoEm DEFAULT SYSDATETIME(),
        CONSTRAINT CK_Usuarios_Role CHECK (Role IN ('Cliente', 'Admin'))
    );
END
GO

-- 2. CATEGORIAS — macrocategorias do catálogo
IF OBJECT_ID('dbo.Categorias', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Categorias (
        Id         INT IDENTITY(1,1) CONSTRAINT PK_Categorias PRIMARY KEY,
        Nome       VARCHAR(50)  NOT NULL CONSTRAINT UQ_Categorias_Nome UNIQUE,
        Slug       VARCHAR(50)  NOT NULL CONSTRAINT UQ_Categorias_Slug UNIQUE,
        Descricao  VARCHAR(255) NULL,
        Ativo      BIT          NOT NULL CONSTRAINT DF_Categorias_Ativo DEFAULT 1
    );
END
GO

-- 3. PRODUTOS — camisas e chuteiras
--    Linha: Clube / Seleção (camisas) · Campo / Society / Futsal (chuteiras)
IF OBJECT_ID('dbo.Produtos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Produtos (
        Id                INT IDENTITY(1,1) CONSTRAINT PK_Produtos PRIMARY KEY,
        CategoriaId       INT            NOT NULL,
        Nome              VARCHAR(100)   NOT NULL,
        Modelo            VARCHAR(100)   NOT NULL,
        Linha             VARCHAR(20)    NOT NULL,
        Equipe            VARCHAR(60)    NULL,      -- clube/seleção (camisas)
        Ano               SMALLINT       NULL,      -- temporada ou ano histórico
        Marca             VARCHAR(40)    NULL,      -- chuteiras: Nike, adidas...
        Solado            VARCHAR(40)    NULL,      -- chuteiras: FG — campo, TF — society, IC — quadra
        Descricao         VARCHAR(1000)  NOT NULL,
        Preco             DECIMAL(10,2)  NOT NULL,
        PrecoPromocional  DECIMAL(10,2)  NULL,
        Imagem            VARCHAR(200)   NOT NULL,  -- imagem de capa
        Destaque          BIT            NOT NULL CONSTRAINT DF_Produtos_Destaque DEFAULT 0,
        Ativo             BIT            NOT NULL CONSTRAINT DF_Produtos_Ativo DEFAULT 1,
        CriadoEm          DATETIME2      NOT NULL CONSTRAINT DF_Produtos_CriadoEm DEFAULT SYSDATETIME(),
        AtualizadoEm      DATETIME2      NULL,
        CONSTRAINT FK_Produtos_Categorias FOREIGN KEY (CategoriaId) REFERENCES dbo.Categorias(Id),
        CONSTRAINT CK_Produtos_Preco CHECK (Preco > 0),
        CONSTRAINT CK_Produtos_Promo CHECK (PrecoPromocional IS NULL OR (PrecoPromocional > 0 AND PrecoPromocional < Preco)),
        CONSTRAINT CK_Produtos_Linha CHECK (Linha IN ('Clube', 'Seleção', 'Campo', 'Society', 'Futsal'))
    );
END
GO

-- 4. PRODUTO_IMAGENS — galeria de fotos (1:N com Produtos)
IF OBJECT_ID('dbo.ProdutoImagens', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProdutoImagens (
        Id         INT IDENTITY(1,1) CONSTRAINT PK_ProdutoImagens PRIMARY KEY,
        ProdutoId  INT          NOT NULL,
        Url        VARCHAR(200) NOT NULL,
        Ordem      TINYINT      NOT NULL CONSTRAINT DF_ProdutoImagens_Ordem DEFAULT 1,
        CONSTRAINT FK_ProdutoImagens_Produtos FOREIGN KEY (ProdutoId) REFERENCES dbo.Produtos(Id) ON DELETE CASCADE
    );
END
GO

-- 5. ESTOQUE — saldo por PRODUTO + TAMANHO (camisas P..XG, chuteiras 37..44)
IF OBJECT_ID('dbo.Estoque', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Estoque (
        Id                 INT IDENTITY(1,1) CONSTRAINT PK_Estoque PRIMARY KEY,
        ProdutoId          INT        NOT NULL,
        Tamanho            VARCHAR(5) NOT NULL,
        Quantidade         INT        NOT NULL CONSTRAINT DF_Estoque_Qtd DEFAULT 0,
        UltimaAtualizacao  DATETIME2  NOT NULL CONSTRAINT DF_Estoque_Atualizacao DEFAULT SYSDATETIME(),
        CONSTRAINT FK_Estoque_Produtos FOREIGN KEY (ProdutoId) REFERENCES dbo.Produtos(Id) ON DELETE CASCADE,
        CONSTRAINT UQ_Estoque_ProdutoTamanho UNIQUE (ProdutoId, Tamanho),
        CONSTRAINT CK_Estoque_NaoNegativo CHECK (Quantidade >= 0)   -- última barreira contra venda sem estoque
    );
END
GO

-- 6. ENDERECOS — locais de entrega (1:N com Usuarios)
IF OBJECT_ID('dbo.Enderecos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Enderecos (
        Id           INT IDENTITY(1,1) CONSTRAINT PK_Enderecos PRIMARY KEY,
        UsuarioId    INT          NOT NULL,
        -- CEP, rua, número, complemento e bairro são gravados CIFRADOS pela API (AES-256-GCM,
        -- prefixo "enc1:"): quem lê a tabela sem a chave não vê o endereço do cliente.
        Cep          VARCHAR(100) NOT NULL,
        Rua          VARCHAR(500) NOT NULL,
        Numero       VARCHAR(100) NOT NULL,
        Complemento  VARCHAR(200) NULL,
        Bairro       VARCHAR(400) NOT NULL,
        Cidade       VARCHAR(100) NOT NULL,
        Estado       CHAR(2)      NOT NULL,
        CriadoEm     DATETIME2    NOT NULL CONSTRAINT DF_Enderecos_CriadoEm DEFAULT SYSDATETIME(),
        CONSTRAINT FK_Enderecos_Usuarios FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuarios(Id)
    );
END
GO

-- 7. CUPONS — descontos promocionais
IF OBJECT_ID('dbo.Cupons', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Cupons (
        Id                  INT IDENTITY(1,1) CONSTRAINT PK_Cupons PRIMARY KEY,
        Codigo              VARCHAR(30)   NOT NULL CONSTRAINT UQ_Cupons_Codigo UNIQUE,
        PercentualDesconto  DECIMAL(5,2)  NOT NULL,
        ValorMinimo         DECIMAL(10,2) NOT NULL CONSTRAINT DF_Cupons_Minimo DEFAULT 0,
        ValidoAte           DATE          NULL,
        Ativo               BIT           NOT NULL CONSTRAINT DF_Cupons_Ativo DEFAULT 1,
        CONSTRAINT CK_Cupons_Percentual CHECK (PercentualDesconto > 0 AND PercentualDesconto <= 50)
    );
END
GO

-- 8. PEDIDOS — cabeçalho da venda (Web ou Mobile)
IF OBJECT_ID('dbo.Pedidos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Pedidos (
        Id              INT IDENTITY(1,1) CONSTRAINT PK_Pedidos PRIMARY KEY,
        UsuarioId       INT           NOT NULL,
        EnderecoId      INT           NULL,
        CupomId         INT           NULL,
        DataPedido      DATETIME2     NOT NULL CONSTRAINT DF_Pedidos_Data DEFAULT SYSDATETIME(),
        Subtotal        DECIMAL(10,2) NOT NULL,
        Desconto        DECIMAL(10,2) NOT NULL CONSTRAINT DF_Pedidos_Desconto DEFAULT 0,
        Frete           DECIMAL(10,2) NOT NULL CONSTRAINT DF_Pedidos_Frete DEFAULT 0,
        ValorTotal      DECIMAL(10,2) NOT NULL,
        ValorJogaJunto  DECIMAL(10,2) NOT NULL CONSTRAINT DF_Pedidos_JogaJunto DEFAULT 0, -- 1% para o programa social
        StatusPedido    VARCHAR(30)   NOT NULL CONSTRAINT DF_Pedidos_Status DEFAULT 'Pago',
        FormaPagamento  VARCHAR(50)   NOT NULL,
        Parcelas        TINYINT       NOT NULL CONSTRAINT DF_Pedidos_Parcelas DEFAULT 1,
        CodigoRastreio  VARCHAR(20)   NULL,
        Origem          VARCHAR(10)   NOT NULL CONSTRAINT DF_Pedidos_Origem DEFAULT 'Web',
        AtualizadoEm    DATETIME2     NULL,
        CONSTRAINT FK_Pedidos_Usuarios  FOREIGN KEY (UsuarioId)  REFERENCES dbo.Usuarios(Id),
        CONSTRAINT FK_Pedidos_Enderecos FOREIGN KEY (EnderecoId) REFERENCES dbo.Enderecos(Id),
        CONSTRAINT FK_Pedidos_Cupons    FOREIGN KEY (CupomId)    REFERENCES dbo.Cupons(Id),
        CONSTRAINT CK_Pedidos_Status CHECK (StatusPedido IN ('Aguardando Pagamento', 'Pago', 'Em Separação', 'Enviado', 'Entregue', 'Cancelado')),
        CONSTRAINT CK_Pedidos_Origem CHECK (Origem IN ('Web', 'Mobile')),
        CONSTRAINT CK_Pedidos_Valores CHECK (Subtotal >= 0 AND Desconto >= 0 AND Frete >= 0 AND ValorTotal >= 0)
    );
END
GO

-- 9. ITENS_PEDIDO — tabela associativa Pedidos x Produtos (N:M) com tamanho
IF OBJECT_ID('dbo.ItensPedido', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ItensPedido (
        Id             INT IDENTITY(1,1) CONSTRAINT PK_ItensPedido PRIMARY KEY,
        PedidoId       INT           NOT NULL,
        ProdutoId      INT           NOT NULL,
        Tamanho        VARCHAR(5)    NOT NULL,
        Quantidade     INT           NOT NULL,
        PrecoUnitario  DECIMAL(10,2) NOT NULL,   -- preço congelado no momento da compra
        CONSTRAINT FK_ItensPedido_Pedidos  FOREIGN KEY (PedidoId)  REFERENCES dbo.Pedidos(Id) ON DELETE CASCADE,
        CONSTRAINT FK_ItensPedido_Produtos FOREIGN KEY (ProdutoId) REFERENCES dbo.Produtos(Id),
        CONSTRAINT CK_ItensPedido_Qtd CHECK (Quantidade > 0 AND Quantidade <= 10)
    );
END
GO

-- 10. HISTORICO_STATUS_PEDIDO — linha do tempo de cada pedido (preenchida por trigger)
IF OBJECT_ID('dbo.HistoricoStatusPedido', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HistoricoStatusPedido (
        Id              INT IDENTITY(1,1) CONSTRAINT PK_HistoricoStatusPedido PRIMARY KEY,
        PedidoId        INT          NOT NULL,
        StatusAnterior  VARCHAR(30)  NULL,
        StatusNovo      VARCHAR(30)  NOT NULL,
        DataAlteracao   DATETIME2    NOT NULL CONSTRAINT DF_Historico_Data DEFAULT SYSDATETIME(),
        CONSTRAINT FK_Historico_Pedidos FOREIGN KEY (PedidoId) REFERENCES dbo.Pedidos(Id) ON DELETE CASCADE
    );
END
GO

-- 11. AUDITORIA_ESTOQUE — toda alteração de saldo fica registrada (preenchida por trigger)
IF OBJECT_ID('dbo.AuditoriaEstoque', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AuditoriaEstoque (
        Id              INT IDENTITY(1,1) CONSTRAINT PK_AuditoriaEstoque PRIMARY KEY,
        ProdutoId       INT           NOT NULL,
        Tamanho         VARCHAR(5)    NOT NULL,
        QtdAnterior     INT           NOT NULL,
        QtdNova         INT           NOT NULL,
        OrigemOperacao  NVARCHAR(100) NOT NULL,
        DataOperacao    DATETIME2     NOT NULL CONSTRAINT DF_Auditoria_Data DEFAULT SYSDATETIME()
    );
END
GO

-- 12. AVALIACOES — prova social: nota de 1 a 5 por cliente/produto
IF OBJECT_ID('dbo.Avaliacoes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Avaliacoes (
        Id          INT IDENTITY(1,1) CONSTRAINT PK_Avaliacoes PRIMARY KEY,
        ProdutoId   INT          NOT NULL,
        UsuarioId   INT          NOT NULL,
        Nota        TINYINT      NOT NULL,
        Comentario  VARCHAR(500) NULL,
        CriadoEm    DATETIME2    NOT NULL CONSTRAINT DF_Avaliacoes_CriadoEm DEFAULT SYSDATETIME(),
        Status      VARCHAR(12)  NOT NULL CONSTRAINT DF_Avaliacoes_Status DEFAULT 'Publicada',
        ModeradoPor INT          NULL,             -- admin que fez a última moderação
        ModeradoEm  DATETIME2    NULL,
        MotivoModeracao VARCHAR(200) NULL,
        CONSTRAINT CK_Avaliacoes_Status CHECK (Status IN ('Publicada', 'Pendente', 'Oculta')),
        CONSTRAINT FK_Avaliacoes_Moderador FOREIGN KEY (ModeradoPor) REFERENCES dbo.Usuarios(Id),
        CONSTRAINT FK_Avaliacoes_Produtos FOREIGN KEY (ProdutoId) REFERENCES dbo.Produtos(Id) ON DELETE CASCADE,
        CONSTRAINT FK_Avaliacoes_Usuarios FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuarios(Id),
        CONSTRAINT UQ_Avaliacoes_ProdutoUsuario UNIQUE (ProdutoId, UsuarioId),
        CONSTRAINT CK_Avaliacoes_Nota CHECK (Nota BETWEEN 1 AND 5)
    );
END
GO

-- 13. LOG_ACESSOS — toda tentativa de login (sucesso ou falha), com IP
IF OBJECT_ID('dbo.LogAcessos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.LogAcessos (
        Id         BIGINT IDENTITY(1,1) CONSTRAINT PK_LogAcessos PRIMARY KEY,
        UsuarioId  INT          NULL,               -- NULL quando o e-mail não existe
        Email      VARCHAR(120) NOT NULL,
        Ip         VARCHAR(45)  NULL,               -- IPv4 ou IPv6
        Sucesso    BIT          NOT NULL,
        Detalhe    VARCHAR(60)  NULL,               -- Senha incorreta, Conta bloqueada...
        Data       DATETIME2    NOT NULL CONSTRAINT DF_LogAcessos_Data DEFAULT SYSDATETIME(),
        CONSTRAINT FK_LogAcessos_Usuarios FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuarios(Id)
    );
END
GO

-- ----------------------------------------------------------------------------
-- MIGRAÇÕES — atualizam bancos criados pela versão 1 do script sem perder dados
-- ----------------------------------------------------------------------------
IF COL_LENGTH('dbo.Produtos', 'Marca') IS NULL
    ALTER TABLE dbo.Produtos ADD Marca VARCHAR(40) NULL;
IF COL_LENGTH('dbo.Produtos', 'Solado') IS NULL
    ALTER TABLE dbo.Produtos ADD Solado VARCHAR(40) NULL;
IF COL_LENGTH('dbo.Usuarios', 'TentativasFalhas') IS NULL
    ALTER TABLE dbo.Usuarios ADD TentativasFalhas INT NOT NULL CONSTRAINT DF_Usuarios_Tentativas DEFAULT 0;
IF COL_LENGTH('dbo.Usuarios', 'BloqueadoAte') IS NULL
    ALTER TABLE dbo.Usuarios ADD BloqueadoAte DATETIME2 NULL;
IF COL_LENGTH('dbo.Usuarios', 'VersaoToken') IS NULL
    ALTER TABLE dbo.Usuarios ADD VersaoToken INT NOT NULL CONSTRAINT DF_Usuarios_VersaoToken DEFAULT 1;
IF COL_LENGTH('dbo.Pedidos', 'ValorJogaJunto') IS NULL
    ALTER TABLE dbo.Pedidos ADD ValorJogaJunto DECIMAL(10,2) NOT NULL CONSTRAINT DF_Pedidos_JogaJunto DEFAULT 0;
IF COL_LENGTH('dbo.Avaliacoes', 'Status') IS NULL
    ALTER TABLE dbo.Avaliacoes ADD
        Status VARCHAR(12) NOT NULL CONSTRAINT DF_Avaliacoes_Status DEFAULT 'Publicada'
            CONSTRAINT CK_Avaliacoes_Status CHECK (Status IN ('Publicada', 'Pendente', 'Oculta')),
        ModeradoPor INT NULL CONSTRAINT FK_Avaliacoes_Moderador REFERENCES dbo.Usuarios(Id),
        ModeradoEm DATETIME2 NULL,
        MotivoModeracao VARCHAR(200) NULL;
GO

-- Versão 5: colunas de dados pessoais com espaço para o texto cifrado (AES-256-GCM em Base64)
IF COL_LENGTH('dbo.Enderecos', 'Rua') < 500
BEGIN
    ALTER TABLE dbo.Enderecos ALTER COLUMN Cep         VARCHAR(100) NOT NULL;
    ALTER TABLE dbo.Enderecos ALTER COLUMN Rua         VARCHAR(500) NOT NULL;
    ALTER TABLE dbo.Enderecos ALTER COLUMN Numero      VARCHAR(100) NOT NULL;
    ALTER TABLE dbo.Enderecos ALTER COLUMN Complemento VARCHAR(200) NULL;
    ALTER TABLE dbo.Enderecos ALTER COLUMN Bairro      VARCHAR(400) NOT NULL;
END
IF COL_LENGTH('dbo.Usuarios', 'Telefone') < 100
    ALTER TABLE dbo.Usuarios ALTER COLUMN Telefone VARCHAR(100) NULL;
GO

-- Mascaramento dinâmico (Dynamic Data Masking): quem consulta o banco sem a permissão UNMASK
-- (analistas, relatórios, um login de leitura vazado) vê "mXXX@XXXX.com" e "xxxx" no lugar do
-- e-mail e do IP. A API recebe UNMASK em seguranca.sql porque precisa do e-mail para o login.
IF NOT EXISTS (SELECT 1 FROM sys.masked_columns WHERE object_id = OBJECT_ID('dbo.Usuarios') AND name = 'Email')
    ALTER TABLE dbo.Usuarios ALTER COLUMN Email ADD MASKED WITH (FUNCTION = 'email()');
IF NOT EXISTS (SELECT 1 FROM sys.masked_columns WHERE object_id = OBJECT_ID('dbo.LogAcessos') AND name = 'Email')
    ALTER TABLE dbo.LogAcessos ALTER COLUMN Email ADD MASKED WITH (FUNCTION = 'email()');
IF NOT EXISTS (SELECT 1 FROM sys.masked_columns WHERE object_id = OBJECT_ID('dbo.LogAcessos') AND name = 'Ip')
    ALTER TABLE dbo.LogAcessos ALTER COLUMN Ip ADD MASKED WITH (FUNCTION = 'default()');
GO

-- ============================================================================
-- PARTE 2 — ÍNDICES (OTIMIZAÇÃO DAS CONSULTAS MAIS FREQUENTES)
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Produtos_Categoria_Ativo')
    CREATE INDEX IX_Produtos_Categoria_Ativo ON dbo.Produtos (CategoriaId, Ativo) INCLUDE (Nome, Preco, PrecoPromocional, Linha, Imagem);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Produtos_Linha')
    CREATE INDEX IX_Produtos_Linha ON dbo.Produtos (Linha, Ativo);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ProdutoImagens_Produto')
    CREATE INDEX IX_ProdutoImagens_Produto ON dbo.ProdutoImagens (ProdutoId, Ordem);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Pedidos_Usuario_Data')
    CREATE INDEX IX_Pedidos_Usuario_Data ON dbo.Pedidos (UsuarioId, DataPedido DESC);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Pedidos_Status')
    CREATE INDEX IX_Pedidos_Status ON dbo.Pedidos (StatusPedido) INCLUDE (ValorTotal, DataPedido);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ItensPedido_Pedido')
    CREATE INDEX IX_ItensPedido_Pedido ON dbo.ItensPedido (PedidoId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ItensPedido_Produto')
    CREATE INDEX IX_ItensPedido_Produto ON dbo.ItensPedido (ProdutoId) INCLUDE (Quantidade, PrecoUnitario);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Auditoria_Produto_Data')
    CREATE INDEX IX_Auditoria_Produto_Data ON dbo.AuditoriaEstoque (ProdutoId, DataOperacao DESC);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Avaliacoes_Produto')
    CREATE INDEX IX_Avaliacoes_Produto ON dbo.Avaliacoes (ProdutoId) INCLUDE (Nota);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Produtos_Marca')
    CREATE INDEX IX_Produtos_Marca ON dbo.Produtos (Marca, Ativo) WHERE Marca IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Avaliacoes_Status')
    CREATE INDEX IX_Avaliacoes_Status ON dbo.Avaliacoes (Status, CriadoEm DESC);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_LogAcessos_Data')
    CREATE INDEX IX_LogAcessos_Data ON dbo.LogAcessos (Data DESC) INCLUDE (Email, Sucesso);
GO

-- ============================================================================
-- PARTE 3 — FUNÇÃO
-- ============================================================================

-- fn_CalcularFrete: frete grátis a partir de R$ 299,00; abaixo disso, R$ 19,90
CREATE OR ALTER FUNCTION dbo.fn_CalcularFrete (@ValorProdutos DECIMAL(10,2))
RETURNS DECIMAL(10,2)
AS
BEGIN
    RETURN CASE WHEN @ValorProdutos >= 299.00 OR @ValorProdutos = 0 THEN 0.00 ELSE 19.90 END;
END;
GO

-- fn_CalcularJogaJunto: 1% do valor dos produtos (já com desconto, sem frete) vai para
-- o programa Joga Junto, que apoia escolinhas de futebol. Valor gravado em cada pedido.
CREATE OR ALTER FUNCTION dbo.fn_CalcularJogaJunto (@ValorProdutos DECIMAL(10,2))
RETURNS DECIMAL(10,2)
AS
BEGIN
    RETURN CASE WHEN @ValorProdutos <= 0 THEN 0.00 ELSE ROUND(@ValorProdutos * 0.01, 2) END;
END;
GO

-- Migração da versão 4: pedidos anteriores à coluna ValorJogaJunto ficaram com o padrão 0
UPDATE dbo.Pedidos
SET ValorJogaJunto = dbo.fn_CalcularJogaJunto(Subtotal - Desconto)
WHERE ValorJogaJunto = 0 AND Subtotal - Desconto > 0;
GO

-- ============================================================================
-- PARTE 4 — VIEWS
-- ============================================================================

-- vw_CatalogoProdutos: vitrine pronta (categoria, estoque total, nota média)
CREATE OR ALTER VIEW dbo.vw_CatalogoProdutos
AS
SELECT
    P.Id, P.Nome, P.Modelo, P.Linha, P.Equipe, P.Ano, P.Marca, P.Solado, P.Descricao,
    P.Preco, P.PrecoPromocional,
    COALESCE(P.PrecoPromocional, P.Preco) AS PrecoFinal,
    P.Imagem, P.Destaque, P.CategoriaId,
    C.Nome AS Categoria, C.Slug AS CategoriaSlug,
    ISNULL(E.EstoqueTotal, 0)      AS EstoqueTotal,
    ISNULL(A.NotaMedia, 0)         AS NotaMedia,
    ISNULL(A.TotalAvaliacoes, 0)   AS TotalAvaliacoes
FROM dbo.Produtos P
INNER JOIN dbo.Categorias C ON C.Id = P.CategoriaId
LEFT JOIN (SELECT ProdutoId, SUM(Quantidade) AS EstoqueTotal FROM dbo.Estoque GROUP BY ProdutoId) E
       ON E.ProdutoId = P.Id
LEFT JOIN (SELECT ProdutoId, CAST(AVG(CAST(Nota AS DECIMAL(4,2))) AS DECIMAL(3,2)) AS NotaMedia,
                  COUNT(1) AS TotalAvaliacoes
           FROM dbo.Avaliacoes WHERE Status = 'Publicada' GROUP BY ProdutoId) A
       ON A.ProdutoId = P.Id
WHERE P.Ativo = 1 AND C.Ativo = 1;
GO

-- vw_PedidosDetalhados: pedidos com cliente e quantidade de peças
CREATE OR ALTER VIEW dbo.vw_PedidosDetalhados
AS
SELECT
    PE.Id AS PedidoId, PE.DataPedido, U.Nome AS Cliente, U.Email,
    PE.Subtotal, PE.Desconto, PE.Frete, PE.ValorTotal, PE.ValorJogaJunto,
    PE.StatusPedido, PE.FormaPagamento, PE.Parcelas, PE.CodigoRastreio, PE.Origem,
    (SELECT SUM(I.Quantidade) FROM dbo.ItensPedido I WHERE I.PedidoId = PE.Id) AS TotalPecas
FROM dbo.Pedidos PE
INNER JOIN dbo.Usuarios U ON U.Id = PE.UsuarioId;
GO

-- vw_ProdutosMaisVendidos: ranking de vendas (pedidos não cancelados)
CREATE OR ALTER VIEW dbo.vw_ProdutosMaisVendidos
AS
SELECT
    P.Id AS ProdutoId, P.Nome, C.Nome AS Categoria, P.Linha,
    SUM(I.Quantidade)                    AS UnidadesVendidas,
    SUM(I.Quantidade * I.PrecoUnitario)  AS Receita
FROM dbo.ItensPedido I
INNER JOIN dbo.Pedidos PE   ON PE.Id = I.PedidoId AND PE.StatusPedido <> 'Cancelado'
INNER JOIN dbo.Produtos P   ON P.Id  = I.ProdutoId
INNER JOIN dbo.Categorias C ON C.Id  = P.CategoriaId
GROUP BY P.Id, P.Nome, C.Nome, P.Linha;
GO

-- ============================================================================
-- PARTE 5 — TRIGGERS
-- ============================================================================

-- TRIGGER 1: trg_AuditoriaEstoque
-- Registra em AuditoriaEstoque TODA inserção ou alteração de saldo, seja pelo
-- painel, por uma venda ou por um UPDATE manual. A origem vem do SESSION_CONTEXT
-- definido pelas procedures (quando não houver, grava "Alteração direta").
CREATE OR ALTER TRIGGER dbo.trg_AuditoriaEstoque
ON dbo.Estoque
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Origem NVARCHAR(100) =
        ISNULL(CAST(SESSION_CONTEXT(N'origem') AS NVARCHAR(100)), N'Alteração direta no banco');

    INSERT INTO dbo.AuditoriaEstoque (ProdutoId, Tamanho, QtdAnterior, QtdNova, OrigemOperacao)
    SELECT I.ProdutoId, I.Tamanho, ISNULL(D.Quantidade, 0), I.Quantidade, @Origem
    FROM inserted I
    LEFT JOIN deleted D ON D.Id = I.Id
    WHERE D.Id IS NULL OR D.Quantidade <> I.Quantidade;
END;
GO

-- TRIGGER 2: trg_BaixaEstoqueAposPedido
-- Ao inserir itens de pedido, valida e abate o saldo do tamanho comprado.
-- Se faltar estoque, lança erro e a transação inteira do pedido é desfeita.
CREATE OR ALTER TRIGGER dbo.trg_BaixaEstoqueAposPedido
ON dbo.ItensPedido
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM (SELECT ProdutoId, Tamanho, SUM(Quantidade) AS Qtd FROM inserted GROUP BY ProdutoId, Tamanho) I
        LEFT JOIN dbo.Estoque E ON E.ProdutoId = I.ProdutoId AND E.Tamanho = I.Tamanho
        WHERE E.Id IS NULL OR E.Quantidade < I.Qtd
    )
        THROW 50010, 'Estoque insuficiente para um ou mais itens do pedido.', 1;

    DECLARE @Origem NVARCHAR(100) = CONCAT(N'Venda - Pedido #', (SELECT MIN(PedidoId) FROM inserted));
    EXEC sys.sp_set_session_context @key = N'origem', @value = @Origem;

    UPDATE E
       SET E.Quantidade = E.Quantidade - I.Qtd,
           E.UltimaAtualizacao = SYSDATETIME()
    FROM dbo.Estoque E
    INNER JOIN (SELECT ProdutoId, Tamanho, SUM(Quantidade) AS Qtd FROM inserted GROUP BY ProdutoId, Tamanho) I
            ON E.ProdutoId = I.ProdutoId AND E.Tamanho = I.Tamanho;

    EXEC sys.sp_set_session_context @key = N'origem', @value = NULL;
END;
GO

-- TRIGGER 3: trg_HistoricoStatusPedido
-- Gera a linha do tempo do pedido sempre que ele é criado ou muda de status.
CREATE OR ALTER TRIGGER dbo.trg_HistoricoStatusPedido
ON dbo.Pedidos
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.HistoricoStatusPedido (PedidoId, StatusAnterior, StatusNovo)
    SELECT I.Id, D.StatusPedido, I.StatusPedido
    FROM inserted I
    LEFT JOIN deleted D ON D.Id = I.Id
    WHERE D.Id IS NULL OR D.StatusPedido <> I.StatusPedido;
END;
GO

-- ============================================================================
-- PARTE 6 — STORED PROCEDURES
-- ============================================================================

-- PROCEDURE 1: sp_AtualizarEstoque
-- Define (ou cria) o saldo de um tamanho. A auditoria é feita pelo trigger.
CREATE OR ALTER PROCEDURE dbo.sp_AtualizarEstoque
    @ProdutoId      INT,
    @Tamanho        VARCHAR(5),
    @NovaQuantidade INT,
    @Origem         NVARCHAR(100) = N'Painel Administrativo'
AS
BEGIN
    SET NOCOUNT ON;
    IF @NovaQuantidade < 0
        THROW 50001, 'A quantidade em estoque não pode ser negativa.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Produtos WHERE Id = @ProdutoId)
        THROW 50002, 'Produto não encontrado.', 1;

    EXEC sys.sp_set_session_context @key = N'origem', @value = @Origem;

    IF EXISTS (SELECT 1 FROM dbo.Estoque WHERE ProdutoId = @ProdutoId AND Tamanho = @Tamanho)
        UPDATE dbo.Estoque
           SET Quantidade = @NovaQuantidade, UltimaAtualizacao = SYSDATETIME()
         WHERE ProdutoId = @ProdutoId AND Tamanho = @Tamanho;
    ELSE
        INSERT INTO dbo.Estoque (ProdutoId, Tamanho, Quantidade) VALUES (@ProdutoId, @Tamanho, @NovaQuantidade);

    EXEC sys.sp_set_session_context @key = N'origem', @value = NULL;
END;
GO

-- PROCEDURE 2: sp_RegistrarPedido
-- Fecha uma venda de forma TRANSACIONAL (ACID):
--   1) lê os itens em JSON  2) valida produto, tamanho e estoque com bloqueio
--   3) calcula preços NO BANCO (o cliente não define o valor)  4) aplica cupom e frete
--   5) grava cabeçalho + itens (o trigger baixa o estoque)  6) devolve id e rastreio
-- Formato de @ItensJson: [{"produtoId":1,"tamanho":"M","quantidade":2}, ...]
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarPedido
    @UsuarioId       INT,
    @ItensJson       NVARCHAR(MAX),
    @FormaPagamento  VARCHAR(50),
    @Parcelas        TINYINT      = 1,
    @CodigoCupom     VARCHAR(30)  = NULL,
    @EnderecoId      INT          = NULL,
    @Origem          VARCHAR(10)  = 'Web',
    @PedidoId        INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Itens TABLE (ProdutoId INT, Tamanho VARCHAR(5), Quantidade INT, PrecoUnitario DECIMAL(10,2));

    INSERT INTO @Itens (ProdutoId, Tamanho, Quantidade)
    SELECT ProdutoId, UPPER(Tamanho), SUM(Quantidade)
    FROM OPENJSON(@ItensJson)
         WITH (ProdutoId INT '$.produtoId', Tamanho VARCHAR(5) '$.tamanho', Quantidade INT '$.quantidade')
    GROUP BY ProdutoId, UPPER(Tamanho);

    IF NOT EXISTS (SELECT 1 FROM @Itens)
        THROW 50020, 'O pedido não possui itens.', 1;
    IF EXISTS (SELECT 1 FROM @Itens WHERE Quantidade IS NULL OR Quantidade <= 0 OR Quantidade > 10)
        THROW 50021, 'Quantidade inválida (permitido de 1 a 10 unidades por item).', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuarios WHERE Id = @UsuarioId AND Ativo = 1)
        THROW 50022, 'Usuário inválido ou inativo.', 1;
    IF @EnderecoId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Enderecos WHERE Id = @EnderecoId AND UsuarioId = @UsuarioId)
        THROW 50023, 'Endereço de entrega inválido.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Preço vem SEMPRE do cadastro do produto (proteção contra adulteração no front)
        UPDATE I SET I.PrecoUnitario = COALESCE(P.PrecoPromocional, P.Preco)
        FROM @Itens I
        INNER JOIN dbo.Produtos P ON P.Id = I.ProdutoId AND P.Ativo = 1;

        IF EXISTS (SELECT 1 FROM @Itens WHERE PrecoUnitario IS NULL)
            THROW 50024, 'Um ou mais produtos não estão disponíveis.', 1;

        -- Verificação de estoque com bloqueio das linhas (evita venda dupla concorrente)
        IF EXISTS (
            SELECT 1 FROM @Itens I
            LEFT JOIN dbo.Estoque E WITH (UPDLOCK, HOLDLOCK)
                   ON E.ProdutoId = I.ProdutoId AND E.Tamanho = I.Tamanho
            WHERE E.Id IS NULL OR E.Quantidade < I.Quantidade
        )
            THROW 50025, 'Estoque insuficiente para um ou mais itens (verifique os tamanhos).', 1;

        DECLARE @Subtotal DECIMAL(10,2) = (SELECT SUM(Quantidade * PrecoUnitario) FROM @Itens);
        DECLARE @Desconto DECIMAL(10,2) = 0;
        DECLARE @CupomId INT = NULL;

        IF NULLIF(LTRIM(RTRIM(@CodigoCupom)), '') IS NOT NULL
        BEGIN
            DECLARE @Percentual DECIMAL(5,2), @Minimo DECIMAL(10,2);
            SELECT @CupomId = Id, @Percentual = PercentualDesconto, @Minimo = ValorMinimo
            FROM dbo.Cupons
            WHERE Codigo = UPPER(LTRIM(RTRIM(@CodigoCupom))) AND Ativo = 1
              AND (ValidoAte IS NULL OR ValidoAte >= CAST(GETDATE() AS DATE));

            IF @CupomId IS NULL
                THROW 50026, 'Cupom inválido ou expirado.', 1;
            IF @Subtotal < @Minimo
                THROW 50027, 'O valor do pedido não atinge o mínimo exigido pelo cupom.', 1;

            SET @Desconto = ROUND(@Subtotal * @Percentual / 100.0, 2);
        END

        DECLARE @Frete DECIMAL(10,2) = dbo.fn_CalcularFrete(@Subtotal - @Desconto);

        INSERT INTO dbo.Pedidos
            (UsuarioId, EnderecoId, CupomId, Subtotal, Desconto, Frete, ValorTotal, ValorJogaJunto,
             StatusPedido, FormaPagamento, Parcelas, Origem)
        VALUES
            (@UsuarioId, @EnderecoId, @CupomId, @Subtotal, @Desconto, @Frete, @Subtotal - @Desconto + @Frete,
             dbo.fn_CalcularJogaJunto(@Subtotal - @Desconto),
             'Pago', @FormaPagamento, ISNULL(@Parcelas, 1), ISNULL(@Origem, 'Web'));

        SET @PedidoId = SCOPE_IDENTITY();

        UPDATE dbo.Pedidos
           SET CodigoRastreio = CONCAT('JB', RIGHT(CONCAT('000000000', @PedidoId), 9), 'BR')
         WHERE Id = @PedidoId;

        -- Inserção dos itens: dispara trg_BaixaEstoqueAposPedido
        INSERT INTO dbo.ItensPedido (PedidoId, ProdutoId, Tamanho, Quantidade, PrecoUnitario)
        SELECT @PedidoId, ProdutoId, Tamanho, Quantidade, PrecoUnitario FROM @Itens;

        COMMIT TRANSACTION;

        SELECT Id, Subtotal, Desconto, Frete, ValorTotal, ValorJogaJunto, CodigoRastreio, StatusPedido
        FROM dbo.Pedidos WHERE Id = @PedidoId;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- PROCEDURE 3: sp_AtualizarStatusPedido
-- Avança o status respeitando o fluxo. Cancelamento devolve as peças ao estoque.
CREATE OR ALTER PROCEDURE dbo.sp_AtualizarStatusPedido
    @PedidoId    INT,
    @NovoStatus  VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Atual VARCHAR(30) = (SELECT StatusPedido FROM dbo.Pedidos WHERE Id = @PedidoId);

    IF @Atual IS NULL
        THROW 50030, 'Pedido não encontrado.', 1;
    IF @Atual IN ('Entregue', 'Cancelado')
        THROW 50031, 'Pedidos entregues ou cancelados não podem mais ser alterados.', 1;
    IF @NovoStatus = 'Cancelado' AND @Atual = 'Enviado'
        THROW 50032, 'Pedido já enviado: registre uma devolução em vez de cancelar.', 1;

    BEGIN TRANSACTION;

        UPDATE dbo.Pedidos SET StatusPedido = @NovoStatus, AtualizadoEm = SYSDATETIME() WHERE Id = @PedidoId;

        IF @NovoStatus = 'Cancelado'
        BEGIN
            DECLARE @Origem NVARCHAR(100) = CONCAT(N'Cancelamento - Pedido #', @PedidoId);
            EXEC sys.sp_set_session_context @key = N'origem', @value = @Origem;

            UPDATE E SET E.Quantidade = E.Quantidade + I.Quantidade, E.UltimaAtualizacao = SYSDATETIME()
            FROM dbo.Estoque E
            INNER JOIN dbo.ItensPedido I ON I.ProdutoId = E.ProdutoId AND I.Tamanho = E.Tamanho
            WHERE I.PedidoId = @PedidoId;

            EXEC sys.sp_set_session_context @key = N'origem', @value = NULL;
        END

    COMMIT TRANSACTION;
END;
GO

-- PROCEDURE 4: sp_RelatorioEstoqueGeral
-- Saldo por produto e tamanho, com classificação ESGOTADO / BAIXO (< 5) / REGULAR.
CREATE OR ALTER PROCEDURE dbo.sp_RelatorioEstoqueGeral
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        P.Id AS ProdutoId, P.Nome, P.Linha, C.Nome AS Categoria,
        E.Tamanho, E.Quantidade,
        CASE WHEN E.Quantidade = 0 THEN 'ESGOTADO'
             WHEN E.Quantidade < 5  THEN 'BAIXO'
             ELSE 'REGULAR' END AS StatusNivel,
        E.UltimaAtualizacao
    FROM dbo.Produtos P
    INNER JOIN dbo.Categorias C ON C.Id = P.CategoriaId
    INNER JOIN dbo.Estoque E    ON E.ProdutoId = P.Id
    WHERE P.Ativo = 1
    ORDER BY P.Id,
             CASE E.Tamanho WHEN 'PP' THEN 1 WHEN 'P' THEN 2 WHEN 'M' THEN 3 WHEN 'G' THEN 4
                            WHEN 'GG' THEN 5 WHEN 'XG' THEN 6 ELSE 10 END,
             E.Tamanho;
END;
GO

-- PROCEDURE 5: sp_RelatorioVendas
-- Indicadores do período para o dashboard: totais, ticket médio e vendas por categoria.
CREATE OR ALTER PROCEDURE dbo.sp_RelatorioVendas
    @DataInicio DATE = NULL,
    @DataFim    DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @DataInicio = ISNULL(@DataInicio, DATEADD(DAY, -30, CAST(GETDATE() AS DATE)));
    SET @DataFim    = ISNULL(@DataFim, CAST(GETDATE() AS DATE));

    -- Resultado 1: resumo
    SELECT
        COUNT(1)                      AS TotalPedidos,
        ISNULL(SUM(ValorTotal), 0)    AS Faturamento,
        ISNULL(AVG(ValorTotal), 0)    AS TicketMedio,
        ISNULL(SUM(Desconto), 0)      AS DescontosConcedidos
    FROM dbo.Pedidos
    WHERE StatusPedido <> 'Cancelado'
      AND CAST(DataPedido AS DATE) BETWEEN @DataInicio AND @DataFim;

    -- Resultado 2: por categoria
    SELECT
        C.Nome AS Categoria,
        SUM(I.Quantidade)                   AS Unidades,
        SUM(I.Quantidade * I.PrecoUnitario) AS Receita
    FROM dbo.ItensPedido I
    INNER JOIN dbo.Pedidos PE   ON PE.Id = I.PedidoId
    INNER JOIN dbo.Produtos P   ON P.Id  = I.ProdutoId
    INNER JOIN dbo.Categorias C ON C.Id  = P.CategoriaId
    WHERE PE.StatusPedido <> 'Cancelado'
      AND CAST(PE.DataPedido AS DATE) BETWEEN @DataInicio AND @DataFim
    GROUP BY C.Nome
    ORDER BY Receita DESC;
END;
GO

-- PROCEDURE 6: sp_RegistrarAvaliacao
-- Só quem comprou o produto (pedido não cancelado) pode avaliar; reenvio atualiza a nota.
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarAvaliacao
    @ProdutoId  INT,
    @UsuarioId  INT,
    @Nota       TINYINT,
    @Comentario VARCHAR(500) = NULL,
    @Status     VARCHAR(12)  = 'Publicada'   -- a API manda 'Pendente' quando o texto precisa de revisão
AS
BEGIN
    SET NOCOUNT ON;
    IF @Status NOT IN ('Publicada', 'Pendente')
        THROW 50041, 'Situação inicial de avaliação inválida.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.ItensPedido I
        INNER JOIN dbo.Pedidos P ON P.Id = I.PedidoId
        WHERE I.ProdutoId = @ProdutoId AND P.UsuarioId = @UsuarioId AND P.StatusPedido <> 'Cancelado'
    )
        THROW 50040, 'Somente clientes que compraram este produto podem avaliá-lo.', 1;

    MERGE dbo.Avaliacoes AS Alvo
    USING (SELECT @ProdutoId AS ProdutoId, @UsuarioId AS UsuarioId) AS Origem
       ON Alvo.ProdutoId = Origem.ProdutoId AND Alvo.UsuarioId = Origem.UsuarioId
    WHEN MATCHED THEN
        -- Avaliação ocultada pelo admin e reescrita volta para a fila (não se publica sozinha)
        UPDATE SET Nota = @Nota, Comentario = @Comentario, CriadoEm = SYSDATETIME(),
                   Status = CASE WHEN Alvo.Status = 'Oculta' THEN 'Pendente' ELSE @Status END
    WHEN NOT MATCHED THEN
        INSERT (ProdutoId, UsuarioId, Nota, Comentario, Status) VALUES (@ProdutoId, @UsuarioId, @Nota, @Comentario, @Status);
END;
GO

-- sp_ModerarAvaliacao: o administrador publica ou oculta uma avaliação (por exemplo,
-- com conteúdo ofensivo ou discriminatório). Quem moderou, quando e o motivo ficam
-- gravados na própria avaliação para auditoria.
CREATE OR ALTER PROCEDURE dbo.sp_ModerarAvaliacao
    @AvaliacaoId INT,
    @NovoStatus  VARCHAR(12),
    @AdminId     INT,
    @Motivo      VARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @NovoStatus NOT IN ('Publicada', 'Oculta')
        THROW 50042, 'Use Publicada ou Oculta.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuarios WHERE Id = @AdminId AND Role = 'Admin' AND Ativo = 1)
        THROW 50043, 'Somente administradores podem moderar avaliações.', 1;
    IF @NovoStatus = 'Oculta' AND NULLIF(LTRIM(RTRIM(@Motivo)), '') IS NULL
        THROW 50044, 'Informe o motivo para ocultar a avaliação.', 1;

    UPDATE dbo.Avaliacoes
       SET Status = @NovoStatus, ModeradoPor = @AdminId, ModeradoEm = SYSDATETIME(),
           MotivoModeracao = NULLIF(LTRIM(RTRIM(@Motivo)), '')
     WHERE Id = @AvaliacaoId;
    IF @@ROWCOUNT = 0
        THROW 50045, 'Avaliação não encontrada.', 1;
END;
GO

-- sp_AnonimizarUsuario: atende ao pedido de exclusão de dados (LGPD, art. 18).
-- Remove nome, e-mail, telefone, endereços e avaliações do titular e desativa a conta.
-- Os PEDIDOS são mantidos sem dados pessoais (obrigação fiscal), ligados a um cliente anônimo.
CREATE OR ALTER PROCEDURE dbo.sp_AnonimizarUsuario
    @UsuarioId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @EmailAnonimo VARCHAR(120) = CONCAT('removido-', @UsuarioId, '@anonimo.invalid');
    DECLARE @EmailAntigo VARCHAR(120) = (SELECT Email FROM dbo.Usuarios WHERE Id = @UsuarioId);

    IF @EmailAntigo IS NULL
        THROW 50046, 'Usuário não encontrado.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Usuarios WHERE Id = @UsuarioId AND Role = 'Admin')
        THROW 50047, 'Contas de administrador não podem ser excluídas por aqui.', 1;

    BEGIN TRANSACTION;
        UPDATE dbo.Usuarios
           SET Nome = 'Cliente removido', Email = @EmailAnonimo, SenhaHash = '!removido',
               Telefone = NULL, Ativo = 0, VersaoToken = VersaoToken + 1,
               TentativasFalhas = 0, BloqueadoAte = NULL
         WHERE Id = @UsuarioId;

        UPDATE dbo.Enderecos
           SET Cep = '00000000', Rua = 'Removido (LGPD)', Numero = '-', Complemento = NULL, Bairro = 'Removido'
         WHERE UsuarioId = @UsuarioId;

        DELETE FROM dbo.Avaliacoes WHERE UsuarioId = @UsuarioId;

        UPDATE dbo.LogAcessos SET Email = @EmailAnonimo, Ip = NULL WHERE UsuarioId = @UsuarioId OR Email = @EmailAntigo;

        INSERT INTO dbo.LogAcessos (UsuarioId, Email, Ip, Sucesso, Detalhe)
        VALUES (@UsuarioId, @EmailAnonimo, NULL, 1, 'Conta excluída (LGPD)');
    COMMIT TRANSACTION;
END;
GO

-- sp_RegistrarTentativaLogin: grava o log de acesso e aplica a regra de bloqueio
-- (5 senhas erradas seguidas = conta bloqueada por 15 minutos). Atômica: duas
-- tentativas simultâneas não conseguem "pular" o contador.
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarTentativaLogin
    @Email         VARCHAR(120),
    @Sucesso       BIT,
    @Ip            VARCHAR(45) = NULL,
    @Detalhe       VARCHAR(60) = NULL,
    @BloqueadoAte  DATETIME2 = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @MaxTentativas INT = 5, @MinutosBloqueio INT = 15;
    DECLARE @UsuarioId INT;

    BEGIN TRANSACTION;
        SELECT @UsuarioId = Id
        FROM dbo.Usuarios WITH (UPDLOCK, HOLDLOCK)
        WHERE Email = @Email;

        IF @UsuarioId IS NOT NULL
        BEGIN
            IF @Sucesso = 1
                UPDATE dbo.Usuarios SET TentativasFalhas = 0, BloqueadoAte = NULL WHERE Id = @UsuarioId;
            ELSE
                -- Durante o bloqueio as tentativas só são registradas no log (não renovam o prazo)
                UPDATE dbo.Usuarios
                SET TentativasFalhas = CASE WHEN TentativasFalhas + 1 >= @MaxTentativas THEN 0 ELSE TentativasFalhas + 1 END,
                    BloqueadoAte     = CASE WHEN TentativasFalhas + 1 >= @MaxTentativas
                                            THEN DATEADD(MINUTE, @MinutosBloqueio, SYSDATETIME())
                                            ELSE BloqueadoAte END
                WHERE Id = @UsuarioId
                  AND (BloqueadoAte IS NULL OR BloqueadoAte <= SYSDATETIME());

            SELECT @BloqueadoAte = CASE WHEN BloqueadoAte > SYSDATETIME() THEN BloqueadoAte END
            FROM dbo.Usuarios WHERE Id = @UsuarioId;
        END

        INSERT INTO dbo.LogAcessos (UsuarioId, Email, Ip, Sucesso, Detalhe)
        VALUES (@UsuarioId, @Email, @Ip, @Sucesso, @Detalhe);
    COMMIT TRANSACTION;
END;
GO

-- ----------------------------------------------------------------------------
-- sp_ExpurgarRegistrosAntigos: retenção mínima (LGPD art. 15/16). O log de acessos guarda
-- e-mail e IP; depois de @Dias dias ele não serve mais para investigar incidentes e é apagado.
-- Chamada uma vez por dia pela API (RotinaRetencao). Devolve quantas linhas apagou.
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.sp_ExpurgarRegistrosAntigos
    @Dias INT = 180
AS
BEGIN
    SET NOCOUNT ON;
    IF @Dias < 30 THROW 50010, 'A retenção mínima do log de acessos é de 30 dias.', 1;
    DELETE FROM dbo.LogAcessos WHERE Data < DATEADD(DAY, -@Dias, SYSDATETIME());
    SELECT @@ROWCOUNT AS Apagados;
END;
GO
