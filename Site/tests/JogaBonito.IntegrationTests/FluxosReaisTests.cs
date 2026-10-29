using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using JogaBonito.Api.Infrastructure.Dados;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace JogaBonito.IntegrationTests;

/// <summary>
/// Fluxos completos contra a API real + SQL Server real: o que os testes com API simulada
/// (Playwright) não conseguem provar — procedures, triggers, transações e concorrência.
/// </summary>
[Collection("api-real")]
public class FluxosReaisTests
{
    private readonly ApiReal _api;

    public FluxosReaisTests(ApiReal api) => _api = api;

    [FatoComBanco]
    public async Task Banco_criado_do_zero_fica_pronto_com_36_produtos()
    {
        var c = _api.CreateClient();
        var saude = await c.GetFromJsonAsync<JsonElement>("/health/ready");
        Assert.Equal("Healthy", saude.GetProperty("status").GetString());

        var produtos = await c.GetFromJsonAsync<JsonElement[]>("/api/produtos");
        Assert.Equal(36, produtos!.Length);
        Assert.Equal(Enumerable.Range(1, 36), produtos.Select(p => p.GetProperty("id").GetInt32()).Order());

        var umbro = await c.GetFromJsonAsync<JsonElement[]>("/api/produtos?categoria=chuteiras&marca=Umbro");
        Assert.Equal(2, umbro!.Length);
    }

    [FatoComBanco]
    public async Task Scripts_rodam_de_novo_sem_duplicar_nada()
    {
        // Simula um segundo deploy: schema + seed + demo outra vez sobre o mesmo banco
        var estado = new EstadoBanco();
        await new InicializadorBanco(_api.ConexaoTeste, Path.Combine(PastaSite(), "banco"), true,
            NullLogger<InicializadorBanco>.Instance).ExecutarAsync(estado);
        Assert.True(estado.Sucesso, estado.Erro);

        var c = _api.CreateClient();
        Assert.Equal(36, (await c.GetFromJsonAsync<JsonElement[]>("/api/produtos"))!.Length);
        Assert.Equal(3, (await c.GetFromJsonAsync<JsonElement[]>("/api/categorias"))!.Length);

        var admin = await _api.ClienteLogadoAsync("admin@jogabonito.com", "Admin@2026");
        var consulta = await admin.GetFromJsonAsync<JsonElement>("/api/admin/consultas/cupons");
        Assert.Equal(3, consulta.GetProperty("linhas").GetArrayLength());
    }

    [FatoComBanco]
    public async Task Compra_completa_baixa_estoque_e_registra_joga_junto()
    {
        var cliente = await _api.NovoClienteAsync();
        var antes = await _api.SaldoAsync(1, "M");

        var resposta = await cliente.PostAsJsonAsync("/api/pedidos", ApiReal.Pedido(1, "M"));
        Assert.Equal(HttpStatusCode.Created, resposta.StatusCode);
        var criado = await resposta.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(349.90m, criado.GetProperty("total").GetDecimal());          // frete grátis ≥ R$ 299
        Assert.Equal(3.50m, criado.GetProperty("jogaJunto").GetDecimal());       // 1% de R$ 349,90

        Assert.Equal(antes - 1, await _api.SaldoAsync(1, "M"));                  // trigger de baixa
        var meus = await cliente.GetFromJsonAsync<JsonElement[]>("/api/pedidos/meus");
        Assert.Single(meus!);
        Assert.Equal("Pago", meus![0].GetProperty("status").GetString());

        // Cancelamento devolve a peça e entra no histórico (trigger)
        var id = criado.GetProperty("pedidoId").GetInt32();
        Assert.Equal(HttpStatusCode.NoContent, (await cliente.PostAsync($"/api/pedidos/{id}/cancelar", null)).StatusCode);
        Assert.Equal(antes, await _api.SaldoAsync(1, "M"));
        var pedido = await cliente.GetFromJsonAsync<JsonElement>($"/api/pedidos/{id}");
        Assert.Equal(new[] { "Pago", "Cancelado" },
            pedido.GetProperty("historico").EnumerateArray().Select(h => h.GetProperty("status").GetString()));
    }

