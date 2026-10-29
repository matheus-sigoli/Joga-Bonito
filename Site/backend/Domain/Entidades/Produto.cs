using JogaBonito.Api.Domain.Excecoes;

namespace JogaBonito.Api.Domain.Entidades;

/// <summary>
/// Produto do catálogo (classe abstrata). Camisas e chuteiras compartilham preço,
/// imagens e estoque, mas cada tipo define sua própria grade de tamanhos e as linhas
/// permitidas — exemplo de herança e polimorfismo aplicado ao negócio.
/// </summary>
public abstract class Produto : EntidadeBase
{
    public int CategoriaId { get; set; }
    public string Nome { get; set; } = string.Empty;
    public string Modelo { get; set; } = string.Empty;
    public string Linha { get; set; } = string.Empty;
    public string? Equipe { get; set; }
    public int? Ano { get; set; }
    public string? Marca { get; set; }    // chuteiras: Nike, adidas...
    public string? Solado { get; set; }   // chuteiras: "FG — campo", "TF — society", "IC — quadra"
    public string Descricao { get; set; } = string.Empty;
    public decimal Preco { get; set; }
    public decimal? PrecoPromocional { get; set; }
    public string Imagem { get; set; } = string.Empty;
    public bool Destaque { get; set; }

    /// <summary>Tamanhos vendidos para este tipo de produto.</summary>
    public abstract IReadOnlyList<string> GradeTamanhos { get; }

    /// <summary>Linhas aceitas para este tipo (Clube/Seleção ou Campo/Society/Futsal).</summary>
    public abstract IReadOnlyList<string> LinhasPermitidas { get; }

    public abstract string Tipo { get; }

    public decimal PrecoFinal => PrecoPromocional ?? Preco;

    public bool EmPromocao => PrecoPromocional.HasValue && PrecoPromocional < Preco;

    public int PercentualDesconto =>
        EmPromocao ? (int)Math.Round((1 - PrecoPromocional!.Value / Preco) * 100) : 0;

    public bool TamanhoValido(string tamanho) =>
        GradeTamanhos.Contains((tamanho ?? string.Empty).Trim().ToUpperInvariant());

    /// <summary>Valida o produto antes de gravar (usado no cadastro do painel admin).</summary>
    public virtual void Validar()
    {
        if (string.IsNullOrWhiteSpace(Nome) || Nome.Length > 100)
            throw new RegraNegocioException("Nome do produto é obrigatório (até 100 caracteres).");
        if (string.IsNullOrWhiteSpace(Descricao))
            throw new RegraNegocioException("Descrição do produto é obrigatória.");
        if (Preco <= 0)
            throw new RegraNegocioException("O preço deve ser maior que zero.");
        if (PrecoPromocional.HasValue && (PrecoPromocional <= 0 || PrecoPromocional >= Preco))
            throw new RegraNegocioException("O preço promocional deve ser menor que o preço normal.");
        if (!LinhasPermitidas.Contains(Linha))
            throw new RegraNegocioException($"Linha inválida para {Tipo}. Use: {string.Join(", ", LinhasPermitidas)}.");
        if (Marca is { Length: > 40 } || Solado is { Length: > 40 })
            throw new RegraNegocioException("Marca e tipo de solado podem ter no máximo 40 caracteres.");
    }
}

/// <summary>Camisas (Temporada 2026 e Retrô). Preço mínimo de venda: R$ 160,00.</summary>
public class Camisa : Produto
{
    public const decimal PrecoMinimo = 160m;
    private static readonly string[] Grade = { "P", "M", "G", "GG", "XG" };
    private static readonly string[] Linhas = { "Clube", "Seleção" };

    public override IReadOnlyList<string> GradeTamanhos => Grade;
    public override IReadOnlyList<string> LinhasPermitidas => Linhas;
    public override string Tipo => "Camisa";

    public override void Validar()
    {
        base.Validar();
        if (PrecoFinal < PrecoMinimo)
            throw new RegraNegocioException($"Camisas não podem ser vendidas abaixo de {PrecoMinimo:C}.");
    }
}

/// <summary>Chuteiras de campo, society e futsal. Preço mínimo de venda: R$ 250,00.</summary>
public class Chuteira : Produto
{
    public const decimal PrecoMinimo = 250m;
    private static readonly string[] Grade = { "37", "38", "39", "40", "41", "42", "43", "44" };
    private static readonly string[] Linhas = { "Campo", "Society", "Futsal" };

    public override IReadOnlyList<string> GradeTamanhos => Grade;
    public override IReadOnlyList<string> LinhasPermitidas => Linhas;
    public override string Tipo => "Chuteira";

    public override void Validar()
    {
        base.Validar();
        if (PrecoFinal < PrecoMinimo)
            throw new RegraNegocioException($"Chuteiras não podem ser vendidas abaixo de {PrecoMinimo:C}.");
    }
}

/// <summary>Fábrica que escolhe a subclasse correta a partir da linha do produto.</summary>
public static class ProdutoFactory
{
    public static Produto CriarPorLinha(string linha) => linha switch
    {
        "Campo" or "Society" or "Futsal" => new Chuteira { Linha = linha },
        "Clube" or "Seleção" => new Camisa { Linha = linha },
        _ => throw new RegraNegocioException("Linha de produto desconhecida.")
    };
}
