using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Application.Servicos;
using JogaBonito.Api.Domain.Entidades;
using JogaBonito.Api.Domain.Excecoes;
using JogaBonito.Api.Infrastructure.Cache;
using JogaBonito.Api.Infrastructure.Seguranca;
using System.Security.Claims;
using Microsoft.Extensions.Caching.Memory;
using Xunit;

namespace JogaBonito.Tests;

// ============================================================================
// PRD-002 — bloqueio de login, troca de senha, cache do catálogo e marca/solado.
// Tudo com dublês em memória: os testes não precisam de SQL Server.
// ============================================================================

public class BloqueioLoginTests
{
    private static (AuthServico Servico, UsuariosFake Repo) Criar()
    {
        var repo = new UsuariosFake();
        return (new AuthServico(repo, new HasherFake(), new TokenFake()), repo);
    }

    [Fact]
    public async Task Quinta_senha_errada_bloqueia_a_conta()
    {
        var (auth, repo) = Criar();
        for (var i = 1; i < Usuario.MaxTentativasLogin; i++)
            await Assert.ThrowsAsync<AcessoNegadoException>(() =>
                auth.LoginAsync(new LoginRequest("matheus@estudante.com", "errada"), "10.0.0.1"));

        await Assert.ThrowsAsync<ContaBloqueadaException>(() =>
            auth.LoginAsync(new LoginRequest("matheus@estudante.com", "errada"), "10.0.0.1"));

        Assert.Equal(5, repo.Log.Count(l => l.Detalhe == "Senha incorreta"));
        Assert.All(repo.Log, l => Assert.Equal("10.0.0.1", l.Ip));
    }

    [Fact]
    public async Task Conta_bloqueada_recusa_ate_a_senha_certa_e_registra_no_log()
    {
        var (auth, repo) = Criar();
        repo.BloquearAte(DateTime.Now.AddMinutes(10));

        await Assert.ThrowsAsync<ContaBloqueadaException>(() =>
            auth.LoginAsync(new LoginRequest("matheus@estudante.com", "Cliente@2026")));

        Assert.Equal("Conta bloqueada", repo.Log.Single().Detalhe);
        Assert.False(repo.Log.Single().Sucesso);
    }

    [Fact]
    public async Task Login_certo_zera_contador_e_registra_sucesso()
    {
        var (auth, repo) = Criar();
        await Assert.ThrowsAsync<AcessoNegadoException>(() => auth.LoginAsync(new LoginRequest("matheus@estudante.com", "x")));

        var r = await auth.LoginAsync(new LoginRequest(" MATHEUS@estudante.com ", "Cliente@2026"));

        Assert.Equal("token-2", r.Token);
        Assert.Equal(0, repo.Falhas);
        Assert.True(repo.Log.Last().Sucesso);
    }

    [Fact]
    public async Task Email_inexistente_tem_a_mesma_mensagem_de_senha_errada()
    {
        var (auth, repo) = Criar();
        var ex = await Assert.ThrowsAsync<AcessoNegadoException>(() =>
            auth.LoginAsync(new LoginRequest("ninguem@teste.com", "qualquer1")));
        Assert.Equal("E-mail ou senha incorretos.", ex.Message);
        Assert.Equal("E-mail não cadastrado", repo.Log.Single().Detalhe);
    }

    [Fact]
    public async Task Trocar_senha_exige_a_senha_atual_e_uma_senha_forte()
    {
        var (auth, repo) = Criar();
        await Assert.ThrowsAsync<RegraNegocioException>(() =>
            auth.TrocarSenhaAsync(2, new TrocarSenhaRequest("errada", "NovaSenha2027")));
        await Assert.ThrowsAsync<RegraNegocioException>(() =>
            auth.TrocarSenhaAsync(2, new TrocarSenhaRequest("Cliente@2026", "fraca")));
        await Assert.ThrowsAsync<RegraNegocioException>(() =>
            auth.TrocarSenhaAsync(2, new TrocarSenhaRequest("Cliente@2026", "Cliente@2026")));

        var nova = await auth.TrocarSenhaAsync(2, new TrocarSenhaRequest("Cliente@2026", "NovaSenha2027"));
        Assert.Equal("hash:NovaSenha2027", repo.Hash);
        Assert.Equal(2, repo.Versao);                  // sessões antigas derrubadas
        Assert.Equal("token-2-v2", nova.Token);        // esta sessão continua com token novo
    }

