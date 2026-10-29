using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Domain.Entidades;
using Microsoft.IdentityModel.Tokens;

namespace JogaBonito.Api.Infrastructure.Seguranca;

/// <summary>Configuração do JWT lida do appsettings.json / variáveis de ambiente (Jwt__Chave).</summary>
public class JwtOpcoes
{
    public string Chave { get; set; } = string.Empty;
    public string Emissor { get; set; } = "JogaBonito.Api";
    public string Publico { get; set; } = "JogaBonito.Clientes";
    public int ExpiracaoHoras { get; set; } = 8;

    public SymmetricSecurityKey ChaveAssinatura()
    {
        if (Encoding.UTF8.GetByteCount(Chave) < 32)
            throw new InvalidOperationException(
                "Jwt:Chave precisa ter pelo menos 32 caracteres. Defina a variável de ambiente Jwt__Chave.");
        return new SymmetricSecurityKey(Encoding.UTF8.GetBytes(Chave));
    }

    /// <summary>Chaves publicadas no repositório (appsettings de desenvolvimento, docker-compose, .env.example).</summary>
    public static bool EhChaveDeExemplo(string chave) =>
        new[] { "troque", "dev-somente", "gere-uma-chave", "exemplo" }
            .Any(t => chave.Contains(t, StringComparison.OrdinalIgnoreCase));
}

/// <summary>Emite tokens JWT assinados com HMAC-SHA256 contendo id, nome, e-mail e perfil.</summary>
public class JwtGeradorToken : IGeradorToken
{
    private readonly JwtOpcoes _opcoes;

    public JwtGeradorToken(JwtOpcoes opcoes) => _opcoes = opcoes;

    public (string Token, DateTime ExpiraEm) Gerar(Usuario usuario)
    {
        var expira = DateTime.UtcNow.AddHours(_opcoes.ExpiracaoHoras);
        var token = new JwtSecurityToken(
            issuer: _opcoes.Emissor,
            audience: _opcoes.Publico,
            claims: new[]
            {
                new Claim(ClaimTypes.NameIdentifier, usuario.Id.ToString()),
                new Claim(ClaimTypes.Name, usuario.Nome),
                new Claim(ClaimTypes.Email, usuario.Email),
                new Claim(ClaimTypes.Role, usuario.Perfil.ToString()),
                new Claim(ValidadorSessao.ClaimVersao, usuario.VersaoToken.ToString()),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
            },
            expires: expira,
            signingCredentials: new SigningCredentials(_opcoes.ChaveAssinatura(), SecurityAlgorithms.HmacSha256));

        return (new JwtSecurityTokenHandler().WriteToken(token), expira);
    }
}

/// <summary>Hash de senha com BCrypt (salt aleatório embutido, custo 11).</summary>
public class BCryptHasher : IHasherSenha
{
    public const int Custo = 11;

    public string GerarHash(string senha) => BCrypt.Net.BCrypt.HashPassword(senha, workFactor: Custo);

    public bool PrecisaAtualizar(string hash)
    {
        try { return BCrypt.Net.BCrypt.PasswordNeedsRehash(hash, Custo); }
        catch (BCrypt.Net.SaltParseException) { return false; }
    }

    public bool Verificar(string senha, string hash)
    {
        // Só aceita hashes BCrypt válidos: senhas em texto puro no banco nunca autenticam
        if (string.IsNullOrEmpty(hash) || !hash.StartsWith("$2")) return false;
        try { return BCrypt.Net.BCrypt.Verify(senha, hash); }
        catch (BCrypt.Net.SaltParseException) { return false; }
    }
}

public static class ClaimsExtensoes
{
    public static int UsuarioId(this ClaimsPrincipal user) =>
        int.TryParse(user.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var id)
            ? id
            : throw new UnauthorizedAccessException("Token sem identificação de usuário.");

    public static bool EhAdmin(this ClaimsPrincipal user) => user.IsInRole("Admin");
}
