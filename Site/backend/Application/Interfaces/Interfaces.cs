using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Domain.Entidades;

namespace JogaBonito.Api.Application.Interfaces;

// ============================================================================
// Contratos da camada de aplicação. Os serviços dependem destas interfaces e não
// do SQL Server diretamente (Inversão de Dependência) — isso permite trocar a
// implementação ou usar dublês nos testes unitários.
// ============================================================================

public interface IUsuarioRepositorio
{
    Task<Usuario?> ObterPorEmailAsync(string email);
    Task<Usuario?> ObterPorIdAsync(int id);
    Task<bool> EmailExisteAsync(string email);
    Task<int> InserirAsync(Usuario usuario);
    /// <summary>Grava o novo hash e incrementa VersaoToken (derruba as outras sessões). Devolve a versão nova.</summary>
    Task<int> AtualizarSenhaAsync(int usuarioId, string novoHash);

    /// <summary>Regrava o hash sem mexer na sessão (rehash quando o custo do BCrypt aumenta).</summary>
    Task AtualizarHashAsync(int usuarioId, string novoHash);

    /// <summary>Incrementa VersaoToken: todos os tokens já emitidos para o usuário deixam de valer.</summary>
    Task<int> RevogarSessoesAsync(int usuarioId);

    /// <summary>Estado atual da conta, conferido a cada requisição autenticada (com cache curto).</summary>
    Task<EstadoSessao?> ObterEstadoSessaoAsync(int usuarioId);

    /// <summary>
    /// Grava o log de acesso e aplica a regra de bloqueio (sp_RegistrarTentativaLogin).
    /// Devolve a data/hora até quando a conta ficou bloqueada, ou null.
    /// </summary>
    Task<DateTime?> RegistrarTentativaLoginAsync(string email, bool sucesso, string? ip, string detalhe);
}

public interface IProdutoRepositorio
{
    Task<IReadOnlyList<CategoriaResponse>> ListarCategoriasAsync();
    Task<IReadOnlyList<ProdutoResumoResponse>> ListarAsync(FiltroProdutos filtro);
    Task<ProdutoResumoResponse?> ObterResumoAsync(int id);
    Task<IReadOnlyList<string>> ListarImagensAsync(int produtoId);
    Task<IReadOnlyList<TamanhoEstoqueResponse>> ListarTamanhosAsync(int produtoId);
    Task<IReadOnlyList<AvaliacaoResponse>> ListarAvaliacoesAsync(int produtoId);
    Task RegistrarAvaliacaoAsync(int produtoId, int usuarioId, int nota, string? comentario, string status);
    Task<int> InserirAsync(Produto produto, IReadOnlyList<string> imagens);
    Task AtualizarAsync(Produto produto, IReadOnlyList<string>? imagens);
    Task<bool> DesativarAsync(int id);
    Task<string?> ObterSlugCategoriaAsync(int categoriaId);
}

/// <summary>Direitos do titular (LGPD art. 18): acesso aos dados e exclusão (anonimização).</summary>
public interface IPrivacidadeRepositorio
{
    Task<ContaResponse?> ObterContaAsync(int usuarioId);
    Task<IReadOnlyList<EnderecoResponse>> ListarEnderecosAsync(int usuarioId);
    Task<IReadOnlyList<AvaliacaoPessoalResponse>> ListarAvaliacoesAsync(int usuarioId);
    Task<IReadOnlyList<AcessoResponse>> ListarAcessosAsync(int usuarioId, int limite);
    Task AnonimizarAsync(int usuarioId);
}

/// <summary>Moderação de avaliações pelo painel administrativo.</summary>
public interface IAvaliacaoRepositorio
{
    Task<IReadOnlyList<AvaliacaoAdminResponse>> ListarAsync(string? status, int limite);
    Task ModerarAsync(int avaliacaoId, string novoStatus, int adminId, string? motivo);
}

public interface IPedidoRepositorio
{
    Task<Cupom?> ObterCupomAsync(string codigo);
    Task<int> InserirEnderecoAsync(int usuarioId, EnderecoRequest endereco);
    Task<PedidoCriadoResponse> RegistrarAsync(int usuarioId, CriarPedidoRequest pedido, int? enderecoId);
    Task<IReadOnlyList<PedidoResponse>> ListarPorUsuarioAsync(int usuarioId);
    Task<IReadOnlyList<PedidoResponse>> ListarTodosAsync(string? status, int limite);
    Task<PedidoResponse?> ObterAsync(int pedidoId);
    Task<int?> ObterDonoAsync(int pedidoId);
    Task AtualizarStatusAsync(int pedidoId, string novoStatus);
}

public interface IEstoqueRepositorio
{
    Task<IReadOnlyList<EstoqueLinhaResponse>> RelatorioAsync();
    Task AtualizarAsync(int produtoId, string tamanho, int quantidade, string origem);
    Task<IReadOnlyList<AuditoriaResponse>> AuditoriaAsync(int limite);
}

public interface IRelatorioRepositorio
{
    Task<DashboardResponse> DashboardAsync();
    Task<ConsultaResponse> ExecutarConsultaAsync(string nome);
    IReadOnlyList<ConsultaDisponivelResponse> ConsultasDisponiveis();
    Task<IReadOnlyList<AcessoResponse>> AcessosAsync(int limite);
}

/// <summary>Cache curto do catálogo (vitrine), invalidado quando produto, estoque ou pedido mudam.</summary>
public interface ICacheCatalogo
{
    Task<T> ObterAsync<T>(string chave, Func<Task<T>> carregar);
    void Invalidar();
}

public interface IHasherSenha
{
    string GerarHash(string senha);
    bool Verificar(string senha, string hash);

    /// <summary>True quando o hash foi gerado com custo menor que o atual (deve ser refeito no login).</summary>
    bool PrecisaAtualizar(string hash) => false;
}

/// <summary>O que o servidor confere em cada requisição autenticada.</summary>
public record EstadoSessao(bool Ativo, string Perfil, int VersaoToken);

public interface IGeradorToken
{
    (string Token, DateTime ExpiraEm) Gerar(Usuario usuario);
}
