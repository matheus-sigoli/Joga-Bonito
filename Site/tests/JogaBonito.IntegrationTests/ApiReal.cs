using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.SqlClient;
using Xunit;

namespace JogaBonito.IntegrationTests;

/// <summary>
/// Sobe a API .NET real, em memória, apontando para um banco NOVO no SQL Server indicado
/// por JB_TESTE_SQL. A própria API cria o esquema, o catálogo e os dados de demonstração
/// (Banco:CriarAutomaticamente). Ao final, o banco temporário é apagado.
/// </summary>
public sealed class ApiReal : WebApplicationFactory<Program>, IAsyncLifetime
{
    public const string VariavelConexao = "JB_TESTE_SQL";
    public static string? ConexaoBase => Environment.GetEnvironmentVariable(VariavelConexao);

    public string NomeBanco { get; } = $"JogaBonitoTeste_{Guid.NewGuid():N}"[..32];
    public string ConexaoTeste { get; }

    public ApiReal()
    {
        var b = new SqlConnectionStringBuilder(ConexaoBase ?? "Server=.;") { InitialCatalog = NomeBanco };
        ConexaoTeste = b.ConnectionString;

        // Variáveis de ambiente são lidas pelo WebApplication.CreateBuilder antes de qualquer outra coisa
        Definir("ConnectionStrings__DefaultConnection", ConexaoTeste);
        Definir("Site__Raiz", PastaSite());
        Definir("Banco__CriarAutomaticamente", "true");
        Definir("Banco__CarregarDemonstracao", "true");
        Definir("Seguranca__LoginsPorMinuto", "1000");
        Definir("Seguranca__PedidosPorMinuto", "1000");
        Definir("Seguranca__RequisicoesPorMinuto", "100000");
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder) =>
        builder.UseEnvironment("Development");

    public Task InitializeAsync() => Task.CompletedTask;

    public new async Task DisposeAsync()
    {
        await base.DisposeAsync();
        if (ConexaoBase is null) return;
        SqlConnection.ClearAllPools();
        var master = new SqlConnectionStringBuilder(ConexaoBase) { InitialCatalog = "master" }.ConnectionString;
        await using var con = new SqlConnection(master);
        await con.OpenAsync();
        await using var cmd = new SqlCommand(
            $"IF DB_ID('{NomeBanco}') IS NOT NULL BEGIN ALTER DATABASE [{NomeBanco}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{NomeBanco}]; END", con);
        await cmd.ExecuteNonQueryAsync();
    }

    // ------------------------------------------------------------------ ajudas
    public async Task<HttpClient> ClienteLogadoAsync(string email, string senha)
    {
        var c = CreateClient();
        var r = await c.PostAsJsonAsync("/api/auth/login", new { email, senha });
        r.EnsureSuccessStatusCode();
        var token = (await r.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("token").GetString();
        c.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return c;
    }

    public async Task<HttpClient> NovoClienteAsync(string prefixo = "cliente")
    {
        // Corta só o identificador: cortar o texto inteiro podia remover o "@teste.com"
        var email = $"{prefixo}-{Guid.NewGuid():N}"[..Math.Min(prefixo.Length + 17, 60)] + "@teste.com";
        var anonimo = CreateClient();
        var r = await anonimo.PostAsJsonAsync("/api/auth/cadastro",
            new { nome = "Cliente de Teste", email, senha = "Camisa10Gol", aceiteLgpd = true });
        r.EnsureSuccessStatusCode();
        var c = await ClienteLogadoAsync(email, "Camisa10Gol");
        c.DefaultRequestHeaders.Add("X-Email-Teste", email);
        return c;
    }

    public async Task<int> SaldoAsync(int produtoId, string tamanho)
    {
        var d = await CreateClient().GetFromJsonAsync<JsonElement>($"/api/produtos/{produtoId}");
        return d.GetProperty("tamanhos").EnumerateArray()
            .Single(t => t.GetProperty("tamanho").GetString() == tamanho).GetProperty("quantidade").GetInt32();
    }

    public static object Pedido(int produtoId, string tamanho, int quantidade = 1) => new
    {
        itens = new[] { new { produtoId, tamanho, quantidade } },
        formaPagamento = "PIX",
        parcelas = 1,
        endereco = new
        {
            cep = "01310100", rua = "Avenida Paulista", numero = "1000", complemento = (string?)null,
            bairro = "Bela Vista", cidade = "São Paulo", estado = "SP"
        },
        origem = "Web"
    };

    private static void Definir(string nome, string valor) => Environment.SetEnvironmentVariable(nome, valor);

    private static string PastaSite()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "banco", "schema.sql")))
            dir = dir.Parent;
        return dir?.FullName ?? throw new DirectoryNotFoundException("Pasta Site (com banco/schema.sql) não encontrada.");
    }
}

/// <summary>Teste que precisa do SQL Server: ignorado quando JB_TESTE_SQL não está definida.</summary>
public sealed class FatoComBancoAttribute : FactAttribute
{
    public FatoComBancoAttribute()
    {
        if (string.IsNullOrWhiteSpace(ApiReal.ConexaoBase))
            Skip = $"Defina {ApiReal.VariavelConexao} com a conexão de um SQL Server de testes.";
    }
}

[CollectionDefinition("api-real")]
public sealed class ColecaoApiReal : ICollectionFixture<ApiReal> { }
