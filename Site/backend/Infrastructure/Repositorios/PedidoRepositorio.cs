using System.Text.Json;
using System.Text.RegularExpressions;
using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Domain.Entidades;
using JogaBonito.Api.Infrastructure.Dados;
using JogaBonito.Api.Infrastructure.Seguranca;
using Microsoft.Data.SqlClient;
using static JogaBonito.Api.Infrastructure.Dados.SqlUtil;

namespace JogaBonito.Api.Infrastructure.Repositorios;

/// <summary>Pedidos, itens, histórico de status, endereços e cupons.</summary>
public class PedidoRepositorio : IPedidoRepositorio
{
    private readonly IConexaoFactory _conexoes;
    private readonly ProtetorDados _protetor;

    public PedidoRepositorio(IConexaoFactory conexoes, ProtetorDados protetor)
    {
        _conexoes = conexoes;
        _protetor = protetor;
    }

    public async Task<Cupom?> ObterCupomAsync(string codigo)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(@"
            SELECT Id, Codigo, PercentualDesconto, ValorMinimo, ValidoAte, Ativo
            FROM dbo.Cupons WHERE Codigo = @Codigo", con);
        cmd.Parameters.Add(Param("@Codigo", (codigo ?? string.Empty).Trim().ToUpperInvariant()));
        await using var r = await cmd.ExecuteReaderAsync();
        if (!await r.ReadAsync()) return null;
        var validoAte = r["ValidoAte"] is DBNull ? (DateTime?)null : r.Data("ValidoAte");
        return new Cupom
        {
            Id = r.Int("Id"), Codigo = r.Str("Codigo"), Percentual = r.Dec("PercentualDesconto"),
            ValorMinimo = r.Dec("ValorMinimo"), ValidoAte = validoAte, Ativo = r.Bool("Ativo")
        };
    }

    public async Task<int> InserirEnderecoAsync(int usuarioId, EnderecoRequest e)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(@"
            INSERT INTO dbo.Enderecos (UsuarioId, Cep, Rua, Numero, Complemento, Bairro, Cidade, Estado)
            OUTPUT INSERTED.Id
            VALUES (@UsuarioId, @Cep, @Rua, @Numero, @Complemento, @Bairro, @Cidade, @Estado);", con);
        cmd.Parameters.Add(Param("@UsuarioId", usuarioId));
        // Endereço é dado pessoal: CEP, rua, número, complemento e bairro vão cifrados (AES-256-GCM).
        // Cidade e estado ficam abertos para os relatórios de vendas por região.
        cmd.Parameters.Add(Param("@Cep", _protetor.Proteger(Regex.Replace(e.Cep, @"\D", ""))));
        cmd.Parameters.Add(Param("@Rua", _protetor.Proteger(Limitar(e.Rua, 150))));
        cmd.Parameters.Add(Param("@Numero", _protetor.Proteger(Limitar(e.Numero, 20))));
        cmd.Parameters.Add(Param("@Complemento", string.IsNullOrWhiteSpace(e.Complemento) ? null : _protetor.Proteger(Limitar(e.Complemento, 60))));
        cmd.Parameters.Add(Param("@Bairro", _protetor.Proteger(Limitar(e.Bairro, 100))));
        cmd.Parameters.Add(Param("@Cidade", Limitar(e.Cidade, 100)));
        cmd.Parameters.Add(Param("@Estado", e.Estado.Trim().ToUpperInvariant()));
        return Convert.ToInt32(await TraduzirErrosAsync(() => cmd.ExecuteScalarAsync()));
    }

