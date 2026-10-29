using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace JogaBonito.Api.Infrastructure.Dados;

/// <summary>
/// /health/ready: a API só está "pronta" se
///   1. a preparação automática do banco não falhou (quando ligada);
///   2. o SQL Server aceita conexão;
///   3. o ESQUEMA está completo (tabelas, views, funções, procedures e triggers que a API usa);
///   4. o catálogo tem produtos ativos.
/// Assim um banco criado pela metade não aparece como saudável para o balanceador.
/// </summary>
public class SqlHealthCheck : IHealthCheck
{
    /// <summary>Objetos de que a API depende (nome, tipo em sys.objects).</summary>
    public static readonly (string Nome, string Tipo)[] ObjetosObrigatorios =
    {
        ("Usuarios", "U"), ("Categorias", "U"), ("Produtos", "U"), ("ProdutoImagens", "U"), ("Estoque", "U"),
        ("Enderecos", "U"), ("Cupons", "U"), ("Pedidos", "U"), ("ItensPedido", "U"), ("HistoricoStatusPedido", "U"),
        ("AuditoriaEstoque", "U"), ("Avaliacoes", "U"), ("LogAcessos", "U"),
        ("vw_CatalogoProdutos", "V"), ("vw_PedidosDetalhados", "V"), ("vw_ProdutosMaisVendidos", "V"),
        ("fn_CalcularFrete", "FN"), ("fn_CalcularJogaJunto", "FN"),
        ("sp_RegistrarPedido", "P"), ("sp_AtualizarStatusPedido", "P"), ("sp_AtualizarEstoque", "P"),
        ("sp_RelatorioEstoqueGeral", "P"), ("sp_RelatorioVendas", "P"), ("sp_RegistrarAvaliacao", "P"),
        ("sp_RegistrarTentativaLogin", "P"), ("sp_ModerarAvaliacao", "P"), ("sp_AnonimizarUsuario", "P"), ("sp_ExpurgarRegistrosAntigos", "P"),
        ("trg_AuditoriaEstoque", "TR"), ("trg_BaixaEstoqueAposPedido", "TR"), ("trg_HistoricoStatusPedido", "TR")
    };

    private readonly IConexaoFactory _conexoes;
    private readonly EstadoBanco _estado;

    public SqlHealthCheck(IConexaoFactory conexoes, EstadoBanco estado)
    {
        _conexoes = conexoes;
        _estado = estado;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        if (_estado.Executado && !_estado.Sucesso)
            return HealthCheckResult.Unhealthy($"Preparação do banco falhou: {_estado.Erro}");

        try
        {
            await using var con = await _conexoes.AbrirAsync();

            var nomes = string.Join(" UNION ALL ", ObjetosObrigatorios.Select((o, i) =>
                $"SELECT @n{i} AS Nome, @t{i} AS Tipo"));
            await using var cmd = new SqlCommand($@"
                SELECT O.Nome FROM ({nomes}) O
                WHERE NOT EXISTS (SELECT 1 FROM sys.objects S
                                  WHERE S.name = O.Nome AND S.type = O.Tipo AND S.schema_id = SCHEMA_ID('dbo'));
                SELECT CASE WHEN OBJECT_ID('dbo.Produtos', 'U') IS NULL THEN 0
                            ELSE (SELECT COUNT(1) FROM dbo.Produtos WHERE Ativo = 1) END;", con);
            for (var i = 0; i < ObjetosObrigatorios.Length; i++)
            {
                cmd.Parameters.AddWithValue($"@n{i}", ObjetosObrigatorios[i].Nome);
                cmd.Parameters.AddWithValue($"@t{i}", ObjetosObrigatorios[i].Tipo);
            }

            var faltando = new List<string>();
            int produtos;
            await using (var r = await cmd.ExecuteReaderAsync(cancellationToken))
            {
                while (await r.ReadAsync(cancellationToken)) faltando.Add(r.GetString(0));
                await r.NextResultAsync(cancellationToken);
                await r.ReadAsync(cancellationToken);
                produtos = r.GetInt32(0);
            }

            if (faltando.Count > 0)
                return HealthCheckResult.Unhealthy($"Esquema incompleto: faltam {string.Join(", ", faltando)}.");
            if (produtos == 0)
                return HealthCheckResult.Unhealthy("Esquema completo, mas o catálogo está vazio (rode seed.sql).");
            return HealthCheckResult.Healthy($"SQL Server acessível, esquema completo, {produtos} produtos ativos.");
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy("SQL Server indisponível.", ex);
        }
    }
}
