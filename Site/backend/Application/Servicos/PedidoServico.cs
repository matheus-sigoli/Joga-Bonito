using System.Text.RegularExpressions;
using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Domain.Entidades;
using JogaBonito.Api.Domain.Excecoes;

namespace JogaBonito.Api.Application.Servicos;

/// <summary>Checkout (simulação e fechamento), histórico e gestão de pedidos.</summary>
public class PedidoServico
{
    public static readonly string[] FormasPagamento = { "PIX", "Cartão de Crédito", "Cartão de Débito" };
    private static readonly string[] Ufs =
    {
        "AC","AL","AP","AM","BA","CE","DF","ES","GO","MA","MT","MS","MG","PA","PB","PR",
        "PE","PI","RJ","RN","RS","RO","RR","SC","SP","SE","TO"
    };

    private readonly IPedidoRepositorio _pedidos;
    private readonly IProdutoRepositorio _produtos;
    private readonly TimeProvider _relogio;
    private readonly ICacheCatalogo _cache;

    public PedidoServico(IPedidoRepositorio pedidos, IProdutoRepositorio produtos, TimeProvider relogio,
        ICacheCatalogo? cache = null)
    {
        _pedidos = pedidos;
        _produtos = produtos;
        _relogio = relogio;
        _cache = cache ?? new SemCacheCatalogo();
    }

    /// <summary>Calcula o resumo do carrinho com preços oficiais, cupom e frete (sem gravar).</summary>
    public async Task<ResumoPedidoResponse> SimularAsync(SimularPedidoRequest request)
    {
        var pedido = await MontarPedidoAsync(request.Itens);

        if (!string.IsNullOrWhiteSpace(request.Cupom))
        {
            var cupom = await _pedidos.ObterCupomAsync(request.Cupom)
                        ?? throw new RegraNegocioException("Cupom inválido ou expirado.");
            pedido.AplicarCupom(cupom, _relogio.GetLocalNow().DateTime);
        }

        return new ResumoPedidoResponse(
            pedido.Itens.Select(i => new ItemPedidoResponse(i.ProdutoId, i.Nome, i.Imagem, i.Tamanho,
                i.Quantidade, i.PrecoUnitario, i.Subtotal)).ToList(),
            pedido.Subtotal, pedido.Desconto, pedido.Frete, pedido.Total, pedido.Cupom?.Codigo, pedido.ValorJogaJunto);
    }

    public async Task<ValidarCupomResponse> ValidarCupomAsync(ValidarCupomRequest request)
    {
        var codigo = (request.Codigo ?? string.Empty).Trim().ToUpperInvariant();
        var cupom = await _pedidos.ObterCupomAsync(codigo);
        if (cupom is null)
            return new ValidarCupomResponse(false, codigo, 0, 0, "Cupom inválido ou expirado.");
        try
        {
            var desconto = cupom.CalcularDesconto(request.Subtotal, _relogio.GetLocalNow().DateTime);
            return new ValidarCupomResponse(true, cupom.Codigo, cupom.Percentual, desconto,
                $"Cupom aplicado: {cupom.Percentual:0.#}% de desconto.");
        }
        catch (RegraNegocioException ex)
        {
            return new ValidarCupomResponse(false, codigo, cupom.Percentual, 0, ex.Message);
        }
    }

    /// <summary>Fecha o pedido. A gravação é atômica na procedure sp_RegistrarPedido.</summary>
    public async Task<PedidoCriadoResponse> CriarAsync(int usuarioId, CriarPedidoRequest request)
    {
        if (!FormasPagamento.Contains(request.FormaPagamento))
            throw new RegraNegocioException("Forma de pagamento inválida.");

        var parcelas = request.FormaPagamento == "Cartão de Crédito" ? request.Parcelas : 1;
        if (parcelas is < 1 or > 6)
            throw new RegraNegocioException("Parcelamento permitido: de 1 a 6 vezes sem juros.");

        // Valida itens e tamanhos antes de abrir a transação no banco
        await MontarPedidoAsync(request.Itens);

        int? enderecoId = null;
        if (request.Endereco is not null)
        {
            ValidarEndereco(request.Endereco);
            enderecoId = await _pedidos.InserirEnderecoAsync(usuarioId, request.Endereco);
        }

        var origem = string.Equals(request.Origem, "Mobile", StringComparison.OrdinalIgnoreCase) ? "Mobile" : "Web";
        var criado = await _pedidos.RegistrarAsync(usuarioId,
            request with { Parcelas = parcelas, Origem = origem, Cupom = request.Cupom?.Trim().ToUpperInvariant() },
            enderecoId);
        _cache.Invalidar(); // a trigger baixou o estoque: a vitrine precisa refletir
        return criado;
    }

