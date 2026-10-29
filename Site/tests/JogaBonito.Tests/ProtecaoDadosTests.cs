using System.Security.Cryptography;
using JogaBonito.Api.Application.Servicos;
using JogaBonito.Api.Domain.Excecoes;
using JogaBonito.Api.Infrastructure.Dados;
using JogaBonito.Api.Infrastructure.Seguranca;
using Microsoft.AspNetCore.Http;
using Xunit;

namespace JogaBonito.Tests;

// ============================================================================
// Rodada de segurança: criptografia dos dados pessoais, máscaras, sessão por
// cookie (CSRF), imagens de produto e sincronização do catalogo-local.js.
// ============================================================================

public class ProtetorDadosTests
{
    private static ProtetorDados Novo() => new(RandomNumberGenerator.GetBytes(32));

    [Theory]
    [InlineData("Avenida Paulista")]
    [InlineData("Rua São João, Conceição")]   // acentos
    [InlineData("01310100")]
    [InlineData("")]
    public void Cifra_e_abre_o_mesmo_texto(string texto)
    {
        var p = Novo();
        var cifrado = p.Proteger(texto)!;
        Assert.StartsWith(ProtetorDados.Prefixo, cifrado);
        Assert.DoesNotContain(texto.Length > 0 ? texto : "§", cifrado);
        Assert.Equal(texto, p.Abrir(cifrado));
    }

    [Fact]
    public void Mesmo_endereco_gera_textos_cifrados_diferentes()
    {
        var p = Novo();
        Assert.NotEqual(p.Proteger("Avenida Paulista"), p.Proteger("Avenida Paulista"));
    }

    [Fact]
    public void Valor_adulterado_no_banco_nao_abre()
    {
        var p = Novo();
        var bytes = Convert.FromBase64String(p.Proteger("Avenida Paulista")![ProtetorDados.Prefixo.Length..]);
        bytes[^1] ^= 0x01;
        Assert.ThrowsAny<CryptographicException>(() => p.Abrir(ProtetorDados.Prefixo + Convert.ToBase64String(bytes)));
    }

    [Fact]
    public void Chave_errada_nao_abre()
    {
        var cifrado = Novo().Proteger("Avenida Paulista");
        Assert.ThrowsAny<CryptographicException>(() => Novo().Abrir(cifrado));
    }

    [Fact]
    public void Texto_antigo_sem_prefixo_e_lido_como_esta_e_nulo_continua_nulo()
    {
        var p = Novo();
        Assert.Equal("Removido (LGPD)", p.Abrir("Removido (LGPD)"));
        Assert.Null(p.Proteger(null));
        Assert.Null(p.Abrir(null));
    }

    [Theory]
    [InlineData("")]
    [InlineData("curta")]
    [InlineData("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")] // 48 bytes
    public void Chave_invalida_e_recusada(string base64) =>
        Assert.Throws<InvalidOperationException>(() => ProtetorDados.DeBase64(base64));
}

public class MascaraTests
{
    [Theory]
    [InlineData("matheus@estudante.com", "ma*****@estudante.com")]
    [InlineData("admin@jogabonito.com", "ad***@jogabonito.com")]
    [InlineData("jo@x.com", "j***@x.com")]
    [InlineData("semarroba", "***")]
    public void Email(string email, string esperado) => Assert.Equal(esperado, Mascara.Email(email));

    [Theory]
    [InlineData("200.150.10.27", "200.150.10.x")]
    [InlineData("2804:14c:5b:1234::9", "2804:14c:5b::x")]
    [InlineData(null, null)]
    public void Ip(string? ip, string? esperado) => Assert.Equal(esperado, Mascara.Ip(ip));

    [Fact]
    public void Telefone() => Assert.Equal("(**) *****-7777", Mascara.Telefone("(11) 98888-7777"));
}

public class CookieSessaoTests
{
    private static HttpRequest Requisicao(string host = "localhost:5000", string esquema = "http")
    {
        var ctx = new DefaultHttpContext();
        ctx.Request.Scheme = esquema;
        ctx.Request.Host = new HostString(host);
        return ctx.Request;
    }