    [Fact]
    public async Task Login_refaz_hash_com_custo_antigo()
    {
        var (auth, repo) = Criar();
        repo.HashAntigo = true;
        await auth.LoginAsync(new LoginRequest("matheus@estudante.com", "Cliente@2026"));
        Assert.Equal("hash:Cliente@2026", repo.Hash);
        Assert.False(repo.HashAntigo);
        Assert.Equal(1, repo.Versao);                  // rehash não derruba a sessão
    }

    [Theory]
    [InlineData("TROQUE-ESTA-CHAVE-EM-PRODUCAO-JogaBonito-PIM4-2026", true)]
    [InlineData("DEV-SOMENTE-chave-local-JogaBonito-PIM4-2026-nao-usar", true)]
    [InlineData("q8Zr0v4Lk2NwYp7tXs1Hc9Bm3Df6Ga5JeRu0Ti8Ko2Qw", false)]
    public void Chave_jwt_de_exemplo_e_recusada_em_producao(string chave, bool exemplo) =>
        Assert.Equal(exemplo, JwtOpcoes.EhChaveDeExemplo(chave));

    // ---------------------------------------------------------------- dublês
    internal sealed class UsuariosFake : IUsuarioRepositorio
    {
        public string Hash { get; private set; } = "hash:Cliente@2026";
        public int Versao { get; private set; } = 1;
        public bool HashAntigo { get; set; }
        public bool Ativo { get; set; } = true;
        public string Perfil { get; set; } = "Cliente";
        public int Falhas { get; private set; }
        private DateTime? _bloqueadoAte;
        public List<(string Email, bool Sucesso, string? Ip, string Detalhe)> Log { get; } = new();

        public void BloquearAte(DateTime data) => _bloqueadoAte = data;

        private Usuario Matheus() => new(2, "Matheus Sigoli", "matheus@estudante.com",
            HashAntigo ? "antigo:" + Hash : Hash, PerfilUsuario.Cliente, true,
            _bloqueadoAte > DateTime.Now ? _bloqueadoAte : null, Versao);

        public Task<Usuario?> ObterPorEmailAsync(string email) =>
            Task.FromResult(email == "matheus@estudante.com" ? Matheus() : null);

        public Task<Usuario?> ObterPorIdAsync(int id) => Task.FromResult(id == 2 ? Matheus() : null);

        // Mesma regra da sp_RegistrarTentativaLogin
        public Task<DateTime?> RegistrarTentativaLoginAsync(string email, bool sucesso, string? ip, string detalhe)
        {
            Log.Add((email, sucesso, ip, detalhe));
            if (email != "matheus@estudante.com") return Task.FromResult<DateTime?>(null);
            if (sucesso) { Falhas = 0; _bloqueadoAte = null; }
            else if (!(_bloqueadoAte > DateTime.Now) && ++Falhas >= Usuario.MaxTentativasLogin)
            {
                Falhas = 0;
                _bloqueadoAte = DateTime.Now.AddMinutes(Usuario.MinutosBloqueio);
            }
            return Task.FromResult(_bloqueadoAte > DateTime.Now ? _bloqueadoAte : null);
        }

