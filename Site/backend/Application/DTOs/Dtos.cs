namespace JogaBonito.Api.Application.DTOs;

// ============================================================================
// Contratos de entrada e saída da API (Data Transfer Objects).
// A API serializa em camelCase: { "produtoId": 1, "tamanho": "M" }.
// ============================================================================

// ---------- Autenticação ----------
public record LoginRequest(string Email, string Senha);
public record CadastroRequest(string Nome, string Email, string Senha, bool AceiteLgpd);
public record UsuarioResponse(int Id, string Nome, string Email, string Role);
public record LoginResponse(string Token, DateTime ExpiraEm, UsuarioResponse Usuario);
public record TrocarSenhaRequest(string SenhaAtual, string NovaSenha);
public record StatusConexaoResponse(string Status, IReadOnlyList<StatusComponenteResponse> Componentes, double DuracaoMs);
public record StatusComponenteResponse(string Nome, string Status, string? Descricao, double DuracaoMs);
public record AcessoResponse(long Id, string Email, string? Ip, bool Sucesso, string? Detalhe, DateTime Data);

// ---------- Catálogo ----------
public record CategoriaResponse(int Id, string Nome, string Slug, string Descricao);

public record FiltroProdutos(string? Categoria, string? Linha, string? Busca, string? Ordem, bool? Destaque,
    string? Marca = null, decimal? PrecoMax = null);

public record ProdutoResumoResponse(
    int Id, string Nome, string Modelo, string Linha, string? Equipe, int? Ano,
    string Descricao, decimal Preco, decimal? PrecoPromocional, decimal PrecoFinal,
    string Img, bool Destaque, int CategoriaId, string Categoria, string CategoriaSlug,
    int Estoque, decimal NotaMedia, int TotalAvaliacoes,
    string? Marca = null, string? Solado = null);

public record TamanhoEstoqueResponse(string Tamanho, int Quantidade);

public record ProdutoDetalheResponse(
    ProdutoResumoResponse Produto, string Tipo, IReadOnlyList<string> Imgs,
    IReadOnlyList<TamanhoEstoqueResponse> Tamanhos);

public record AvaliacaoResponse(string Cliente, int Nota, string? Comentario, DateTime Data);
public record AvaliacaoRequest(int Nota, string? Comentario);
public record AvaliacaoEnviadaResponse(string Status, string Mensagem);

// ---------- Moderação de avaliações (admin) ----------
public record AvaliacaoAdminResponse(int Id, int ProdutoId, string Produto, string Cliente, int Nota,
    string? Comentario, string Status, DateTime Data, string? MotivoModeracao, string? Moderador, DateTime? ModeradoEm);
public record ModerarAvaliacaoRequest(string Status, string? Motivo);

// ---------- LGPD ----------
public record ExcluirContaRequest(string Senha);
public record EnderecoResponse(string Cep, string Rua, string Numero, string? Complemento, string Bairro,
    string Cidade, string Estado);
public record AvaliacaoPessoalResponse(string Produto, int Nota, string? Comentario, string Status, DateTime Data);
public record ContaResponse(int Id, string Nome, string Email, string? Telefone, string Perfil,
    DateTime CriadoEm, DateTime? AceiteLgpdEm);
public record DadosPessoaisResponse(ContaResponse Conta, IReadOnlyList<EnderecoResponse> Enderecos,
    IReadOnlyList<PedidoResponse> Pedidos, IReadOnlyList<AvaliacaoPessoalResponse> Avaliacoes,
    IReadOnlyList<AcessoResponse> Acessos, DateTime GeradoEm, string Observacao);

// ---------- Carrinho / Pedidos ----------
public record ItemCarrinhoRequest(int ProdutoId, string Tamanho, int Quantidade);

public record EnderecoRequest(string Cep, string Rua, string Numero, string? Complemento,
    string Bairro, string Cidade, string Estado);

public record SimularPedidoRequest(List<ItemCarrinhoRequest> Itens, string? Cupom);

public record CriarPedidoRequest(
    List<ItemCarrinhoRequest> Itens, string FormaPagamento, int Parcelas,
    string? Cupom, EnderecoRequest? Endereco, string? Origem);

public record ItemPedidoResponse(int ProdutoId, string Nome, string Img, string Tamanho,
    int Qtd, decimal Preco, decimal Subtotal);

public record ResumoPedidoResponse(IReadOnlyList<ItemPedidoResponse> Itens,
    decimal Subtotal, decimal Desconto, decimal Frete, decimal Total, string? Cupom, decimal JogaJunto = 0);

public record PedidoCriadoResponse(int PedidoId, string CodigoRastreio, decimal Subtotal,
    decimal Desconto, decimal Frete, decimal Total, string Status, decimal JogaJunto = 0);

public record HistoricoStatusResponse(string Status, DateTime Data);

public record PedidoResponse(
    int Id, DateTime Data, string Status, string FormaPagamento, int Parcelas,
    string? CodigoRastreio, string Origem, decimal Subtotal, decimal Desconto,
    decimal Frete, decimal Total, string? Cliente,
    IReadOnlyList<ItemPedidoResponse> Itens, IReadOnlyList<HistoricoStatusResponse> Historico,
    decimal JogaJunto = 0);

public record ValidarCupomRequest(string Codigo, decimal Subtotal);
public record ValidarCupomResponse(bool Valido, string Codigo, decimal Percentual, decimal Desconto, string Mensagem);

// ---------- Administração ----------
public record AtualizarEstoqueRequest(int ProdutoId, string Tamanho, int Quantidade);
public record AtualizarStatusRequest(string Status);

public record EstoqueLinhaResponse(int ProdutoId, string Nome, string Linha, string Categoria,
    string Tamanho, int Quantidade, string StatusNivel, DateTime UltimaAtualizacao);

public record AuditoriaResponse(int Id, int ProdutoId, string Produto, string Tamanho,
    int QtdAnterior, int QtdNova, string Origem, DateTime Data);

public record SalvarProdutoRequest(
    int CategoriaId, string Nome, string Modelo, string Linha, string? Equipe, int? Ano,
    string Descricao, decimal Preco, decimal? PrecoPromocional, string Imagem,
    bool Destaque, List<string>? Imagens, string? Marca = null, string? Solado = null);

public record VendaCategoriaResponse(string Categoria, int Unidades, decimal Receita);
public record MaisVendidoResponse(int ProdutoId, string Nome, string Categoria, int Unidades, decimal Receita);

public record DashboardResponse(
    int TotalProdutos, int TotalPecasEstoque, int TotalClientes, int TotalPedidos,
    decimal FaturamentoTotal, decimal Faturamento30Dias, decimal TicketMedio30Dias,
    int TamanhosEsgotados, int TamanhosEstoqueBaixo, int PedidosPendentesEnvio,
    IReadOnlyList<VendaCategoriaResponse> VendasPorCategoria,
    IReadOnlyList<MaisVendidoResponse> MaisVendidos,
    decimal TotalJogaJunto = 0, int AvaliacoesPendentes = 0);

public record ConsultaResponse(string Nome, string Descricao, IReadOnlyList<string> Colunas,
    IReadOnlyList<Dictionary<string, object?>> Linhas);

public record ConsultaDisponivelResponse(string Nome, string Descricao);
