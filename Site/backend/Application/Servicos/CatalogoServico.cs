using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Domain.Entidades;
using JogaBonito.Api.Domain.Excecoes;

namespace JogaBonito.Api.Application.Servicos;

/// <summary>Consulta do catálogo (com cache curto), avaliações e manutenção de produtos.</summary>
public class CatalogoServico
{
    private readonly IProdutoRepositorio _produtos;
    private readonly ICacheCatalogo _cache;
    private readonly IReadOnlyList<string> _termosBloqueados;

    public CatalogoServico(IProdutoRepositorio produtos, ICacheCatalogo? cache = null,
        IReadOnlyList<string>? termosBloqueados = null)
    {
        _produtos = produtos;
        _cache = cache ?? new SemCacheCatalogo();
        _termosBloqueados = termosBloqueados ?? Array.Empty<string>();
    }

    public Task<IReadOnlyList<CategoriaResponse>> CategoriasAsync() =>
        _cache.ObterAsync("categorias", () => _produtos.ListarCategoriasAsync());

    public Task<IReadOnlyList<ProdutoResumoResponse>> ListarAsync(FiltroProdutos filtro)
    {
        if (filtro.Busca is { Length: > 60 })
            throw new RegraNegocioException("Termo de busca muito longo.");
        if (filtro.Marca is { Length: > 40 })
            throw new RegraNegocioException("Marca inválida.");
        if (filtro.PrecoMax is <= 0)
            throw new RegraNegocioException("O preço máximo deve ser maior que zero.");

        // Normaliza para que "Nike" e " nike " usem a mesma entrada do cache
        var f = filtro with
        {
            Categoria = Normalizar(filtro.Categoria), Linha = Normalizar(filtro.Linha),
            Busca = Normalizar(filtro.Busca), Ordem = Normalizar(filtro.Ordem), Marca = Normalizar(filtro.Marca)
        };
        return _cache.ObterAsync($"lista:{f}".ToLowerInvariant(), () => _produtos.ListarAsync(f));
    }

    private static string? Normalizar(string? texto) => string.IsNullOrWhiteSpace(texto) ? null : texto.Trim();

    /// <summary>Descarta o cache da vitrine (chamado após pedidos e ajustes de estoque).</summary>
    public void InvalidarCache() => _cache.Invalidar();

    public Task<ProdutoDetalheResponse> DetalharAsync(int id) =>
        _cache.ObterAsync($"produto:{id}", () => CarregarDetalheAsync(id));

    private async Task<ProdutoDetalheResponse> CarregarDetalheAsync(int id)
    {
        var resumo = await _produtos.ObterResumoAsync(id)
                     ?? throw new RecursoNaoEncontradoException("Produto não encontrado.");

        var imagens = await _produtos.ListarImagensAsync(id);
        var tamanhos = await _produtos.ListarTamanhosAsync(id);
        var tipo = ProdutoFactory.CriarPorLinha(resumo.Linha);

        // Garante a grade completa na ordem certa, mesmo para tamanhos sem registro de estoque
        var grade = tipo.GradeTamanhos
            .Select(t => tamanhos.FirstOrDefault(x => x.Tamanho == t) ?? new TamanhoEstoqueResponse(t, 0))
            .ToList();

        return new ProdutoDetalheResponse(resumo, tipo.Tipo,
            imagens.Count > 0 ? imagens : new List<string> { resumo.Img }, grade);
    }

    public async Task<IReadOnlyList<AvaliacaoResponse>> AvaliacoesAsync(int produtoId)
    {
        _ = await _produtos.ObterResumoAsync(produtoId)
            ?? throw new RecursoNaoEncontradoException("Produto não encontrado.");
        return await _produtos.ListarAvaliacoesAsync(produtoId);
    }

    public async Task<AvaliacaoEnviadaResponse> AvaliarAsync(int produtoId, int usuarioId, AvaliacaoRequest request)
    {
        if (request.Nota is < 1 or > 5)
            throw new RegraNegocioException("A nota deve ser de 1 a 5 estrelas.");
        var comentario = request.Comentario?.Trim();
        if (comentario is { Length: > 500 })
            throw new RegraNegocioException("O comentário pode ter no máximo 500 caracteres.");
        var status = ModeracaoAvaliacao.StatusInicial(comentario, _termosBloqueados);
        await _produtos.RegistrarAvaliacaoAsync(produtoId, usuarioId, request.Nota,
            string.IsNullOrEmpty(comentario) ? null : comentario, status);
        _cache.Invalidar(); // nota média da vitrine mudou
        return status == ModeracaoAvaliacao.Publicada
            ? new AvaliacaoEnviadaResponse(status, "Obrigado pela avaliação!")
            : new AvaliacaoEnviadaResponse(status, "Recebemos sua avaliação. Ela aparece na loja depois de revisada pela equipe.");
    }

