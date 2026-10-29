using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Domain.Excecoes;
using JogaBonito.Api.Infrastructure.Dados;
using JogaBonito.Api.Infrastructure.Seguranca;
using Microsoft.Data.SqlClient;
using static JogaBonito.Api.Infrastructure.Dados.SqlUtil;

namespace JogaBonito.Api.Infrastructure.Repositorios;

/// <summary>Estoque por tamanho (procedures sp_RelatorioEstoqueGeral e sp_AtualizarEstoque).</summary>
public class EstoqueRepositorio : IEstoqueRepositorio
{
    private readonly IConexaoFactory _conexoes;

    public EstoqueRepositorio(IConexaoFactory conexoes) => _conexoes = conexoes;

    public async Task<IReadOnlyList<EstoqueLinhaResponse>> RelatorioAsync()
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("dbo.sp_RelatorioEstoqueGeral", con)
        {
            CommandType = System.Data.CommandType.StoredProcedure
        };
        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<EstoqueLinhaResponse>();
        while (await r.ReadAsync())
            lista.Add(new EstoqueLinhaResponse(r.Int("ProdutoId"), r.Str("Nome"), r.Str("Linha"), r.Str("Categoria"),
                r.Str("Tamanho"), r.Int("Quantidade"), r.Str("StatusNivel"), r.Data("UltimaAtualizacao")));
        return lista;
    }

    public async Task AtualizarAsync(int produtoId, string tamanho, int quantidade, string origem)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("dbo.sp_AtualizarEstoque", con)
        {
            CommandType = System.Data.CommandType.StoredProcedure
        };
        cmd.Parameters.Add(Param("@ProdutoId", produtoId));
        cmd.Parameters.Add(Param("@Tamanho", tamanho));
        cmd.Parameters.Add(Param("@NovaQuantidade", quantidade));
        cmd.Parameters.Add(Param("@Origem", origem));
        await TraduzirErrosAsync(() => cmd.ExecuteNonQueryAsync());
    }

    public async Task<IReadOnlyList<AuditoriaResponse>> AuditoriaAsync(int limite)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(@"
            SELECT TOP (@Limite) A.Id, A.ProdutoId, ISNULL(P.Nome, '(removido)') AS Produto, A.Tamanho,
                   A.QtdAnterior, A.QtdNova, A.OrigemOperacao, A.DataOperacao
            FROM dbo.AuditoriaEstoque A LEFT JOIN dbo.Produtos P ON P.Id = A.ProdutoId
            ORDER BY A.Id DESC", con);
        cmd.Parameters.Add(Param("@Limite", limite));
        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<AuditoriaResponse>();
        while (await r.ReadAsync())
            lista.Add(new AuditoriaResponse(r.Int("Id"), r.Int("ProdutoId"), r.Str("Produto"), r.Str("Tamanho"),
                r.Int("QtdAnterior"), r.Int("QtdNova"), r.Str("OrigemOperacao"), r.Data("DataOperacao")));
        return lista;
    }
}

/// <summary>Indicadores do dashboard e consultas somente-leitura pré-definidas.</summary>
public class RelatorioRepositorio : IRelatorioRepositorio
{
    private readonly IConexaoFactory _conexoes;