    public Task<IReadOnlyList<PedidoResponse>> MeusPedidosAsync(int usuarioId) =>
        _pedidos.ListarPorUsuarioAsync(usuarioId);

    public async Task<PedidoResponse> ObterAsync(int pedidoId, int usuarioId, bool ehAdmin)
    {
        var pedido = await _pedidos.ObterAsync(pedidoId)
                     ?? throw new RecursoNaoEncontradoException("Pedido não encontrado.");
        if (!ehAdmin && await _pedidos.ObterDonoAsync(pedidoId) != usuarioId)
            // 404, e não 403: não confirma para um curioso que o pedido de outra pessoa existe
            throw new RecursoNaoEncontradoException("Pedido não encontrado.");
        return pedido;
    }

    public async Task CancelarPeloClienteAsync(int pedidoId, int usuarioId)
    {
        var pedido = await ObterAsync(pedidoId, usuarioId, ehAdmin: false);
        if (!StatusPedidoRegras.DeTexto(pedido.Status).ClientePodeCancelar())
            throw new RegraNegocioException("Este pedido já está em separação e não pode ser cancelado pelo site. Fale com o atendimento.");
        await _pedidos.AtualizarStatusAsync(pedidoId, StatusPedido.Cancelado.ParaTexto());
        _cache.Invalidar(); // cancelamento devolve o estoque
    }

    public Task<IReadOnlyList<PedidoResponse>> ListarTodosAsync(string? status) =>
        _pedidos.ListarTodosAsync(string.IsNullOrWhiteSpace(status) ? null : StatusPedidoRegras.DeTexto(status).ParaTexto(), 200);

    public async Task AtualizarStatusAsync(int pedidoId, string novoStatusTexto)
    {
        var pedido = await _pedidos.ObterAsync(pedidoId)
                     ?? throw new RecursoNaoEncontradoException("Pedido não encontrado.");
        var atual = StatusPedidoRegras.DeTexto(pedido.Status);
        var novo = StatusPedidoRegras.DeTexto(novoStatusTexto);
        if (!atual.PodeMudarPara(novo))
            throw new RegraNegocioException($"Não é possível mudar de '{atual.ParaTexto()}' para '{novo.ParaTexto()}'.");
        await _pedidos.AtualizarStatusAsync(pedidoId, novo.ParaTexto());
        if (novo == StatusPedido.Cancelado) _cache.Invalidar();
    }

    // ---------------------------------------------------------------------

    private async Task<Pedido> MontarPedidoAsync(IReadOnlyList<ItemCarrinhoRequest>? itens)
    {
        if (itens is null || itens.Count == 0)
            throw new RegraNegocioException("Seu carrinho está vazio.");
        if (itens.Count > 30)
            throw new RegraNegocioException("Limite de 30 itens diferentes por pedido.");

        var pedido = new Pedido();
        foreach (var item in itens)
        {
            var produto = await _produtos.ObterResumoAsync(item.ProdutoId)
                          ?? throw new RegraNegocioException($"Produto {item.ProdutoId} não está disponível.");

            var tipo = ProdutoFactory.CriarPorLinha(produto.Linha);
            var tamanho = (item.Tamanho ?? string.Empty).Trim().ToUpperInvariant();
            if (!tipo.TamanhoValido(tamanho))
                throw new RegraNegocioException($"Tamanho '{item.Tamanho}' inválido para {produto.Nome}.");

            var estoque = (await _produtos.ListarTamanhosAsync(produto.Id))
                .FirstOrDefault(t => t.Tamanho == tamanho)?.Quantidade ?? 0;
            if (estoque < item.Quantidade)
                throw new RegraNegocioException(estoque == 0
                    ? $"{produto.Nome} ({tamanho}) está esgotado."
                    : $"Restam apenas {estoque} unidade(s) de {produto.Nome} ({tamanho}).");

            pedido.AdicionarItem(new ItemPedido
            {
                ProdutoId = produto.Id, Nome = produto.Nome, Imagem = produto.Img,
                Tamanho = tamanho, Quantidade = item.Quantidade, PrecoUnitario = produto.PrecoFinal
            });
        }
        return pedido;
    }

    private static void ValidarEndereco(EnderecoRequest e)
    {
        var cep = Regex.Replace(e.Cep ?? string.Empty, @"\D", "");
        if (cep.Length != 8) throw new RegraNegocioException("CEP inválido.");
        if (string.IsNullOrWhiteSpace(e.Rua) || string.IsNullOrWhiteSpace(e.Numero)
            || string.IsNullOrWhiteSpace(e.Bairro) || string.IsNullOrWhiteSpace(e.Cidade))
            throw new RegraNegocioException("Preencha o endereço completo de entrega.");
        if (!Ufs.Contains((e.Estado ?? string.Empty).ToUpperInvariant()))
            throw new RegraNegocioException("UF inválida.");
    }
}
