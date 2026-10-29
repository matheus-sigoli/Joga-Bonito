-- ============================================================================
-- JOGA BONITO — DADOS DE DEMONSTRAÇÃO (contas, pedidos e avaliações)
-- PIM IV · UNIP 2026/2
-- Carregado só quando Banco:CarregarDemonstracao = true (ambiente Development,
-- docker-compose local). Em produção, o administrador é criado pelas variáveis
-- Banco__AdminEmail e Banco__AdminSenha, e não existem contas com senha pública.
-- ============================================================================

-- Índices filtrados exigem estas opções; o sqlcmd vem com QUOTED_IDENTIFIER OFF
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ----------------------------------------------------------------------------
-- 1. USUÁRIOS DE DEMONSTRAÇÃO (senhas em hash BCrypt, custo 11)
--    admin@jogabonito.com  / Admin@2026    (Administrador)
--    matheus@estudante.com / Cliente@2026  (Cliente)
--    professor@unip.br     / Unip@2026     (Cliente — acesso do avaliador)
-- ----------------------------------------------------------------------------
INSERT INTO dbo.Usuarios (Nome, Email, SenhaHash, Role, AceiteLgpdEm)
SELECT N.Nome, N.Email, N.SenhaHash, N.Role, SYSDATETIME()
FROM (VALUES
    ('Administrador Joga Bonito', 'admin@jogabonito.com',  '$2b$11$rRNFY.UXVEAeVxCfOMCjgOHmaxZXVv7I1vJC2K.F2ZhrbJemtpI/e', 'Admin'),
    ('Matheus Sigoli',            'matheus@estudante.com', '$2b$11$HOijHJnaaOl2FOw2i0R1zO1RsPOzlcNJmBczoQOwhomijcudfXhDG', 'Cliente'),
    ('Professor Avaliador',       'professor@unip.br',     '$2b$11$UhkALb1XySrHRWC12bQ69..4FzOWiGmpXLnqOn1o2HvOOSTtStQKa', 'Cliente')
) N(Nome, Email, SenhaHash, Role)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Usuarios U WHERE U.Email = N.Email);
GO

-- ----------------------------------------------------------------------------
-- 2. PEDIDOS E AVALIAÇÕES DE DEMONSTRAÇÃO (passam pela procedure oficial)
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.Pedidos)
BEGIN
    DECLARE @Cliente INT = (SELECT Id FROM dbo.Usuarios WHERE Email = 'matheus@estudante.com');
    DECLARE @Prof INT    = (SELECT Id FROM dbo.Usuarios WHERE Email = 'professor@unip.br');
    DECLARE @NovoPedido INT;

    INSERT INTO dbo.Enderecos (UsuarioId, Cep, Rua, Numero, Bairro, Cidade, Estado)
    VALUES (@Cliente, '01310100', 'Avenida Paulista', '1000', 'Bela Vista', 'São Paulo', 'SP');
    DECLARE @End INT = SCOPE_IDENTITY();

    EXEC dbo.sp_RegistrarPedido @UsuarioId = @Cliente,
         @ItensJson = N'[{"produtoId":1,"tamanho":"M","quantidade":1},{"produtoId":13,"tamanho":"G","quantidade":1}]',
         @FormaPagamento = 'PIX', @CodigoCupom = 'BEMVINDO10', @EnderecoId = @End, @Origem = 'Web',
         @PedidoId = @NovoPedido OUTPUT;
    EXEC dbo.sp_AtualizarStatusPedido @PedidoId = @NovoPedido, @NovoStatus = 'Em Separação';
    EXEC dbo.sp_AtualizarStatusPedido @PedidoId = @NovoPedido, @NovoStatus = 'Enviado';
    EXEC dbo.sp_AtualizarStatusPedido @PedidoId = @NovoPedido, @NovoStatus = 'Entregue';

    EXEC dbo.sp_RegistrarPedido @UsuarioId = @Cliente,
         @ItensJson = N'[{"produtoId":30,"tamanho":"41","quantidade":1}]',
         @FormaPagamento = 'Cartão de Crédito', @Parcelas = 3, @EnderecoId = @End, @Origem = 'Mobile',
         @PedidoId = @NovoPedido OUTPUT;

    EXEC dbo.sp_RegistrarPedido @UsuarioId = @Prof,
         @ItensJson = N'[{"produtoId":14,"tamanho":"M","quantidade":1},{"produtoId":9,"tamanho":"G","quantidade":1}]',
         @FormaPagamento = 'PIX', @Origem = 'Web',
         @PedidoId = @NovoPedido OUTPUT;

    EXEC dbo.sp_RegistrarAvaliacao 1, @Cliente, 5, 'Tecido muito bom e o tamanho M ficou certinho. Chegou antes do prazo.';
    EXEC dbo.sp_RegistrarAvaliacao 13, @Cliente, 5, 'Réplica caprichada, gola idêntica à do tetra. Virou peça de coleção.';
    EXEC dbo.sp_RegistrarAvaliacao 14, @Prof, 4, 'Bonita e bem acabada. Veste um pouco justa, recomendo um número acima.';
END
GO
