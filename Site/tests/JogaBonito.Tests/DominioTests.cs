using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Application.Servicos;
using JogaBonito.Api.Domain.Entidades;
using JogaBonito.Api.Domain.Excecoes;
using Xunit;

namespace JogaBonito.Tests;

public class RegraFreteTests
{
    [Theory]
    [InlineData(100.00, 19.90)]
    [InlineData(298.99, 19.90)]
    [InlineData(299.00, 0.00)]
    [InlineData(650.00, 0.00)]
    public void Frete_gratis_a_partir_de_299(decimal valor, decimal esperado) =>
        Assert.Equal(esperado, RegraFrete.Calcular(valor));
}

public class PedidoTests
{
    private static ItemPedido Item(int id, string tam, int qtd, decimal preco) =>
        new() { ProdutoId = id, Nome = $"Produto {id}", Tamanho = tam, Quantidade = qtd, PrecoUnitario = preco };

    [Fact]
    public void Calcula_subtotal_frete_e_total()
    {
        var pedido = new Pedido();
        pedido.AdicionarItem(Item(1, "M", 1, 160m));
        Assert.Equal(160m, pedido.Subtotal);
        Assert.Equal(19.90m, pedido.Frete);
        Assert.Equal(179.90m, pedido.Total);
    }

    [Fact]
    public void Mesmo_produto_e_tamanho_soma_quantidade()
    {
        var pedido = new Pedido();
        pedido.AdicionarItem(Item(1, "M", 1, 200m));
        pedido.AdicionarItem(Item(1, "M", 2, 200m));
        Assert.Single(pedido.Itens);
        Assert.Equal(3, pedido.Itens[0].Quantidade);
        Assert.Equal(0m, pedido.Frete);
    }

    [Fact]
    public void Cupom_aplica_desconto_e_pode_tirar_frete_gratis()
    {
        var pedido = new Pedido();
        pedido.AdicionarItem(Item(1, "G", 1, 300m));
        pedido.AplicarCupom(new Cupom { Codigo = "BEMVINDO10", Percentual = 10m }, DateTime.Today);
        Assert.Equal(30m, pedido.Desconto);
        Assert.Equal(19.90m, pedido.Frete);          // 270 < 299
        Assert.Equal(289.90m, pedido.Total);
    }

    [Fact]
    public void Cupom_expirado_e_rejeitado()
    {
        var pedido = new Pedido();
        pedido.AdicionarItem(Item(1, "G", 1, 300m));
        var cupom = new Cupom { Codigo = "X", Percentual = 10m, ValidoAte = DateTime.Today.AddDays(-1) };
        Assert.Throws<RegraNegocioException>(() => pedido.AplicarCupom(cupom, DateTime.Today));
    }

    [Fact]
    public void Quantidade_acima_do_limite_e_rejeitada() =>
        Assert.Throws<RegraNegocioException>(() => new Pedido().AdicionarItem(Item(1, "M", 11, 200m)));
}

public class StatusPedidoTests
{
    [Theory]
    [InlineData(StatusPedido.Pago, StatusPedido.EmSeparacao, true)]
    [InlineData(StatusPedido.EmSeparacao, StatusPedido.Pago, false)]
    [InlineData(StatusPedido.Enviado, StatusPedido.Cancelado, false)]
    [InlineData(StatusPedido.Pago, StatusPedido.Cancelado, true)]
    [InlineData(StatusPedido.Entregue, StatusPedido.Cancelado, false)]
    public void Transicoes_de_status(StatusPedido atual, StatusPedido novo, bool permitido) =>
        Assert.Equal(permitido, atual.PodeMudarPara(novo));

    [Fact]
    public void Converte_texto_do_banco() =>
        Assert.Equal(StatusPedido.EmSeparacao, StatusPedidoRegras.DeTexto("Em Separação"));
}

public class UsuarioEProdutoTests
{
    [Theory]
    [InlineData("curta1")]
    [InlineData("somenteletras")]
    [InlineData("12345678")]
    [InlineData("senha123")]                       // lista de senhas comuns
    [InlineData("Brasil2026")]                     // idem, sem diferenciar maiúsculas
    [InlineData("aaaa1111")]                       // só 2 caracteres diferentes
    public void Senha_fraca_e_rejeitada(string senha) =>
        Assert.Throws<RegraNegocioException>(() => Usuario.ValidarForcaSenha(senha));

    [Fact]
    public void Senha_nao_pode_conter_o_email_nem_passar_de_72_bytes()
    {
        Assert.Throws<RegraNegocioException>(() => Usuario.ValidarForcaSenha("matheus2026", "matheus@estudante.com"));
        Assert.Throws<RegraNegocioException>(() => Usuario.ValidarForcaSenha(new string('a', 70) + "1é"));   // 73 bytes
        Usuario.ValidarForcaSenha("uma frase longa de torcedor 1994", "matheus@estudante.com");          // frase: aceita
    }

    [Fact]
    public void Novo_cliente_normaliza_email()
    {
        var u = Usuario.NovoCliente("Maria Souza", "  Maria@Email.COM ", "hash");
        Assert.Equal("maria@email.com", u.Email);
        Assert.Equal(PerfilUsuario.Cliente, u.Perfil);
    }