        public Task<int> AtualizarSenhaAsync(int usuarioId, string novoHash) { Hash = novoHash; return Task.FromResult(++Versao); }
        public Task AtualizarHashAsync(int usuarioId, string novoHash) { Hash = novoHash; HashAntigo = false; return Task.CompletedTask; }
        public Task<int> RevogarSessoesAsync(int usuarioId) => Task.FromResult(++Versao);
        public Task<EstadoSessao?> ObterEstadoSessaoAsync(int usuarioId) =>
            Task.FromResult<EstadoSessao?>(usuarioId == 2 ? new EstadoSessao(Ativo, Perfil, Versao) : null);
        public Task<bool> EmailExisteAsync(string email) => Task.FromResult(false);
        public Task<int> InserirAsync(Usuario usuario) => Task.FromResult(99);
    }

    private sealed class HasherFake : IHasherSenha
    {
        public string GerarHash(string senha) => "hash:" + senha;
        public bool Verificar(string senha, string hash) => hash.EndsWith("hash:" + senha);
        public bool PrecisaAtualizar(string hash) => hash.StartsWith("antigo:");
    }

    private sealed class TokenFake : IGeradorToken
    {
        public (string Token, DateTime ExpiraEm) Gerar(Usuario usuario) =>
            (usuario.VersaoToken == 1 ? $"token-{usuario.Id}" : $"token-{usuario.Id}-v{usuario.VersaoToken}", DateTime.Now.AddHours(8));
    }
}

public class CacheCatalogoTests
{
    private static CacheCatalogo NovoCache() => new(new MemoryCache(new MemoryCacheOptions { SizeLimit = 100 }));

    [Fact]
    public async Task Segunda_consulta_vem_do_cache_e_invalidar_recarrega()
    {
        var cache = NovoCache();
        var cargas = 0;
        Task<int> Carregar() => Task.FromResult(++cargas);

        Assert.Equal(1, await cache.ObterAsync("lista", Carregar));
        Assert.Equal(1, await cache.ObterAsync("lista", Carregar));   // não foi ao banco

        cache.Invalidar();                                              // ex.: pedido baixou o estoque
        Assert.Equal(2, await cache.ObterAsync("lista", Carregar));
    }

    [Fact]
    public async Task Catalogo_normaliza_filtro_e_reaproveita_a_consulta()
    {
        var repo = new ProdutosContador();
        var servico = new CatalogoServico(repo, NovoCache());

        await servico.ListarAsync(new FiltroProdutos("chuteiras", null, null, null, null, "Nike", null));
        await servico.ListarAsync(new FiltroProdutos(" chuteiras ", "", " ", null, null, " nike ", null));

        Assert.Equal(1, repo.Listagens);
        Assert.Equal("Nike", repo.UltimoFiltro!.Marca);
    }

    [Fact]
    public async Task Filtros_invalidos_sao_recusados()
    {
        var servico = new CatalogoServico(new ProdutosContador());
        await Assert.ThrowsAsync<RegraNegocioException>(() =>
            servico.ListarAsync(new FiltroProdutos(null, null, null, null, null, new string('x', 41), null)));
        await Assert.ThrowsAsync<RegraNegocioException>(() =>
            servico.ListarAsync(new FiltroProdutos(null, null, null, null, null, null, -1m)));
    }

    [Fact]
    public async Task Marca_e_solado_so_sao_gravados_em_chuteiras()
    {
        var repo = new ProdutosContador();
        var servico = new CatalogoServico(repo);

        await servico.CriarAsync(new SalvarProdutoRequest(3, "Nike Phantom FG", "", "Campo", null, null, "Chuteira de campo",
            849.90m, null, "", false, null, "Nike", "FG — campo"));
        Assert.Equal("Nike", repo.Gravado!.Marca);
        Assert.Equal("FG — campo", repo.Gravado.Solado);

        await servico.CriarAsync(new SalvarProdutoRequest(1, "Camisa Brasil 2026 Home", "", "Seleção", "Brasil", 2026,
            "Camisa", 349.90m, null, "", false, null, "Nike", "FG — campo"));
        Assert.Null(repo.Gravado!.Marca);
        Assert.Null(repo.Gravado.Solado);
    }

    private sealed class ProdutosContador : IProdutoRepositorio
    {
        public int Listagens { get; private set; }
        public FiltroProdutos? UltimoFiltro { get; private set; }
        public Produto? Gravado { get; private set; }

