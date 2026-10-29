-- ============================================================================
-- JOGA BONITO — USUÁRIO DE APLICAÇÃO COM PRIVILÉGIO MÍNIMO (SQL SERVER)
-- PIM IV · UNIP 2026/2
-- ----------------------------------------------------------------------------
-- Execute UMA vez, como administrador (sa ou equivalente), DEPOIS que a API
-- criou o banco. Em produção a API deve conectar com este usuário, nunca com
-- sa nem com uma conta db_owner:
--
--   ConnectionStrings__DefaultConnection =
--     Server=...;Database=JogaBonitoDB;User Id=jogabonito_app;Password=<senha forte>;
--     Encrypt=True;TrustServerCertificate=False;
--   Banco__CriarAutomaticamente = false
--
-- O que o usuário pode fazer:
--   * LER tabelas e views (catálogo, pedidos, relatórios);
--   * EXECUTAR as stored procedures (pedido, estoque, status, avaliação, login);
--   * INSERIR/ATUALIZAR apenas o que a API grava diretamente (Usuarios,
--     Enderecos, Produtos, ProdutoImagens, Estoque).
-- O que NÃO pode: DELETE em pedidos/itens/auditoria, ALTER, DROP, CREATE.
--
-- A senha NÃO fica neste arquivo: ela é passada como variável do sqlcmd.
--   Linha de comando / pipeline:
--     sqlcmd -S <servidor> -U <admin> -i seguranca.sql -v SENHA_APP="<senha forte>"
--   SSMS: menu Query › SQLCMD Mode e acrescente no topo, sem salvar o arquivo:
--     :setvar SENHA_APP "<senha forte>"
-- Sem a variável, o sqlcmd para antes de criar qualquer coisa.
-- ============================================================================
:on error exit

IF LEN(N'$(SENHA_APP)') < 12
    THROW 50000, 'Informe SENHA_APP com pelo menos 12 caracteres (sqlcmd -v SENHA_APP=...).', 1;
GO

USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'jogabonito_app')
    CREATE LOGIN jogabonito_app WITH PASSWORD = N'$(SENHA_APP)', CHECK_POLICY = ON;
ELSE
    ALTER LOGIN jogabonito_app WITH PASSWORD = N'$(SENHA_APP)';  -- rodar de novo troca a senha
GO

USE JogaBonitoDB;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'jogabonito_app')
    CREATE USER jogabonito_app FOR LOGIN jogabonito_app;
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