    /// <summary>
    /// Console do banco SEGURO: o painel escolhe uma consulta pelo nome e a API
    /// executa somente SQL fixo daqui. Nenhum texto do usuário é executado no banco.
    /// </summary>
    private static readonly Dictionary<string, (string Descricao, string Sql)> Consultas = new()
    {
        ["tabelas"] = ("Quantidade de registros em cada tabela", @"
            SELECT t.name AS Tabela, SUM(p.rows) AS Registros
            FROM sys.tables t INNER JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
            GROUP BY t.name ORDER BY t.name"),
        ["objetos"] = ("Procedures, triggers, views e funções do banco", @"
            SELECT name AS Objeto, type_desc AS Tipo, CONVERT(VARCHAR(19), modify_date, 120) AS Alterado
            FROM sys.objects WHERE type IN ('P', 'TR', 'V', 'FN') ORDER BY type_desc, name"),
        ["catalogo"] = ("View vw_CatalogoProdutos", @"
            SELECT Id, Nome, Categoria, Linha, Equipe, Ano, Marca, Solado, Preco, PrecoFinal, EstoqueTotal, NotaMedia, TotalAvaliacoes
            FROM dbo.vw_CatalogoProdutos ORDER BY Id"),
        ["pedidos"] = ("View vw_PedidosDetalhados", @"
            SELECT TOP 100 PedidoId, CONVERT(VARCHAR(16), DataPedido, 120) AS Data, Cliente, TotalPecas,
                   Subtotal, Desconto, Frete, ValorTotal, StatusPedido, FormaPagamento, Origem, CodigoRastreio
            FROM dbo.vw_PedidosDetalhados ORDER BY PedidoId DESC"),
        ["mais-vendidos"] = ("View vw_ProdutosMaisVendidos", @"
            SELECT TOP 20 ProdutoId, Nome, Categoria, Linha, UnidadesVendidas, Receita
            FROM dbo.vw_ProdutosMaisVendidos ORDER BY UnidadesVendidas DESC, Receita DESC"),
        ["auditoria-estoque"] = ("Tabela AuditoriaEstoque (alimentada por trigger)", @"
            SELECT TOP 100 A.Id, P.Nome AS Produto, A.Tamanho, A.QtdAnterior, A.QtdNova, A.OrigemOperacao,
                   CONVERT(VARCHAR(19), A.DataOperacao, 120) AS Data
            FROM dbo.AuditoriaEstoque A LEFT JOIN dbo.Produtos P ON P.Id = A.ProdutoId ORDER BY A.Id DESC"),
        ["historico-status"] = ("Tabela HistoricoStatusPedido (alimentada por trigger)", @"
            SELECT TOP 100 Id, PedidoId, StatusAnterior, StatusNovo, CONVERT(VARCHAR(19), DataAlteracao, 120) AS Data
            FROM dbo.HistoricoStatusPedido ORDER BY Id DESC"),
        ["cupons"] = ("Tabela Cupons", @"
            SELECT Codigo, PercentualDesconto, ValorMinimo, ValidoAte, Ativo,
                   (SELECT COUNT(1) FROM dbo.Pedidos P WHERE P.CupomId = C.Id) AS VezesUsado
            FROM dbo.Cupons C ORDER BY Codigo"),
        ["clientes"] = ("Clientes cadastrados (e-mail mascarado)", @"
            SELECT U.Id, U.Nome, U.Email, U.Role, CONVERT(VARCHAR(10), U.CriadoEm, 120) AS Cadastro,
                   (SELECT COUNT(1) FROM dbo.Pedidos P WHERE P.UsuarioId = U.Id) AS Pedidos,
                   CASE WHEN U.BloqueadoAte > SYSDATETIME() THEN 'Sim' ELSE 'Não' END AS Bloqueado
            FROM dbo.Usuarios U ORDER BY U.Id"),
        ["joga-junto"] = ("Contribuição Joga Junto por mês (fn_CalcularJogaJunto)", @"
            SELECT FORMAT(DataPedido, 'yyyy-MM') AS Mes, COUNT(1) AS Pedidos, SUM(ValorJogaJunto) AS Contribuicao
            FROM dbo.Pedidos WHERE StatusPedido <> 'Cancelado'
            GROUP BY FORMAT(DataPedido, 'yyyy-MM') ORDER BY Mes DESC"),
        ["moderacao"] = ("Avaliações moderadas (sp_ModerarAvaliacao)", @"
            SELECT TOP 100 A.Id, P.Nome AS Produto, A.Nota, A.Status, A.MotivoModeracao,
                   M.Email AS Moderador, CONVERT(VARCHAR(19), A.ModeradoEm, 120) AS ModeradoEm
            FROM dbo.Avaliacoes A INNER JOIN dbo.Produtos P ON P.Id = A.ProdutoId
            LEFT JOIN dbo.Usuarios M ON M.Id = A.ModeradoPor
            WHERE A.ModeradoEm IS NOT NULL ORDER BY A.ModeradoEm DESC"),
        ["acessos"] = ("Tabela LogAcessos (e-mail e IP mascarados)", @"
            SELECT TOP 100 Id, Email, Ip, CASE WHEN Sucesso = 1 THEN 'Sucesso' ELSE 'Falha' END AS Resultado,
                   Detalhe, CONVERT(VARCHAR(19), Data, 120) AS Data
            FROM dbo.LogAcessos ORDER BY Id DESC")
    };

    public RelatorioRepositorio(IConexaoFactory conexoes) => _conexoes = conexoes;

    public IReadOnlyList<ConsultaDisponivelResponse> ConsultasDisponiveis() =>
        Consultas.Select(c => new ConsultaDisponivelResponse(c.Key, c.Value.Descricao)).ToList();

    public async Task<ConsultaResponse> ExecutarConsultaAsync(string nome)
    {
        if (!Consultas.TryGetValue(nome, out var consulta))
            throw new RecursoNaoEncontradoException("Consulta não encontrada.");

        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(consulta.Sql, con);
        await using var r = await cmd.ExecuteReaderAsync();
        var colunas = Enumerable.Range(0, r.FieldCount).Select(r.GetName).ToList();
        var linhas = new List<Dictionary<string, object?>>();
        while (await r.ReadAsync())
        {
            var linha = new Dictionary<string, object?>();
            for (var i = 0; i < r.FieldCount; i++)
                linha[colunas[i]] = r.IsDBNull(i) ? null : Mascarar(colunas[i], r.GetValue(i));
            linhas.Add(linha);
        }
        return new ConsultaResponse(nome, consulta.Descricao, colunas, linhas);
    }

    /// <summary>O console mostra o necessário para operar a loja: e-mails e IPs saem mascarados.</summary>
    private static object Mascarar(string coluna, object valor) => coluna switch
    {
        "Email" or "Moderador" => Mascara.Email(valor.ToString()),
        "Ip" => Mascara.Ip(valor.ToString()) ?? "",
        _ => valor
    };

    public async Task<IReadOnlyList<AcessoResponse>> AcessosAsync(int limite)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(@"
            SELECT TOP (@Limite) Id, Email, Ip, Sucesso, Detalhe, Data
            FROM dbo.LogAcessos ORDER BY Id DESC", con);
        cmd.Parameters.Add(Param("@Limite", limite));
        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<AcessoResponse>();
        while (await r.ReadAsync())
            lista.Add(new AcessoResponse(Convert.ToInt64(r["Id"]), Mascara.Email(r.Str("Email")), Mascara.Ip(r.StringOuNull("Ip")),
                r.Bool("Sucesso"), r.StringOuNull("Detalhe"), r.Data("Data")));
        return lista;
    }

    public async Task<DashboardResponse> DashboardAsync()
    {
        await using var con = await _conexoes.AbrirAsync();

        int totalProdutos, pecas, clientes, pedidos, esgotados, baixos, pendentes, avaliacoesPendentes;
        decimal faturamento, jogaJunto;
        await using (var cmd = new SqlCommand(@"
            SELECT
              (SELECT COUNT(1) FROM dbo.Produtos WHERE Ativo = 1) AS TotalProdutos,
              (SELECT ISNULL(SUM(E.Quantidade), 0) FROM dbo.Estoque E INNER JOIN dbo.Produtos P ON P.Id = E.ProdutoId AND P.Ativo = 1) AS Pecas,
              (SELECT COUNT(1) FROM dbo.Usuarios WHERE Role = 'Cliente') AS Clientes,
              (SELECT COUNT(1) FROM dbo.Pedidos) AS Pedidos,
              (SELECT ISNULL(SUM(ValorTotal), 0) FROM dbo.Pedidos WHERE StatusPedido <> 'Cancelado') AS Faturamento,
              (SELECT COUNT(1) FROM dbo.Estoque E INNER JOIN dbo.Produtos P ON P.Id = E.ProdutoId AND P.Ativo = 1 WHERE E.Quantidade = 0) AS Esgotados,
              (SELECT COUNT(1) FROM dbo.Estoque E INNER JOIN dbo.Produtos P ON P.Id = E.ProdutoId AND P.Ativo = 1 WHERE E.Quantidade BETWEEN 1 AND 4) AS Baixos,
              (SELECT COUNT(1) FROM dbo.Pedidos WHERE StatusPedido IN ('Pago', 'Em Separação')) AS Pendentes,
              (SELECT ISNULL(SUM(ValorJogaJunto), 0) FROM dbo.Pedidos WHERE StatusPedido <> 'Cancelado') AS JogaJunto,
              (SELECT COUNT(1) FROM dbo.Avaliacoes WHERE Status = 'Pendente') AS AvaliacoesPendentes", con))
        {
            await using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            totalProdutos = r.Int("TotalProdutos"); pecas = r.Int("Pecas"); clientes = r.Int("Clientes");
            pedidos = r.Int("Pedidos"); faturamento = r.Dec("Faturamento"); esgotados = r.Int("Esgotados");
            baixos = r.Int("Baixos"); pendentes = r.Int("Pendentes");
            jogaJunto = r.Dec("JogaJunto"); avaliacoesPendentes = r.Int("AvaliacoesPendentes");
        }

        decimal fat30 = 0, ticket30 = 0;
        var porCategoria = new List<VendaCategoriaResponse>();
        await using (var cmd = new SqlCommand("dbo.sp_RelatorioVendas", con) { CommandType = System.Data.CommandType.StoredProcedure })
        {
            await using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync()) { fat30 = r.Dec("Faturamento"); ticket30 = r.Dec("TicketMedio"); }
            await r.NextResultAsync();
            while (await r.ReadAsync())
                porCategoria.Add(new VendaCategoriaResponse(r.Str("Categoria"), r.Int("Unidades"), r.Dec("Receita")));
        }

        var maisVendidos = new List<MaisVendidoResponse>();
        await using (var cmd = new SqlCommand(@"
            SELECT TOP 5 ProdutoId, Nome, Categoria, UnidadesVendidas, Receita
            FROM dbo.vw_ProdutosMaisVendidos ORDER BY UnidadesVendidas DESC, Receita DESC", con))
        {
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                maisVendidos.Add(new MaisVendidoResponse(r.Int("ProdutoId"), r.Str("Nome"), r.Str("Categoria"),
                    r.Int("UnidadesVendidas"), r.Dec("Receita")));
        }

        return new DashboardResponse(totalProdutos, pecas, clientes, pedidos, faturamento, fat30, ticket30,
            esgotados, baixos, pendentes, porCategoria, maisVendidos, jogaJunto, avaliacoesPendentes);
    }
}
