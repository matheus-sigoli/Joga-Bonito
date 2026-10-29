using System.Security.Claims;
using JogaBonito.Api.Application.Interfaces;
using Microsoft.Extensions.Caching.Memory;

namespace JogaBonito.Api.Infrastructure.Seguranca;

/// <summary>
/// Confere, a cada requisição autenticada, se o token ainda vale para o BANCO — não só para a assinatura:
///   * a conta continua ativa;
///   * o perfil no token (Cliente/Admin) é o mesmo do cadastro — um admin rebaixado perde o acesso na hora;
///   * a versão do token (claim "ver") é a atual — trocar a senha ou "sair de todos os aparelhos"
///     incrementa Usuarios.VersaoToken e todos os tokens antigos param de funcionar.
/// O estado fica 30 s em cache para não consultar o banco em toda requisição; as alterações feitas
/// por esta API descartam o cache na hora (<see cref="Invalidar"/>).
/// </summary>
public class ValidadorSessao
{
    public const string ClaimVersao = "ver";
    private static readonly TimeSpan Duracao = TimeSpan.FromSeconds(30);

    private readonly IUsuarioRepositorio _usuarios;
    private readonly IMemoryCache _cache;

    public ValidadorSessao(IUsuarioRepositorio usuarios, IMemoryCache cache)
    {
        _usuarios = usuarios;
        _cache = cache;
    }

    /// <summary>Devolve null se o token é válido, ou o motivo da recusa.</summary>
    public async Task<string?> ValidarAsync(ClaimsPrincipal usuario)
    {
        if (!int.TryParse(usuario.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var id))
            return "Token sem identificação de usuário.";
        if (!int.TryParse(usuario.FindFirst(ClaimVersao)?.Value, out var versao))
            return "Token antigo. Entre novamente.";

        var estado = await _cache.GetOrCreateAsync(Chave(id), entrada =>
        {
            entrada.SetAbsoluteExpiration(Duracao).SetSize(1);
            return _usuarios.ObterEstadoSessaoAsync(id);
        });

        if (estado is null || !estado.Ativo) return "Conta inexistente ou desativada.";
        if (estado.VersaoToken != versao) return "Sessão encerrada. Entre novamente.";
        if (!usuario.IsInRole(estado.Perfil)) return "Seu perfil de acesso mudou. Entre novamente.";
        return null;
    }

    public void Invalidar(int usuarioId) => _cache.Remove(Chave(usuarioId));

    private static string Chave(int id) => $"sessao:{id}";
}