    public async Task<PedidoCriadoResponse> RegistrarAsync(int usuarioId, CriarPedidoRequest pedido, int? enderecoId)
    {
        var itensJson = JsonSerializer.Serialize(pedido.Itens.Select(i => new
        {
            produtoId = i.ProdutoId,
            tamanho = i.Tamanho.Trim().ToUpperInvariant(),
            quantidade = i.Quantidade
        }));

        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("dbo.sp_RegistrarPedido", con)
        {
            CommandType = System.Data.CommandType.StoredProcedure
        };
        cmd.Parameters.Add(Param("@UsuarioId", usuarioId));
        cmd.Parameters.Add(Param("@ItensJson", itensJson));
        cmd.Parameters.Add(Param("@FormaPagamento", pedido.FormaPagamento));
        cmd.Parameters.Add(Param("@Parcelas", pedido.Parcelas));
        cmd.Parameters.Add(Param("@CodigoCupom", string.IsNullOrWhiteSpace(pedido.Cupom) ? null : pedido.Cupom));
        cmd.Parameters.Add(Param("@EnderecoId", enderecoId));
        cmd.Parameters.Add(Param("@Origem", pedido.Origem ?? "Web"));
        cmd.Parameters.Add(new SqlParameter("@PedidoId", System.Data.SqlDbType.Int)
        {
            Direction = System.Data.ParameterDirection.Output
        });

        return await TraduzirErrosAsync(async () =>
        {
            await using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) throw new InvalidOperationException("A procedure não retornou o pedido.");
            return new PedidoCriadoResponse(r.Int("Id"), r.Str("CodigoRastreio"), r.Dec("Subtotal"),
                r.Dec("Desconto"), r.Dec("Frete"), r.Dec("ValorTotal"), r.Str("StatusPedido"), r.Dec("ValorJogaJunto"));
        });
    }

    public Task<IReadOnlyList<PedidoResponse>> ListarPorUsuarioAsync(int usuarioId) =>
        CarregarAsync("WHERE P.UsuarioId = @Filtro", usuarioId, 100);

    public Task<IReadOnlyList<PedidoResponse>> ListarTodosAsync(string? status, int limite) =>
        status is null ? CarregarAsync("", null, limite) : CarregarAsync("WHERE P.StatusPedido = @Filtro", status, limite);

    public async Task<PedidoResponse?> ObterAsync(int pedidoId) =>
        (await CarregarAsync("WHERE P.Id = @Filtro", pedidoId, 1)).FirstOrDefault();

    public async Task<int?> ObterDonoAsync(int pedidoId)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("SELECT UsuarioId FROM dbo.Pedidos WHERE Id = @Id", con);
        cmd.Parameters.Add(Param("@Id", pedidoId));
        var resultado = await cmd.ExecuteScalarAsync();
        return resultado is null or DBNull ? null : Convert.ToInt32(resultado);
    }

    public async Task AtualizarStatusAsync(int pedidoId, string novoStatus)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("dbo.sp_AtualizarStatusPedido", con)
        {
            CommandType = System.Data.CommandType.StoredProcedure
        };
        cmd.Parameters.Add(Param("@PedidoId", pedidoId));
        cmd.Parameters.Add(Param("@NovoStatus", novoStatus));
        await TraduzirErrosAsync(() => cmd.ExecuteNonQueryAsync());
    }

    // ------------------------------------------------------------------
    // Carrega cabeçalhos + itens + histórico em 3 consultas (evita N+1)
    // ------------------------------------------------------------------
    private async Task<IReadOnlyList<PedidoResponse>> CarregarAsync(string filtro, object? valor, int limite)
    {
        await using var con = await _conexoes.AbrirAsync();

        var cabecalhos = new List<(int Id, DateTime Data, string Status, string Forma, int Parcelas, string? Rastreio,
            string Origem, decimal Sub, decimal Desc, decimal Frete, decimal Total, string Cliente, decimal JogaJunto)>();

        await using (var cmd = new SqlCommand($@"
            SELECT TOP (@Limite) P.Id, P.DataPedido, P.StatusPedido, P.FormaPagamento, P.Parcelas, P.CodigoRastreio,
                   P.Origem, P.Subtotal, P.Desconto, P.Frete, P.ValorTotal, P.ValorJogaJunto, U.Nome AS Cliente
            FROM dbo.Pedidos P
            INNER JOIN dbo.Usuarios U ON U.Id = P.UsuarioId
            {filtro}
            ORDER BY P.Id DESC", con))
        {
            cmd.Parameters.Add(Param("@Limite", limite));
            if (valor is not null) cmd.Parameters.Add(Param("@Filtro", valor));
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                cabecalhos.Add((r.Int("Id"), r.Data("DataPedido"), r.Str("StatusPedido"), r.Str("FormaPagamento"),
                    r.Int("Parcelas"), r.StringOuNull("CodigoRastreio"), r.Str("Origem"), r.Dec("Subtotal"),
                    r.Dec("Desconto"), r.Dec("Frete"), r.Dec("ValorTotal"), r.Str("Cliente"), r.Dec("ValorJogaJunto")));
        }

        if (cabecalhos.Count == 0) return Array.Empty<PedidoResponse>();

        // Lista de ids vem do próprio banco (inteiros), segura para compor a cláusula IN
        var ids = string.Join(",", cabecalhos.Select(c => c.Id));
        var itens = new Dictionary<int, List<ItemPedidoResponse>>();
        var historico = new Dictionary<int, List<HistoricoStatusResponse>>();

        await using (var cmd = new SqlCommand($@"
            SELECT I.PedidoId, I.ProdutoId, P.Nome, P.Imagem, I.Tamanho, I.Quantidade, I.PrecoUnitario
            FROM dbo.ItensPedido I INNER JOIN dbo.Produtos P ON P.Id = I.ProdutoId
            WHERE I.PedidoId IN ({ids}) ORDER BY I.Id", con))
        {
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var pedidoId = r.Int("PedidoId");
                if (!itens.TryGetValue(pedidoId, out var lista)) itens[pedidoId] = lista = new();
                var qtd = r.Int("Quantidade");
                var preco = r.Dec("PrecoUnitario");
                lista.Add(new ItemPedidoResponse(r.Int("ProdutoId"), r.Str("Nome"), r.Str("Imagem"),
                    r.Str("Tamanho"), qtd, preco, qtd * preco));
            }
        }

        await using (var cmd = new SqlCommand($@"
            SELECT PedidoId, StatusNovo, DataAlteracao FROM dbo.HistoricoStatusPedido
            WHERE PedidoId IN ({ids}) ORDER BY DataAlteracao, Id", con))
        {
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var pedidoId = r.Int("PedidoId");
                if (!historico.TryGetValue(pedidoId, out var lista)) historico[pedidoId] = lista = new();
                lista.Add(new HistoricoStatusResponse(r.Str("StatusNovo"), r.Data("DataAlteracao")));
            }
        }

        return cabecalhos.Select(c => new PedidoResponse(
            c.Id, c.Data, c.Status, c.Forma, c.Parcelas, c.Rastreio, c.Origem, c.Sub, c.Desc, c.Frete, c.Total,
            c.Cliente,
            itens.GetValueOrDefault(c.Id) ?? new List<ItemPedidoResponse>(),
            historico.GetValueOrDefault(c.Id) ?? new List<HistoricoStatusResponse>(), c.JogaJunto)).ToList();
    }

    private static string Limitar(string? texto, int max)
    {
        var t = (texto ?? string.Empty).Trim();
        return t.Length > max ? t[..max] : t;
    }
}
