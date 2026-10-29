using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Domain.Excecoes;

namespace JogaBonito.Api.Application.Servicos;

/// <summary>
/// Direitos do titular previstos na LGPD (Lei 13.709/2018, art. 18), sem depender de e-mail:
///   * acesso/portabilidade: o cliente baixa todos os seus dados em JSON;
///   * correção: nome e e-mail são corrigidos pelo atendimento (ver Política de Privacidade);
///   * eliminação: a conta é anonimizada; os pedidos ficam sem dados pessoais porque a
///     empresa precisa guardá-los por obrigação fiscal (art. 16, I).
/// Só o próprio titular, autenticado e informando a senha (para excluir), executa as ações.
/// </summary>
public class PrivacidadeServico
{
    private readonly IPrivacidadeRepositorio _privacidade;
    private readonly IPedidoRepositorio _pedidos;
    private readonly IUsuarioRepositorio _usuarios;
    private readonly IHasherSenha _hasher;

    public PrivacidadeServico(IPrivacidadeRepositorio privacidade, IPedidoRepositorio pedidos,
        IUsuarioRepositorio usuarios, IHasherSenha hasher)
    {
        _privacidade = privacidade;
        _pedidos = pedidos;
        _usuarios = usuarios;
        _hasher = hasher;
    }

    public async Task<DadosPessoaisResponse> ExportarAsync(int usuarioId)
    {
        var conta = await _privacidade.ObterContaAsync(usuarioId)
                    ?? throw new RecursoNaoEncontradoException("Conta não encontrada.");
        return new DadosPessoaisResponse(
            conta,
            await _privacidade.ListarEnderecosAsync(usuarioId),
            await _pedidos.ListarPorUsuarioAsync(usuarioId),
            await _privacidade.ListarAvaliacoesAsync(usuarioId),
            await _privacidade.ListarAcessosAsync(usuarioId, 200),
            DateTime.UtcNow,
            "Dados pessoais mantidos pela Joga Bonito (LGPD, art. 18, II e V). Senhas não são exportadas: ficam guardadas só como hash BCrypt.");
    }

    public async Task ExcluirContaAsync(int usuarioId, ExcluirContaRequest request)
    {
        var usuario = await _usuarios.ObterPorIdAsync(usuarioId)
                      ?? throw new RecursoNaoEncontradoException("Conta não encontrada.");
        if (string.IsNullOrEmpty(request.Senha) || !_hasher.Verificar(request.Senha, usuario.SenhaHash))
            throw new RegraNegocioException("Senha incorreta. Para excluir a conta, confirme sua senha atual.");
        if (usuario.EhAdministrador)
            throw new RegraNegocioException("Contas de administrador não podem ser excluídas por aqui.");
        await _privacidade.AnonimizarAsync(usuarioId);
    }
}
