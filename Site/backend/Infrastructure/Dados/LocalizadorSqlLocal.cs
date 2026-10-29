using Microsoft.Data.SqlClient;

namespace JogaBonito.Api.Infrastructure.Dados;

/// <summary>
/// Desenvolvimento no Windows: encontra sozinho um SQL Server neste computador quando a connection string
/// configurada (por padrão .\SQLEXPRESS) não responde — assim a API funciona pelo Visual Studio, pelo
/// "dotnet run" ou pelo lançador, tenha o computador SQL Express, a instância padrão ou só o LocalDB.
///
/// Ordem: o servidor configurado → o que o lançador encontrou da última vez
/// (%LOCALAPPDATA%\JogaBonito\servidor-sql.txt) → .\SQLEXPRESS → . → (localdb)\MSSQLLocalDB.
/// Só vale para autenticação do Windows (Trusted_Connection); com usuário e senha (Docker, nuvem)
/// a connection string é usada exatamente como veio.
/// </summary>
public static class LocalizadorSqlLocal
{
    public static async Task<(string Conexao, string? Aviso)> ResolverAsync(string conexao)
    {
        SqlConnectionStringBuilder original;
        try { original = new SqlConnectionStringBuilder(conexao); }
        catch (ArgumentException) { return (conexao, null); }
        if (!original.IntegratedSecurity) return (conexao, null);

        var candidatos = new List<string> { original.DataSource };
        var salvo = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "JogaBonito", "servidor-sql.txt");
        try
        {
            if (File.Exists(salvo))
                candidatos.Add((await File.ReadAllLinesAsync(salvo)).FirstOrDefault()?.Trim() ?? "");
        }
        catch (IOException) { /* arquivo em uso: segue com os padrões */ }
        if (OperatingSystem.IsWindows())
            candidatos.AddRange(new[] { @".\SQLEXPRESS", ".", @"(localdb)\MSSQLLocalDB" });

        foreach (var servidor in candidatos.Where(c => !string.IsNullOrWhiteSpace(c)).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!await RespondeAsync(original, servidor)) continue;
            if (string.Equals(servidor, original.DataSource, StringComparison.OrdinalIgnoreCase))
                return (conexao, null);
            var ajustada = new SqlConnectionStringBuilder(conexao) { DataSource = servidor };
            return (ajustada.ConnectionString,
                $"SQL Server '{original.DataSource}' não respondeu; usando '{servidor}', encontrado neste computador.");
        }
        return (conexao, $"Nenhum SQL Server respondeu neste computador ({string.Join(", ", candidatos.Distinct())}). " +
                         "Ligue o serviço SQL Server (iniciar-projeto.bat faz isso) — a API tenta de novo sozinha.");
    }

    private static async Task<bool> RespondeAsync(SqlConnectionStringBuilder modelo, string servidor)
    {
        var teste = new SqlConnectionStringBuilder(modelo.ConnectionString)
        {
            DataSource = servidor,
            InitialCatalog = "master",
            ConnectTimeout = servidor.StartsWith("(localdb)", StringComparison.OrdinalIgnoreCase) ? 20 : 4,
            ConnectRetryCount = 0,
            Pooling = false
        };
        try
        {
            await using var con = new SqlConnection(teste.ConnectionString);
            await con.OpenAsync();
            return true;
        }
        catch (Exception ex) when (ex is SqlException or InvalidOperationException or PlatformNotSupportedException)
        {
            return false;
        }
    }
}