    // ---------------- Administração ----------------

    public async Task<int> CriarAsync(SalvarProdutoRequest request)
    {
        var produto = await MontarAsync(request);
        var imagens = ValidarImagens(request.Imagens) ?? new List<string>();
        if (imagens.Count == 0) imagens.Add(produto.Imagem);
        var id = await _produtos.InserirAsync(produto, imagens);
        _cache.Invalidar();
        return id;
    }

    public async Task AtualizarAsync(int id, SalvarProdutoRequest request)
    {
        _ = await _produtos.ObterResumoAsync(id) ?? throw new RecursoNaoEncontradoException("Produto não encontrado.");
        var produto = await MontarAsync(request);
        produto.Id = id;
        await _produtos.AtualizarAsync(produto, ValidarImagens(request.Imagens));
        _cache.Invalidar();
    }

    public async Task DesativarAsync(int id)
    {
        if (!await _produtos.DesativarAsync(id))
            throw new RecursoNaoEncontradoException("Produto não encontrado.");
        _cache.Invalidar();
    }

    /// <summary>
    /// Imagens só de dentro da pasta IMG do site: sem URL externa (rastreamento, conteúdo trocado depois),
    /// sem "javascript:"/"data:" e sem "../../" para sair da pasta.
    /// </summary>
    public static string ValidarImagem(string caminho)
    {
        var c = caminho.Trim().Replace('\\', '/');
        if (c.Length > 200 || !System.Text.RegularExpressions.Regex.IsMatch(c,
                @"^\.\./IMG/[A-Za-z0-9 _/-]{1,180}\.(jpg|jpeg|png|webp|svg)$", System.Text.RegularExpressions.RegexOptions.IgnoreCase)
            || c.Contains("//", StringComparison.Ordinal) || c[7..].Contains("..", StringComparison.Ordinal))
            throw new RegraNegocioException("Imagem inválida: use um arquivo da pasta IMG, por exemplo ../IMG/Produtos/37/1.jpg.");
        return c;
    }

    private static List<string>? ValidarImagens(IEnumerable<string>? imagens) =>
        imagens?.Where(i => !string.IsNullOrWhiteSpace(i)).Take(12).Select(ValidarImagem).ToList();

    private async Task<Produto> MontarAsync(SalvarProdutoRequest r)
    {
        var slug = await _produtos.ObterSlugCategoriaAsync(r.CategoriaId)
                   ?? throw new RegraNegocioException("Categoria inválida.");

        var produto = ProdutoFactory.CriarPorLinha(r.Linha);
        if ((slug == "chuteiras") != (produto is Chuteira))
            throw new RegraNegocioException("A linha escolhida não combina com a categoria.");

        produto.CategoriaId = r.CategoriaId;
        produto.Nome = r.Nome?.Trim() ?? string.Empty;
        produto.Modelo = string.IsNullOrWhiteSpace(r.Modelo) ? produto.Tipo : r.Modelo.Trim();
        produto.Equipe = string.IsNullOrWhiteSpace(r.Equipe) ? null : r.Equipe.Trim();
        produto.Ano = r.Ano;
        // Marca e solado só fazem sentido para chuteiras
        produto.Marca = produto is Chuteira && !string.IsNullOrWhiteSpace(r.Marca) ? r.Marca.Trim() : null;
        produto.Solado = produto is Chuteira && !string.IsNullOrWhiteSpace(r.Solado) ? r.Solado.Trim() : null;
        produto.Descricao = r.Descricao?.Trim() ?? string.Empty;
        produto.Preco = r.Preco;
        produto.PrecoPromocional = r.PrecoPromocional;
        produto.Imagem = string.IsNullOrWhiteSpace(r.Imagem) ? "../IMG/LOGO 2.png" : ValidarImagem(r.Imagem);
        produto.Destaque = r.Destaque;
        produto.Validar();
        return produto;
    }
}

/// <summary>Sem cache: usado quando nenhum cache é injetado (ex.: testes unitários).</summary>
internal sealed class SemCacheCatalogo : ICacheCatalogo
{
    public Task<T> ObterAsync<T>(string chave, Func<Task<T>> carregar) => carregar();
    public void Invalidar() { }
}
