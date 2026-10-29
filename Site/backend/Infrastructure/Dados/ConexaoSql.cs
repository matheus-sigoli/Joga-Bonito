using System.Text.RegularExpressions;
using JogaBonito.Api.Domain.Excecoes;
using Microsoft.Data.SqlClient;

namespace JogaBonito.Api.Infrastructure.Dados;

/// <summary>Cria conexões abertas com o SQL Server a partir da connection string.</summary>
public interface IConexaoFactory
{
    Task<SqlConnection> AbrirAsync();
}

/// <summary>
/// Fábrica de conexões com três proteções para banco na nuvem (Azure SQL / container):
///   1. Pool de conexões configurado (reaproveita conexões abertas — padrão do ADO.NET);
///   2. Reconexão ociosa (ConnectRetryCount): se a conexão do pool caiu, o driver refaz sozinho;
///   3. Retentativa com espera exponencial (SqlClient Retry Logic) ao ABRIR a conexão quando o
///      SQL Server devolve um erro transitório (banco reiniciando, failover, limite de sessões).
/// Comandos não são repetidos automaticamente: um INSERT repetido poderia duplicar dados.
/// </summary>
public class SqlConexaoFactory : IConexaoFactory
{
    private readonly string _connectionString;
    private readonly SqlRetryLogicBaseProvider _retentativa;

    public SqlConexaoFactory(string connectionString, int tentativas = 4)
    {
        // Necessário em algumas versões do SqlClient para habilitar a Retry Logic
        AppContext.SetSwitch("Switch.Microsoft.Data.SqlClient.EnableRetryLogic", true);

        _connectionString = Ajustar(connectionString);
        _retentativa = SqlConfigurableRetryFactory.CreateExponentialRetryProvider(new SqlRetryLogicOption
        {
            NumberOfTries = Math.Max(1, tentativas),
            DeltaTime = TimeSpan.FromSeconds(1),        // 1s, 2s, 4s...
            MaxTimeInterval = TimeSpan.FromSeconds(15)
            // TransientErrors: usa a lista padrão do driver (4060, 40197, 40501, 40613, 49918...)
        });
    }

    /// <summary>Completa a connection string com valores seguros quando não foram informados.</summary>
    public static string Ajustar(string connectionString)
    {
        var b = new SqlConnectionStringBuilder(connectionString);
        var informado = connectionString.ToLowerInvariant();
        if (!informado.Contains("application name")) b.ApplicationName = "JogaBonito.Api";
        if (!informado.Contains("max pool size")) b.MaxPoolSize = 100;
        if (!informado.Contains("connect retry count") && !informado.Contains("connectretrycount")) b.ConnectRetryCount = 3;
        if (!informado.Contains("connect retry interval") && !informado.Contains("connectretryinterval")) b.ConnectRetryInterval = 5;
        if (!informado.Contains("timeout")) b.ConnectTimeout = 15;
        return b.ConnectionString;
    }

    public async Task<SqlConnection> AbrirAsync()
    {
        var conexao = new SqlConnection(_connectionString) { RetryLogicProvider = _retentativa };
        try
        {
            await conexao.OpenAsync();
            return conexao;
        }
        catch
        {
            await conexao.DisposeAsync();
            throw;
        }
    }
}

/// <summary>Utilitários de leitura e tradução de erros do SQL Server.</summary>
public static class SqlUtil
{
    /// <summary>Erros lançados com THROW 50000+ nas procedures/triggers são regras de negócio.</summary>
    public static async Task<T> TraduzirErrosAsync<T>(Func<Task<T>> acao)
    {
        try
        {
            return await acao();
        }
        catch (SqlException ex) when (ex.Number >= 50000)
        {
            throw new RegraNegocioException(ex.Message);
        }
        catch (SqlException ex) when (ex.Number is 2627 or 2601)
        {
            throw new RegraNegocioException("Registro duplicado.");
        }
        catch (SqlException ex) when (ex.Number == 547)
        {
            throw new RegraNegocioException("Operação viola uma regra de integridade do banco (valor fora do permitido ou registro relacionado).");
        }
    }

    public static async Task TraduzirErrosAsync(Func<Task> acao) =>
        await TraduzirErrosAsync(async () => { await acao(); return true; });

    public static string? StringOuNull(this SqlDataReader r, string coluna)
    {
        var i = r.GetOrdinal(coluna);
        return r.IsDBNull(i) ? null : r.GetString(i);
    }

    public static int? IntOuNull(this SqlDataReader r, string coluna)
    {
        var i = r.GetOrdinal(coluna);
        return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
    }

    public static decimal? DecimalOuNull(this SqlDataReader r, string coluna)
    {
        var i = r.GetOrdinal(coluna);
        return r.IsDBNull(i) ? null : r.GetDecimal(i);
    }

    public static int Int(this SqlDataReader r, string coluna) => Convert.ToInt32(r[coluna]);
    public static decimal Dec(this SqlDataReader r, string coluna) => Convert.ToDecimal(r[coluna]);
    public static string Str(this SqlDataReader r, string coluna) => Convert.ToString(r[coluna]) ?? string.Empty;
    public static bool Bool(this SqlDataReader r, string coluna) => Convert.ToBoolean(r[coluna]);
    public static DateTime Data(this SqlDataReader r, string coluna) => Convert.ToDateTime(r[coluna]);

