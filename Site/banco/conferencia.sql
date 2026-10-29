-- ============================================================================
-- JOGA BONITO — conferência de consistência do banco
-- Rode no SSMS / Azure Data Studio depois dos testes (ou a qualquer momento).
-- Cada linha do resultado é uma regra: "OK" ou "FALHA" com quantos registros a violam.
-- Somente leitura: não altera nada.
-- ============================================================================
SET NOCOUNT ON;

DECLARE @R TABLE (Ordem INT IDENTITY, Regra NVARCHAR(200), Problemas INT);

-- Catálogo
INSERT @R SELECT N'36 produtos do catálogo ativos (IDs 1 a 36)',
    36 - (SELECT COUNT(1) FROM dbo.Produtos WHERE Id BETWEEN 1 AND 36 AND Ativo = 1);
INSERT @R SELECT N'Todo produto ativo tem estoque para os tamanhos do seu tipo',
    (SELECT COUNT(1) FROM dbo.Produtos P
     WHERE P.Ativo = 1 AND (SELECT COUNT(1) FROM dbo.Estoque E WHERE E.ProdutoId = P.Id) NOT IN (5, 8));
INSERT @R SELECT N'Chuteiras só com numeração 37–44; camisas só P–XG',
    (SELECT COUNT(1) FROM dbo.Estoque E JOIN dbo.Produtos P ON P.Id = E.ProdutoId JOIN dbo.Categorias C ON C.Id = P.CategoriaId
     WHERE (C.Slug = 'chuteiras' AND E.Tamanho NOT IN ('37','38','39','40','41','42','43','44'))
        OR (C.Slug <> 'chuteiras' AND E.Tamanho NOT IN ('P','M','G','GG','XG')));
INSERT @R SELECT N'Nenhum saldo de estoque negativo', (SELECT COUNT(1) FROM dbo.Estoque WHERE Quantidade < 0);
INSERT @R SELECT N'Todo produto ativo tem ao menos uma imagem na galeria',
    (SELECT COUNT(1) FROM dbo.Produtos P WHERE P.Ativo = 1 AND NOT EXISTS (SELECT 1 FROM dbo.ProdutoImagens I WHERE I.ProdutoId = P.Id));

-- Pedidos
INSERT @R SELECT N'Subtotal do pedido = soma dos itens (preço congelado × quantidade)',
    (SELECT COUNT(1) FROM dbo.Pedidos PE
     WHERE PE.Subtotal <> (SELECT SUM(I.Quantidade * I.PrecoUnitario) FROM dbo.ItensPedido I WHERE I.PedidoId = PE.Id));
INSERT @R SELECT N'Total = subtotal − desconto + frete',
    (SELECT COUNT(1) FROM dbo.Pedidos WHERE ValorTotal <> Subtotal - Desconto + Frete);
INSERT @R SELECT N'Frete segue fn_CalcularFrete (grátis a partir de R$ 299)',
    (SELECT COUNT(1) FROM dbo.Pedidos WHERE Frete <> dbo.fn_CalcularFrete(Subtotal - Desconto));
INSERT @R SELECT N'Joga Junto = 1% dos produtos com desconto (fn_CalcularJogaJunto)',
    (SELECT COUNT(1) FROM dbo.Pedidos WHERE ValorJogaJunto <> dbo.fn_CalcularJogaJunto(Subtotal - Desconto));
INSERT @R SELECT N'Todo pedido tem itens', (SELECT COUNT(1) FROM dbo.Pedidos PE WHERE NOT EXISTS (SELECT 1 FROM dbo.ItensPedido I WHERE I.PedidoId = PE.Id));
INSERT @R SELECT N'Todo pedido tem linha do tempo (trigger de histórico)',
    (SELECT COUNT(1) FROM dbo.Pedidos PE WHERE NOT EXISTS (SELECT 1 FROM dbo.HistoricoStatusPedido H WHERE H.PedidoId = PE.Id));
INSERT @R SELECT N'Status atual do pedido = último status do histórico',
    (SELECT COUNT(1) FROM dbo.Pedidos PE
     CROSS APPLY (SELECT TOP 1 StatusNovo FROM dbo.HistoricoStatusPedido H WHERE H.PedidoId = PE.Id ORDER BY H.Id DESC) U
     WHERE U.StatusNovo <> PE.StatusPedido);
INSERT @R SELECT N'Pedido cancelado devolveu o estoque (auditoria com entrada de cancelamento)',
    (SELECT COUNT(1) FROM dbo.Pedidos PE
     WHERE PE.StatusPedido = 'Cancelado'
       AND (SELECT COALESCE(SUM(A.QtdNova - A.QtdAnterior), 0) FROM dbo.AuditoriaEstoque A
            WHERE A.OrigemOperacao LIKE CONCAT(N'%#', PE.Id) AND A.QtdNova > A.QtdAnterior)
         < (SELECT SUM(I.Quantidade) FROM dbo.ItensPedido I WHERE I.PedidoId = PE.Id));
