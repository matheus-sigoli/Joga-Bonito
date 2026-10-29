using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Application.Servicos;
using JogaBonito.Api.Domain.Entidades;
using JogaBonito.Api.Domain.Excecoes;
using Xunit;

namespace JogaBonito.Tests;

public class ModeracaoAvaliacaoTests
{
    private static readonly string[] Bloqueados = { "idiota", "macaco" };

    [Theory]
    [InlineData("Tecido ótimo, chegou rápido.", "Publicada")]
    [InlineData(null, "Publicada")]
    [InlineData("Mais barato em www.outraloja.com", "Pendente")]
    [InlineData("Me chama no 11 98888-7777", "Pendente")]
    [InlineData("Escreve pra mim: fulano@email.com", "Pendente")]
    [InlineData("Vendedor IDIÓTA", "Pendente")]                 // maiúsculas e acento não escapam
    [InlineData("Jogador xingado de macaco no estádio", "Pendente")]
    [InlineData("Tamanho 42 serviu bem", "Publicada")]         // número curto não é telefone
    public void Status_inicial_da_avaliacao(string? comentario, string esperado) =>
        Assert.Equal(esperado, ModeracaoAvaliacao.StatusInicial(comentario, Bloqueados));

    [Fact]
    public async Task Servico_grava_pendente_e_avisa_o_cliente()
    {
        var repo = new ProdutosAvaliacao();
        var servico = new CatalogoServico(repo, termosBloqueados: Bloqueados);

        var r = await servico.AvaliarAsync(8, 2, new AvaliacaoRequest(5, "veja em https://golpe.example"));

        Assert.Equal("Pendente", repo.StatusGravado);
        Assert.Equal("Pendente", r.Status);
        Assert.Contains("revisada", r.Mensagem);
    }

    [Theory]
    [InlineData("Publicada", true)]
    [InlineData("Oculta", true)]
    [InlineData("Pendente", false)]   // o admin não devolve para a fila: decide
    [InlineData("Apagada", false)]
    public void Admin_so_publica_ou_oculta(string status, bool valido) =>
        Assert.Equal(valido, ModeracaoAvaliacao.StatusDeModeracaoValido(status));

    private sealed class ProdutosAvaliacao : IProdutoRepositorio
    {
        public string? StatusGravado { get; private set; }

        public Task RegistrarAvaliacaoAsync(int produtoId, int usuarioId, int nota, string? comentario, string status)
        {
            StatusGravado = status;
            return Task.CompletedTask;
        }

        public Task<IReadOnlyList<CategoriaResponse>> ListarCategoriasAsync() => throw new NotImplementedException();
        public Task<IReadOnlyList<ProdutoResumoResponse>> ListarAsync(FiltroProdutos filtro) => throw new NotImplementedException();
        public Task<ProdutoResumoResponse?> ObterResumoAsync(int id) => throw new NotImplementedException();
        public Task<IReadOnlyList<string>> ListarImagensAsync(int produtoId) => throw new NotImplementedException();
        public Task<IReadOnlyList<TamanhoEstoqueResponse>> ListarTamanhosAsync(int produtoId) => throw new NotImplementedException();
        public Task<IReadOnlyList<AvaliacaoResponse>> ListarAvaliacoesAsync(int produtoId) => throw new NotImplementedException();
        public Task<int> InserirAsync(Produto produto, IReadOnlyList<string> imagens) => throw new NotImplementedException();
        public Task AtualizarAsync(Produto produto, IReadOnlyList<string>? imagens) => throw new NotImplementedException();
        public Task<bool> DesativarAsync(int id) => throw new NotImplementedException();
        public Task<string?> ObterSlugCategoriaAsync(int categoriaId) => throw new NotImplementedException();
    }
}

public class JogaJuntoTests
{
    [Theory]
    [InlineData(349.90, 3.50)]
    [InlineData(299.90, 3.00)]
    [InlineData(100.00, 1.00)]
    [InlineData(0, 0)]
    public void Um_por_cento_dos_produtos(decimal valor, decimal esperado) =>
        Assert.Equal(esperado, RegraJogaJunto.Calcular(valor));

    [Fact]
    public void Pedido_calcula_sobre_o_valor_com_desconto_e_sem_frete()
    {
        var pedido = new Pedido();
        pedido.AdicionarItem(new ItemPedido { ProdutoId = 1, Nome = "Camisa", Tamanho = "M", Quantidade = 1, PrecoUnitario = 100m });
        Assert.Equal(19.90m, pedido.Frete);
        Assert.Equal(1.00m, pedido.ValorJogaJunto);
    }
}

public class PrivacidadeServicoTests
{
    [Fact]
    public async Task Excluir_conta_exige_a_senha_e_nao_vale_para_admin()
    {
        var usuarios = new BloqueioLoginTests.UsuariosFake();
        var privacidade = new PrivacidadeFake();
        var servico = new PrivacidadeServico(privacidade, null!, usuarios, new HasherSimples());

        await Assert.ThrowsAsync<RegraNegocioException>(() =>
            servico.ExcluirContaAsync(2, new ExcluirContaRequest("errada")));
        Assert.False(privacidade.Anonimizou);

        await servico.ExcluirContaAsync(2, new ExcluirContaRequest("Cliente@2026"));
        Assert.True(privacidade.Anonimizou);
    }

    private sealed class HasherSimples : IHasherSenha
    {
        public string GerarHash(string senha) => "hash:" + senha;
        public bool Verificar(string senha, string hash) => hash == "hash:" + senha;
    }

    private sealed class PrivacidadeFake : IPrivacidadeRepositorio
    {
        public bool Anonimizou { get; private set; }
        public Task AnonimizarAsync(int usuarioId) { Anonimizou = true; return Task.CompletedTask; }
        public Task<ContaResponse?> ObterContaAsync(int usuarioId) => throw new NotImplementedException();
        public Task<IReadOnlyList<EnderecoResponse>> ListarEnderecosAsync(int usuarioId) => throw new NotImplementedException();
        public Task<IReadOnlyList<AvaliacaoPessoalResponse>> ListarAvaliacoesAsync(int usuarioId) => throw new NotImplementedException();
        public Task<IReadOnlyList<AcessoResponse>> ListarAcessosAsync(int usuarioId, int limite) => throw new NotImplementedException();
    }
}