    [Theory]
    [InlineData("http://localhost:5000", false, true)]        // a própria loja
    [InlineData("https://loja.exemplo.com", false, true)]     // origem liberada em Cors:Origens
    [InlineData("http://localhost:5500", true, true)]         // Live Server, só em desenvolvimento
    [InlineData("http://localhost:5500", false, false)]
    [InlineData("https://golpe.exemplo.net", true, false)]    // nunca
    [InlineData("null", true, false)]                          // iframe/arquivo sem origem
    public void Origem_permitida(string origem, bool desenvolvimento, bool esperado) =>
        Assert.Equal(esperado, CookieSessao.OrigemPermitida(origem, Requisicao(),
            new[] { "https://loja.exemplo.com" }, desenvolvimento));

    [Fact]
    public async Task Escrita_pelo_cookie_sem_cabecalho_e_recusada_e_com_cabecalho_passa()
    {
        var middleware = CookieSessao.Middleware(Array.Empty<string>(), desenvolvimento: false);

        async Task<int> Executar(bool comCabecalho)
        {
            var ctx = new DefaultHttpContext();
            ctx.Request.Method = "POST";
            ctx.Request.Path = "/api/pedidos";
            ctx.Request.Headers.Cookie = "jb_sessao=token-qualquer";
            if (comCabecalho) ctx.Request.Headers[CookieSessao.CabecalhoCsrf] = "1";
            ctx.Response.Body = new MemoryStream();
            var chegou = false;
            await middleware(ctx, () => { chegou = true; return Task.CompletedTask; });
            return chegou ? 200 : ctx.Response.StatusCode;
        }

        Assert.Equal(403, await Executar(comCabecalho: false));
        Assert.Equal(200, await Executar(comCabecalho: true));
    }

    [Fact]
    public async Task App_com_bearer_nao_precisa_do_cabecalho_csrf()
    {
        var ctx = new DefaultHttpContext();
        ctx.Request.Method = "POST";
        ctx.Request.Path = "/api/pedidos";
        ctx.Request.Headers.Authorization = "Bearer abc";
        var chegou = false;
        await CookieSessao.Middleware(Array.Empty<string>(), false)(ctx, () => { chegou = true; return Task.CompletedTask; });
        Assert.True(chegou);
    }
}

public class ImagemProdutoTests
{
    [Theory]
    [InlineData("../IMG/Produtos/37/1.jpg")]
    [InlineData("../IMG/LOGO 2.png")]
    [InlineData("../IMG/Produtos/5/ilustracao.svg")]
    public void Caminho_da_pasta_IMG_e_aceito(string caminho) =>
        Assert.Equal(caminho, CatalogoServico.ValidarImagem(caminho));

    [Theory]
    [InlineData("https://rastreador.exemplo/foto.jpg")]
    [InlineData("javascript:alert(1)")]
    [InlineData("data:image/svg+xml;base64,PHN2Zz4=")]
    [InlineData("../IMG/../../backend/appsettings.json")]
    [InlineData("../IMG/Produtos/1/foto.exe")]
    [InlineData("//golpe.exemplo/foto.jpg")]
    public void Caminho_fora_da_pasta_ou_externo_e_recusado(string caminho) =>
        Assert.Throws<RegraNegocioException>(() => CatalogoServico.ValidarImagem(caminho));
}