INSERT @R SELECT N'Toda venda baixou o estoque (auditoria de saída por pedido)',
    (SELECT COUNT(1) FROM dbo.Pedidos PE
     WHERE (SELECT COALESCE(SUM(A.QtdAnterior - A.QtdNova), 0) FROM dbo.AuditoriaEstoque A
            WHERE A.OrigemOperacao LIKE CONCAT(N'%#', PE.Id) AND A.QtdNova < A.QtdAnterior)
         < (SELECT SUM(I.Quantidade) FROM dbo.ItensPedido I WHERE I.PedidoId = PE.Id));

-- Avaliações e moderação
INSERT @R SELECT N'Avaliação só de quem comprou o produto na loja',
    (SELECT COUNT(1) FROM dbo.Avaliacoes A
     WHERE NOT EXISTS (SELECT 1 FROM dbo.ItensPedido I JOIN dbo.Pedidos P ON P.Id = I.PedidoId
                       WHERE I.ProdutoId = A.ProdutoId AND P.UsuarioId = A.UsuarioId));
INSERT @R SELECT N'Avaliação oculta tem moderador, data e motivo',
    (SELECT COUNT(1) FROM dbo.Avaliacoes WHERE Status = 'Oculta' AND (ModeradoPor IS NULL OR ModeradoEm IS NULL OR MotivoModeracao IS NULL));

-- Dados pessoais e segurança
INSERT @R SELECT N'Endereços cifrados (AES-256-GCM, prefixo enc1:) ou anonimizados',
    (SELECT COUNT(1) FROM dbo.Enderecos WHERE Rua NOT LIKE 'enc1:%' AND Rua <> 'Removido (LGPD)');
INSERT @R SELECT N'Telefones cifrados', (SELECT COUNT(1) FROM dbo.Usuarios WHERE Telefone IS NOT NULL AND Telefone NOT LIKE 'enc1:%');
INSERT @R SELECT N'Senhas só em hash BCrypt', (SELECT COUNT(1) FROM dbo.Usuarios WHERE SenhaHash NOT LIKE '$2%' AND Ativo = 1);
INSERT @R SELECT N'Conta excluída (LGPD) sem nome, e-mail real ou endereço',
    (SELECT COUNT(1) FROM dbo.Usuarios U WHERE U.Email LIKE 'removido-%@anonimo.invalid'
       AND (U.Ativo = 1 OR EXISTS (SELECT 1 FROM dbo.Enderecos E WHERE E.UsuarioId = U.Id AND E.Rua <> 'Removido (LGPD)')));
INSERT @R SELECT N'E-mail e IP com mascaramento dinâmico',
    3 - (SELECT COUNT(1) FROM sys.masked_columns
         WHERE (object_id = OBJECT_ID('dbo.Usuarios') AND name = 'Email')
            OR (object_id = OBJECT_ID('dbo.LogAcessos') AND name IN ('Email', 'Ip')));
INSERT @R SELECT N'Log de acessos sem registros com mais de 180 dias',
    (SELECT COUNT(1) FROM dbo.LogAcessos WHERE Data < DATEADD(DAY, -181, SYSDATETIME()));
INSERT @R SELECT N'Contas de demonstração ausentes (rode só em PRODUÇÃO; em Development elas existem)',
    (SELECT COUNT(1) FROM dbo.Usuarios WHERE Email IN ('admin@jogabonito.com', 'matheus@estudante.com', 'professor@unip.br'));

SELECT Ordem AS [#], Regra, CASE WHEN Problemas = 0 THEN 'OK' ELSE 'FALHA' END AS Resultado, Problemas
FROM @R ORDER BY Ordem;

-- Em scripts (sqlcmd -b, pipeline): termina com erro se alguma regra falhou.
-- @IgnorarDemo = 1 em Development, onde as contas de demonstração existem de propósito.
DECLARE @IgnorarDemo BIT = 1;
IF EXISTS (SELECT 1 FROM @R WHERE Problemas > 0 AND (@IgnorarDemo = 0 OR Regra NOT LIKE N'Contas de demonstração%'))
    RAISERROR(N'Conferência do banco: há regras com FALHA (veja a tabela acima).', 16, 1);

-- Resumo do Joga Junto (para o relatório social)
SELECT FORMAT(DataPedido, 'yyyy-MM') AS Mes, COUNT(1) AS Pedidos, SUM(ValorJogaJunto) AS JogaJunto
FROM dbo.Pedidos WHERE StatusPedido <> 'Cancelado'
GROUP BY FORMAT(DataPedido, 'yyyy-MM') ORDER BY Mes DESC;