    [FatoComBanco]
    public async Task Estoque_insuficiente_nao_grava_nada()
    {
        // Pelo seed: produto 8 tamanho P está esgotado (0) e produto 6 tamanho P tem só 3 peças
        var cliente = await _api.NovoClienteAsync();
        Assert.Equal(0, await _api.SaldoAsync(8, "P"));
        Assert.Equal(3, await _api.SaldoAsync(6, "P"));

        Assert.Equal(HttpStatusCode.BadRequest, (await cliente.PostAsJsonAsync("/api/pedidos", ApiReal.Pedido(8, "P"))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await cliente.PostAsJsonAsync("/api/pedidos", ApiReal.Pedido(6, "P", 4))).StatusCode);

        Assert.Equal(3, await _api.SaldoAsync(6, "P"));
        Assert.Empty((await cliente.GetFromJsonAsync<JsonElement[]>("/api/pedidos/meus"))!);
    }

    [FatoComBanco]
    public async Task Duas_compras_simultaneas_da_ultima_peca_so_uma_passa()
    {
        var admin = await _api.ClienteLogadoAsync("admin@jogabonito.com", "Admin@2026");
        (await admin.PutAsJsonAsync("/api/admin/estoque", new { produtoId = 3, tamanho = "GG", quantidade = 1 }))
            .EnsureSuccessStatusCode();

        var a = await _api.NovoClienteAsync("a");
        var b = await _api.NovoClienteAsync("b");
        var respostas = await Task.WhenAll(
            a.PostAsJsonAsync("/api/pedidos", ApiReal.Pedido(3, "GG")),
            b.PostAsJsonAsync("/api/pedidos", ApiReal.Pedido(3, "GG")));

        Assert.Equal(1, respostas.Count(r => r.StatusCode == HttpStatusCode.Created));
        Assert.Equal(1, respostas.Count(r => r.StatusCode == HttpStatusCode.BadRequest));
        Assert.Equal(0, await _api.SaldoAsync(3, "GG"));
    }