public class SincronizadorCatalogoLocalTests
{
    private static string ArquivoReal()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "Javascript", "catalogo-local.js")))
            dir = dir.Parent;
        return Path.Combine(dir?.FullName ?? throw new DirectoryNotFoundException("Site/Javascript"), "Javascript", "catalogo-local.js");
    }

    [Fact]
    public void Catalogo_local_do_projeto_tem_36_produtos_validos()
    {
        var (produtos, ignorados) = SincronizadorCatalogoLocal.Ler(File.ReadAllText(ArquivoReal()));
        Assert.Equal(0, ignorados);
        Assert.Equal(36, produtos.Count);
        Assert.Equal(Enumerable.Range(1, 36), produtos.Select(p => p.Id).OrderBy(i => i));
        Assert.Equal(12, produtos.Count(p => p.CategoriaSlug == "chuteiras"));
        Assert.All(produtos, p => Assert.StartsWith("../IMG/Produtos/", p.Imagem));
    }

    [Fact]
    public void Versao_muda_com_o_preco_mas_nao_com_a_quantidade_em_estoque()
    {
        var (produtos, _) = SincronizadorCatalogoLocal.Ler(File.ReadAllText(ArquivoReal()));
        var original = SincronizadorCatalogoLocal.Versao(produtos);

        var outroEstoque = produtos.Select(p => p with { Tamanhos = p.Tamanhos.Select(t => (t.Tamanho, t.Quantidade + 5)).ToList() });
        Assert.Equal(original, SincronizadorCatalogoLocal.Versao(outroEstoque));

        var outroPreco = produtos.Select(p => p.Id == 1 ? p with { Preco = p.Preco + 10 } : p);
        Assert.NotEqual(original, SincronizadorCatalogoLocal.Versao(outroPreco));
    }

    [Fact]
    public void Produto_invalido_e_ignorado_e_o_resto_segue()
    {
        const string js = """
            const JB_CATALOGO_LOCAL = [
             { "id": 1, "categoriaSlug": "retro", "nome": "Camisa Teste", "modelo": "Coleção Retrô", "linha": "Clube",
               "descricao": "Descrição de teste com tamanho suficiente.", "preco": 199.9, "img": "../IMG/Produtos/1/1.jpg",
               "tamanhos": [ { "tamanho": "M", "quantidade": 3 } ] },
             { "id": 2, "categoriaSlug": "retro", "nome": "Imagem externa", "modelo": "x", "linha": "Clube",
               "descricao": "Descrição de teste com tamanho suficiente.", "preco": 199.9, "img": "https://golpe.exemplo/a.jpg" },
             { "id": 3, "categoriaSlug": "retro", "nome": "Linha errada", "modelo": "x", "linha": "Basquete",
               "descricao": "Descrição de teste com tamanho suficiente.", "preco": 199.9, "img": "../IMG/Produtos/3/1.jpg" },
             { "id": 4, "categoriaSlug": "chuteiras", "nome": "Chuteira", "modelo": "x", "linha": "Futsal",
               "descricao": "Descrição de teste com tamanho suficiente.", "preco": 0, "img": "../IMG/Produtos/4/1.jpg" },
            ];
            """;
        var (produtos, ignorados) = SincronizadorCatalogoLocal.Ler(js);
        Assert.Equal(new[] { 1 }, produtos.Select(p => p.Id));
        Assert.Equal(3, ignorados);
    }
}

public class SincronizadorImagensTests
{
    [Fact]
    public void Fotos_da_pasta_viram_a_galeria_em_ordem_natural_e_a_ilustracao_so_vale_sem_foto()
    {
        var pasta = Directory.CreateTempSubdirectory("jb-fotos-").FullName;
        try
        {
            File.WriteAllText(Path.Combine(pasta, "ilustracao.svg"), "<svg/>");
            Assert.Equal(new[] { "../IMG/Produtos/7/ilustracao.svg" }, SincronizadorImagens.GaleriaDaPasta(pasta, 7));

            foreach (var n in new[] { "10.jpg", "2.jpg", "frente.png", "Costas.webp", "1.JPG", "__temp.jpg", "notas.txt", "foto;alert(1).jpg" })
                File.WriteAllText(Path.Combine(pasta, n), "x");

            Assert.Equal(new[]
            {
                "../IMG/Produtos/7/1.JPG", "../IMG/Produtos/7/2.jpg", "../IMG/Produtos/7/10.jpg",
                "../IMG/Produtos/7/Costas.webp", "../IMG/Produtos/7/frente.png"
            }, SincronizadorImagens.GaleriaDaPasta(pasta, 7));
        }
        finally
        {
            Directory.Delete(pasta, recursive: true);
        }
    }
}