    [Fact]
    public void Fabrica_cria_subclasse_pela_linha()
    {
        Assert.IsType<Chuteira>(ProdutoFactory.CriarPorLinha("Society"));
        Assert.IsType<Camisa>(ProdutoFactory.CriarPorLinha("Seleção"));
    }

    [Fact]
    public void Camisa_abaixo_do_preco_minimo_e_invalida()
    {
        var camisa = (Camisa)ProdutoFactory.CriarPorLinha("Clube");
        camisa.Nome = "Teste"; camisa.Descricao = "Desc"; camisa.Preco = 120m;
        Assert.Throws<RegraNegocioException>(camisa.Validar);
    }

    [Fact]
    public void Grade_de_tamanhos_por_tipo()
    {
        Assert.True(new Chuteira().TamanhoValido("42"));
        Assert.False(new Chuteira().TamanhoValido("M"));
        Assert.True(new Camisa().TamanhoValido("gg"));
    }
}

/// <summary>Serviço testado com repositórios em memória (sem banco).</summary>
public class PedidoServicoTests
{
    [Fact]
    public async Task Simulacao_usa_preco_do_catalogo_e_nao_do_cliente()
    {
        var servico = new PedidoServico(new PedidosFake(), new ProdutosFake(), TimeProvider.System);
        var resumo = await servico.SimularAsync(new SimularPedidoRequest(
            new List<ItemCarrinhoRequest> { new(1, "M", 2) }, null));

        Assert.Equal(2 * 349.90m, resumo.Subtotal);
        Assert.Equal(0m, resumo.Frete);
    }

    [Fact]
    public async Task Tamanho_esgotado_bloqueia_checkout()
    {
        var servico = new PedidoServico(new PedidosFake(), new ProdutosFake(), TimeProvider.System);
        var ex = await Assert.ThrowsAsync<RegraNegocioException>(() => servico.SimularAsync(
            new SimularPedidoRequest(new List<ItemCarrinhoRequest> { new(1, "XG", 1) }, null)));
        Assert.Contains("esgotado", ex.Message);
    }

    private class ProdutosFake : IProdutoRepositorio
    {
        private static readonly ProdutoResumoResponse Brasil = new(1, "Camisa Brasil 2026 Home", "Torcedor", "Seleção",
            "Brasil", 2026, "desc", 349.90m, null, 349.90m, "img.jpg", true, 1, "Temporada 2026", "temporada-2026",
            20, 5, 1);

        public Task<ProdutoResumoResponse?> ObterResumoAsync(int id) =>
            Task.FromResult(id == 1 ? Brasil : null);

        public Task<IReadOnlyList<TamanhoEstoqueResponse>> ListarTamanhosAsync(int produtoId) =>
            Task.FromResult<IReadOnlyList<TamanhoEstoqueResponse>>(new[]
            {
                new TamanhoEstoqueResponse("M", 10), new TamanhoEstoqueResponse("XG", 0)
            });

        public Task<IReadOnlyList<CategoriaResponse>> ListarCategoriasAsync() => throw new NotImplementedException();
        public Task<IReadOnlyList<ProdutoResumoResponse>> ListarAsync(FiltroProdutos filtro) => throw new NotImplementedException();
        public Task<IReadOnlyList<string>> ListarImagensAsync(int produtoId) => throw new NotImplementedException();
        public Task<IReadOnlyList<AvaliacaoResponse>> ListarAvaliacoesAsync(int produtoId) => throw new NotImplementedException();
        public Task RegistrarAvaliacaoAsync(int produtoId, int usuarioId, int nota, string? comentario, string status) => throw new NotImplementedException();
        public Task<int> InserirAsync(Produto produto, IReadOnlyList<string> imagens) => throw new NotImplementedException();
        public Task AtualizarAsync(Produto produto, IReadOnlyList<string>? imagens) => throw new NotImplementedException();
        public Task<bool> DesativarAsync(int id) => throw new NotImplementedException();
        public Task<string?> ObterSlugCategoriaAsync(int categoriaId) => throw new NotImplementedException();
    }

    private class PedidosFake : IPedidoRepositorio
    {
        public Task<Cupom?> ObterCupomAsync(string codigo) => Task.FromResult<Cupom?>(null);
        public Task<int> InserirEnderecoAsync(int usuarioId, EnderecoRequest endereco) => throw new NotImplementedException();
        public Task<PedidoCriadoResponse> RegistrarAsync(int usuarioId, CriarPedidoRequest pedido, int? enderecoId) => throw new NotImplementedException();
        public Task<IReadOnlyList<PedidoResponse>> ListarPorUsuarioAsync(int usuarioId) => throw new NotImplementedException();
        public Task<IReadOnlyList<PedidoResponse>> ListarTodosAsync(string? status, int limite) => throw new NotImplementedException();
        public Task<PedidoResponse?> ObterAsync(int pedidoId) => throw new NotImplementedException();
        public Task<int?> ObterDonoAsync(int pedidoId) => throw new NotImplementedException();
        public Task AtualizarStatusAsync(int pedidoId, string novoStatus) => throw new NotImplementedException();
    }
}