    [FatoComBanco]
    public async Task Permissoes_de_cliente_admin_e_anonimo()
    {
        var anonimo = _api.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonimo.GetAsync("/api/pedidos/meus")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonimo.GetAsync("/api/admin/dashboard")).StatusCode);

        var cliente = await _api.NovoClienteAsync();
        Assert.Equal(HttpStatusCode.Forbidden, (await cliente.GetAsync("/api/admin/dashboard")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await cliente.PutAsJsonAsync("/api/admin/estoque",
            new { produtoId = 1, tamanho = "M", quantidade = 999 })).StatusCode);

        // Cliente não vê pedido de outro cliente
        var outro = await _api.NovoClienteAsync();
        var criado = await (await outro.PostAsJsonAsync("/api/pedidos", ApiReal.Pedido(4, "M")))
            .Content.ReadFromJsonAsync<JsonElement>();
        var id = criado.GetProperty("pedidoId").GetInt32();
        Assert.Equal(HttpStatusCode.NotFound, (await cliente.GetAsync($"/api/pedidos/{id}")).StatusCode);

        var admin = await _api.ClienteLogadoAsync("admin@jogabonito.com", "Admin@2026");
        Assert.Equal(HttpStatusCode.OK, (await admin.GetAsync("/api/admin/dashboard")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await admin.GetAsync($"/api/pedidos/{id}")).StatusCode);
    }

    [FatoComBanco]
    public async Task Avaliacao_com_link_espera_moderacao_e_admin_publica()
    {
        var cliente = await _api.NovoClienteAsync();
        (await cliente.PostAsJsonAsync("/api/pedidos", ApiReal.Pedido(6, "M"))).EnsureSuccessStatusCode();

        var r = await cliente.PostAsJsonAsync("/api/produtos/6/avaliacoes",
            new { nota = 5, comentario = "Comprei mais barato em www.outraloja.com" });
        Assert.Equal("Pendente", (await r.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("status").GetString());
        var publicas = await _api.CreateClient().GetFromJsonAsync<JsonElement[]>("/api/produtos/6/avaliacoes");
        Assert.Empty(publicas!);

        var admin = await _api.ClienteLogadoAsync("admin@jogabonito.com", "Admin@2026");
        var fila = await admin.GetFromJsonAsync<JsonElement[]>("/api/admin/avaliacoes?status=Pendente");
        var id = fila!.Single(a => a.GetProperty("produtoId").GetInt32() == 6).GetProperty("id").GetInt32();

        var semMotivo = await admin.PutAsJsonAsync($"/api/admin/avaliacoes/{id}", new { status = "Oculta", motivo = "" });
        Assert.Equal(HttpStatusCode.BadRequest, semMotivo.StatusCode);
        (await admin.PutAsJsonAsync($"/api/admin/avaliacoes/{id}", new { status = "Publicada", motivo = "Link removido não é ofensivo" }))
            .EnsureSuccessStatusCode();
        publicas = await _api.CreateClient().GetFromJsonAsync<JsonElement[]>("/api/produtos/6/avaliacoes");
        Assert.Single(publicas!);
    }

    [FatoComBanco]
    public async Task Trocar_senha_derruba_o_token_antigo()
    {
        var cliente = await _api.NovoClienteAsync();
        var email = cliente.DefaultRequestHeaders.GetValues("X-Email-Teste").Single();
        var outroAparelho = await _api.ClienteLogadoAsync(email, "Camisa10Gol");

        var r = await cliente.PostAsJsonAsync("/api/auth/trocar-senha", new { senhaAtual = "Camisa10Gol", novaSenha = "NovaSenha2027" });
        r.EnsureSuccessStatusCode();

        Assert.Equal(HttpStatusCode.Unauthorized, (await outroAparelho.GetAsync("/api/pedidos/meus")).StatusCode);
        await _api.ClienteLogadoAsync(email, "NovaSenha2027");
    }

    [FatoComBanco]
    public async Task Lgpd_exporta_e_exclui_os_dados_do_titular()
    {
        var cliente = await _api.NovoClienteAsync();
        var email = cliente.DefaultRequestHeaders.GetValues("X-Email-Teste").Single();
        (await cliente.PostAsJsonAsync("/api/pedidos", ApiReal.Pedido(7, "G"))).EnsureSuccessStatusCode();   // 7/M é esgotado de propósito no seed

        var dados = await cliente.GetFromJsonAsync<JsonElement>("/api/auth/meus-dados");
        Assert.Equal(email, dados.GetProperty("conta").GetProperty("email").GetString());
        Assert.Equal(1, dados.GetProperty("pedidos").GetArrayLength());

        Assert.Equal(HttpStatusCode.BadRequest,
            (await cliente.PostAsJsonAsync("/api/auth/excluir-conta", new { senha = "errada" })).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent,
            (await cliente.PostAsJsonAsync("/api/auth/excluir-conta", new { senha = "Camisa10Gol" })).StatusCode);

        // Token antigo não vale mais e o e-mail não entra mais
        Assert.Equal(HttpStatusCode.Unauthorized, (await cliente.GetAsync("/api/pedidos/meus")).StatusCode);
        var login = await _api.CreateClient().PostAsJsonAsync("/api/auth/login", new { email, senha = "Camisa10Gol" });
        Assert.Equal(HttpStatusCode.Unauthorized, login.StatusCode);
    }

    private static string PastaSite()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "banco", "schema.sql")))
            dir = dir.Parent;
        return dir!.FullName;
    }
}
