using JogaBonito.Api.Domain.Excecoes;

namespace JogaBonito.Api.Domain.Entidades;

/// <summary>Ciclo de vida do pedido.</summary>
public enum StatusPedido
{
    AguardandoPagamento,
    Pago,
    EmSeparacao,
    Enviado,
    Entregue,
    Cancelado
}

/// <summary>Conversão entre o enum e o texto gravado no banco + regras de transição.</summary>
public static class StatusPedidoRegras
{
    private static readonly Dictionary<StatusPedido, string> Textos = new()
    {
        [StatusPedido.AguardandoPagamento] = "Aguardando Pagamento",
        [StatusPedido.Pago] = "Pago",
        [StatusPedido.EmSeparacao] = "Em Separação",
        [StatusPedido.Enviado] = "Enviado",
        [StatusPedido.Entregue] = "Entregue",
        [StatusPedido.Cancelado] = "Cancelado"
    };

    public static string ParaTexto(this StatusPedido status) => Textos[status];

    public static StatusPedido DeTexto(string? texto)
    {
        foreach (var (status, descricao) in Textos)
            if (string.Equals(descricao, texto?.Trim(), StringComparison.OrdinalIgnoreCase))
                return status;
        throw new RegraNegocioException($"Status de pedido desconhecido: '{texto}'.");
    }

    public static IEnumerable<string> TodosTextos => Textos.Values;

    /// <summary>Um pedido só anda para frente; cancela-se apenas antes do envio.</summary>
    public static bool PodeMudarPara(this StatusPedido atual, StatusPedido novo)
    {
        if (atual is StatusPedido.Entregue or StatusPedido.Cancelado) return false;
        if (novo == StatusPedido.Cancelado) return atual is not StatusPedido.Enviado;
        return (int)novo > (int)atual;
    }

    /// <summary>O próprio cliente só cancela enquanto o pedido não entrou em separação.</summary>
    public static bool ClientePodeCancelar(this StatusPedido atual) =>
        atual is StatusPedido.AguardandoPagamento or StatusPedido.Pago;
}

/// <summary>Regra de frete da loja (espelhada na função dbo.fn_CalcularFrete).</summary>
public static class RegraFrete
{
    public const decimal LimiteFreteGratis = 299.00m;
    public const decimal ValorFrete = 19.90m;

    public static decimal Calcular(decimal valorProdutos) =>
        valorProdutos <= 0 || valorProdutos >= LimiteFreteGratis ? 0m : ValorFrete;
}

/// <summary>
/// Programa social Joga Junto: 1% do valor dos produtos (com desconto, sem frete) de cada
/// pedido é destinado a escolinhas de futebol. Mesma regra de dbo.fn_CalcularJogaJunto.
/// </summary>
public static class RegraJogaJunto
{
    public const decimal Percentual = 0.01m;

    public static decimal Calcular(decimal valorProdutos) =>
        valorProdutos <= 0 ? 0m : Math.Round(valorProdutos * Percentual, 2, MidpointRounding.AwayFromZero);
}

/// <summary>Cupom de desconto percentual.</summary>
public class Cupom : EntidadeBase
{
    public string Codigo { get; init; } = string.Empty;
    public decimal Percentual { get; init; }
    public decimal ValorMinimo { get; init; }
    public DateTime? ValidoAte { get; init; }
    public bool Ativo { get; init; } = true;

    public bool Vigente(DateTime hoje) => Ativo && (ValidoAte is null || ValidoAte.Value.Date >= hoje.Date);

    public decimal CalcularDesconto(decimal subtotal, DateTime hoje)
    {
        if (!Vigente(hoje)) throw new RegraNegocioException("Cupom inválido ou expirado.");
        if (subtotal < ValorMinimo)
            throw new RegraNegocioException($"Este cupom vale para compras a partir de {ValorMinimo:C}.");
        return Math.Round(subtotal * Percentual / 100m, 2, MidpointRounding.AwayFromZero);
    }
}

/// <summary>Item de um pedido (preço congelado no momento da compra).</summary>
public class ItemPedido
{
    public int ProdutoId { get; init; }
    public string Nome { get; init; } = string.Empty;
    public string Imagem { get; init; } = string.Empty;
    public string Tamanho { get; init; } = string.Empty;
    public int Quantidade { get; init; }
    public decimal PrecoUnitario { get; init; }
    public decimal Subtotal => PrecoUnitario * Quantidade;
}

/// <summary>
/// Agregado Pedido: calcula subtotal, desconto, frete e total a partir dos itens.
/// Usado para simular o checkout; a gravação definitiva é feita pela
/// procedure sp_RegistrarPedido, que repete os cálculos dentro da transação.
/// </summary>
public class Pedido : EntidadeBase
{
    public const int MaximoPorItem = 10;
    private readonly List<ItemPedido> _itens = new();

    public IReadOnlyList<ItemPedido> Itens => _itens;
    public Cupom? Cupom { get; private set; }
    public decimal Desconto { get; private set; }

    public decimal Subtotal => _itens.Sum(i => i.Subtotal);
    public decimal Frete => RegraFrete.Calcular(Subtotal - Desconto);
    public decimal Total => Subtotal - Desconto + Frete;
    public decimal ValorJogaJunto => RegraJogaJunto.Calcular(Subtotal - Desconto);

    public void AdicionarItem(ItemPedido item)
    {
        if (item.Quantidade <= 0 || item.Quantidade > MaximoPorItem)
            throw new RegraNegocioException($"Quantidade inválida para {item.Nome} (1 a {MaximoPorItem}).");

        var existente = _itens.FirstOrDefault(i => i.ProdutoId == item.ProdutoId && i.Tamanho == item.Tamanho);
        if (existente is not null)
        {
            _itens.Remove(existente);
            item = new ItemPedido
            {
                ProdutoId = item.ProdutoId, Nome = item.Nome, Imagem = item.Imagem, Tamanho = item.Tamanho,
                PrecoUnitario = item.PrecoUnitario, Quantidade = existente.Quantidade + item.Quantidade
            };
            if (item.Quantidade > MaximoPorItem)
                throw new RegraNegocioException($"Máximo de {MaximoPorItem} unidades por item.");
        }
        _itens.Add(item);
        RecalcularDesconto();
    }

    public void AplicarCupom(Cupom cupom, DateTime hoje)
    {
        if (_itens.Count == 0) throw new RegraNegocioException("Adicione itens antes de aplicar um cupom.");
        Desconto = cupom.CalcularDesconto(Subtotal, hoje);
        Cupom = cupom;
    }

    private void RecalcularDesconto()
    {
        if (Cupom is not null) Desconto = Math.Round(Subtotal * Cupom.Percentual / 100m, 2, MidpointRounding.AwayFromZero);
    }
}
