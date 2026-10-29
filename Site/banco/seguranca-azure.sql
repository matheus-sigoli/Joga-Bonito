-- ============================================================================
-- JOGA BONITO — USUÁRIO DA APLICAÇÃO NO AZURE SQL DATABASE (privilégio mínimo)
-- PIM IV · UNIP 2026/2
-- ----------------------------------------------------------------------------
-- Versão de seguranca.sql para o Azure SQL Database, que não tem USE nem
-- logins de servidor para a aplicação: o usuário é CONTIDO no próprio banco.
-- Executado pelo pipeline (job deploy) conectado ao banco JogaBonitoDB com a
-- conta administradora, passando a senha como variável:
--   sqlcmd -S <servidor>.database.windows.net -d JogaBonitoDB -U <admin> -N \
--          -i seguranca-azure.sql -v SENHA_APP="<senha do Key Vault>"
-- A connection string da aplicação (guardada no Key Vault) usa User Id=jogabonito_app.
-- ============================================================================
:on error exit

IF LEN(N'$(SENHA_APP)') < 12
    THROW 50000, 'Informe SENHA_APP com pelo menos 12 caracteres (sqlcmd -v SENHA_APP=...).', 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'jogabonito_app')
    CREATE USER jogabonito_app WITH PASSWORD = N'$(SENHA_APP)';
ELSE
    ALTER USER jogabonito_app WITH PASSWORD = N'$(SENHA_APP)';  -- rodar de novo troca a senha
GO

-- Papel próprio da aplicação: as permissões ficam no papel, não no usuário
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'papel_loja' AND type = 'R')
    CREATE ROLE papel_loja;
GO

GRANT SELECT  ON SCHEMA::dbo TO papel_loja;     -- leitura de tabelas e views
GRANT EXECUTE ON SCHEMA::dbo TO papel_loja;     -- procedures e função de frete

GRANT INSERT, UPDATE ON dbo.Usuarios       TO papel_loja;
GRANT INSERT, UPDATE ON dbo.Enderecos      TO papel_loja;
GRANT INSERT, UPDATE ON dbo.Produtos       TO papel_loja;  -- painel admin (exclusão é lógica: Ativo = 0)
GRANT INSERT, UPDATE, DELETE ON dbo.ProdutoImagens TO papel_loja;
GRANT INSERT, UPDATE ON dbo.Estoque        TO papel_loja;

-- Registros de auditoria nunca podem ser apagados ou alterados pela aplicação
-- E-mail e IP têm mascaramento dinâmico; a API precisa do valor real (login, LGPD).
-- Nenhum outro usuário do banco recebe UNMASK.
GRANT UNMASK TO papel_loja;

DENY UPDATE, DELETE ON dbo.AuditoriaEstoque      TO papel_loja;
DENY UPDATE, DELETE ON dbo.HistoricoStatusPedido TO papel_loja;
DENY UPDATE, DELETE ON dbo.LogAcessos            TO papel_loja;
DENY DELETE         ON dbo.Pedidos               TO papel_loja;
DENY DELETE         ON dbo.ItensPedido           TO papel_loja;
GO

ALTER ROLE papel_loja ADD MEMBER jogabonito_app;
GO

-- Conferência: permissões efetivas do usuário da aplicação
EXECUTE AS USER = 'jogabonito_app';
SELECT entity_name = 'dbo', permission_name FROM fn_my_permissions('dbo', 'SCHEMA');
REVERT;
GO