        public Task<IReadOnlyList<ProdutoResumoResponse>> ListarAsync(FiltroProdutos filtro)
        {
            Listagens++;
            UltimoFiltro = filtro;
            return Task.FromResult<IReadOnlyList<ProdutoResumoResponse>>(Array.Empty<ProdutoResumoResponse>());
        }

        public Task<string?> ObterSlugCategoriaAsync(int categoriaId) =>
            Task.FromResult<string?>(categoriaId == 3 ? "chuteiras" : "temporada-2026");

        public Task<int> InserirAsync(Produto produto, IReadOnlyList<string> imagens) { Gravado = produto; return Task.FromResult(37); }

        public Task<IReadOnlyList<CategoriaResponse>> ListarCategoriasAsync() => throw new NotImplementedException();
        public Task<ProdutoResumoResponse?> ObterResumoAsync(int id) => throw new NotImplementedException();
        public Task<IReadOnlyList<string>> ListarImagensAsync(int produtoId) => throw new NotImplementedException();
        public Task<IReadOnlyList<TamanhoEstoqueResponse>> ListarTamanhosAsync(int produtoId) => throw new NotImplementedException();
        public Task<IReadOnlyList<AvaliacaoResponse>> ListarAvaliacoesAsync(int produtoId) => throw new NotImplementedException();
        public Task RegistrarAvaliacaoAsync(int produtoId, int usuarioId, int nota, string? comentario, string status) => throw new NotImplementedException();
        public Task AtualizarAsync(Produto produto, IReadOnlyList<string>? imagens) => throw new NotImplementedException();
        public Task<bool> DesativarAsync(int id) => throw new NotImplementedException();
    }
}

/// <summary>Token com assinatura válida, mas que o banco já não aceita.</summary>
public class ValidadorSessaoTests
{
    private static ClaimsPrincipal Token(string perfil, int versao) => new(new ClaimsIdentity(new[]
    {
        new Claim(ClaimTypes.NameIdentifier, "2"),
        new Claim(ClaimTypes.Role, perfil),
        new Claim(ValidadorSessao.ClaimVersao, versao.ToString())
    }, "teste"));

    private static (ValidadorSessao, BloqueioLoginTests.UsuariosFake) Criar()
    {
        var repo = new BloqueioLoginTests.UsuariosFake();
        return (new ValidadorSessao(repo, new MemoryCache(new MemoryCacheOptions { SizeLimit = 100 })), repo);
    }

    [Fact]
    public async Task Token_atual_e_aceito()
    {
        var (validador, _) = Criar();
        Assert.Null(await validador.ValidarAsync(Token("Cliente", 1)));
    }

    [Fact]
    public async Task Token_antigo_cai_depois_de_sair_de_todos()
    {
        var (validador, repo) = Criar();
        Assert.Null(await validador.ValidarAsync(Token("Cliente", 1)));
        await repo.RevogarSessoesAsync(2);
        validador.Invalidar(2);
        Assert.Equal("Sessão encerrada. Entre novamente.", await validador.ValidarAsync(Token("Cliente", 1)));
        Assert.Null(await validador.ValidarAsync(Token("Cliente", 2)));
    }

    [Fact]
    public async Task Admin_rebaixado_e_conta_desativada_perdem_o_acesso()
    {
        var (validador, repo) = Criar();
        Assert.NotNull(await validador.ValidarAsync(Token("Admin", 1)));      // banco diz Cliente
        repo.Ativo = false;
        validador.Invalidar(2);
        Assert.Equal("Conta inexistente ou desativada.", await validador.ValidarAsync(Token("Cliente", 1)));
    }

    [Fact]
    public async Task Token_sem_versao_e_recusado()
    {
        var (validador, _) = Criar();
        var semVersao = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, "2") }, "teste"));
        Assert.NotNull(await validador.ValidarAsync(semVersao));
    }
}