    public static SqlParameter Param(string nome, object? valor) => new(nome, valor ?? DBNull.Value);
}

/// <summary>Resultado da preparação do banco, consultado pelo health check /health/ready.</summary>
public class EstadoBanco
{
    public bool Executado { get; private set; }
    public bool Sucesso { get; private set; } = true;
    public string? Erro { get; private set; }

    public void Registrar(bool sucesso, string? erro = null)
    {
        Executado = true;
        Sucesso = sucesso;
        Erro = erro;
    }
}

/// <summary>
/// Cria o banco JogaBonitoDB (se não existir) e executa os scripts em lotes separados por GO:
///   1. schema.sql — estrutura e migrações (essencial);
///   2. seed.sql   — categorias, 36 produtos, galeria, estoque e cupons (essencial, incremental);
///   3. demo.sql   — contas, pedidos e avaliações de demonstração (opcional, nunca em produção).
/// Se um lote ESSENCIAL falhar, a execução para ali, o erro é registrado em <see cref="EstadoBanco"/>
/// e /health/ready passa a responder "Unhealthy" — a API não finge que está pronta.
/// </summary>
public class InicializadorBanco
{
    private readonly string _connectionString;
    private readonly string _pastaScripts;
    private readonly bool _carregarDemonstracao;
    private readonly ILogger<InicializadorBanco> _log;

    public InicializadorBanco(string connectionString, string pastaScripts, bool carregarDemonstracao,
        ILogger<InicializadorBanco> log)
    {
        _connectionString = connectionString;
        _pastaScripts = pastaScripts;
        _carregarDemonstracao = carregarDemonstracao;
        _log = log;
    }

    public async Task ExecutarAsync(EstadoBanco estado)
    {
        try
        {
            await CriarBancoSeNecessarioAsync();
            await using var conexao = new SqlConnection(_connectionString);
            await conexao.OpenAsync();

            await ExecutarScriptAsync(conexao, "schema.sql", essencial: true);
            await ExecutarScriptAsync(conexao, "seed.sql", essencial: true);
            if (_carregarDemonstracao)
                await ExecutarScriptAsync(conexao, "demo.sql", essencial: false);

            estado.Registrar(true);
            _log.LogInformation("Banco pronto (demonstração: {Demo}).", _carregarDemonstracao ? "sim" : "não");
        }
        catch (Exception ex)
        {
            estado.Registrar(false, ex.Message);
            _log.LogError(ex, "Preparação do banco interrompida. /health/ready ficará indisponível até corrigir.");
        }
    }

    private async Task CriarBancoSeNecessarioAsync()
    {
        var builder = new SqlConnectionStringBuilder(_connectionString);
        var nomeBanco = builder.InitialCatalog;
        if (string.IsNullOrWhiteSpace(nomeBanco) || !Regex.IsMatch(nomeBanco, @"^[A-Za-z0-9_]+$"))
            throw new InvalidOperationException("Nome de banco inválido na connection string.");

        builder.InitialCatalog = "master";
        for (var tentativa = 1; ; tentativa++)
        {
            try
            {
                await using var master = new SqlConnection(builder.ConnectionString);
                await master.OpenAsync();
                await using var cmd = new SqlCommand(
                    $"IF DB_ID('{nomeBanco}') IS NULL CREATE DATABASE [{nomeBanco}];", master);
                await cmd.ExecuteNonQueryAsync();
                return;
            }
            catch (SqlException ex) when (tentativa < 10)
            {
                // No Docker o SQL Server pode levar alguns segundos para aceitar conexões
                _log.LogWarning("SQL Server indisponível (tentativa {T}/10): {Msg}", tentativa, ex.Message);
                await Task.Delay(TimeSpan.FromSeconds(5));
            }
        }
    }

    private async Task ExecutarScriptAsync(SqlConnection conexao, string arquivo, bool essencial)
    {
        var caminho = Path.Combine(_pastaScripts, arquivo);
        if (!File.Exists(caminho))
        {
            if (essencial) throw new FileNotFoundException($"Script obrigatório não encontrado: {caminho}");
            _log.LogWarning("Script opcional não encontrado: {Caminho}", caminho);
            return;
        }

        var lotes = Regex.Split(await File.ReadAllTextAsync(caminho), @"^\s*GO\s*$",
                RegexOptions.Multiline | RegexOptions.IgnoreCase)
            .Where(l => !string.IsNullOrWhiteSpace(l)).ToList();

        for (var i = 0; i < lotes.Count; i++)
        {
            try
            {
                await using var cmd = new SqlCommand(lotes[i], conexao) { CommandTimeout = 120 };
                await cmd.ExecuteNonQueryAsync();
            }
            catch (SqlException ex)
            {
                var inicio = lotes[i].Trim().Split('\n').FirstOrDefault(l => !l.TrimStart().StartsWith("--"))?.Trim();
                var mensagem = $"{arquivo}, lote {i + 1}/{lotes.Count} ({inicio}): {ex.Message}";
                if (essencial) throw new InvalidOperationException(mensagem, ex);
                _log.LogWarning("Lote opcional ignorado — {Mensagem}", mensagem);
            }
        }
        _log.LogInformation("{Arquivo}: {Total} lotes executados.", arquivo, lotes.Count);
    }
}
