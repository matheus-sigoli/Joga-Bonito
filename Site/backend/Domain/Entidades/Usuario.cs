using System.Text.RegularExpressions;
using JogaBonito.Api.Domain.Excecoes;

namespace JogaBonito.Api.Domain.Entidades;

/// <summary>Classe base de todas as entidades persistidas (identidade).</summary>
public abstract class EntidadeBase
{
    public int Id { get; set; }
}

public enum PerfilUsuario { Cliente, Admin }

/// <summary>
/// Usuário da plataforma. Encapsula as regras de cadastro (nome, e-mail, força da senha)
/// para que nenhuma camada crie um usuário em estado inválido.
/// </summary>
public class Usuario : EntidadeBase
{
    private static readonly Regex FormatoEmail =
        new(@"^[^@\s]+@[^@\s]+\.[^@\s]+$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    public string Nome { get; private set; } = string.Empty;
    public string Email { get; private set; } = string.Empty;
    public string SenhaHash { get; private set; } = string.Empty;
    public PerfilUsuario Perfil { get; private set; } = PerfilUsuario.Cliente;
    public bool Ativo { get; private set; } = true;

    /// <summary>Preenchido somente enquanto o bloqueio está valendo (o banco compara com a hora dele).</summary>
    public DateTime? BloqueadoAte { get; private set; }

    /// <summary>Vai no token (claim "ver"); quando o banco incrementa, todos os tokens antigos deixam de valer.</summary>
    public int VersaoToken { get; private set; } = 1;

    public bool EhAdministrador => Perfil == PerfilUsuario.Admin;
    public bool Bloqueado => BloqueadoAte.HasValue;

    /// <summary>Quantas senhas erradas seguidas bloqueiam a conta, e por quanto tempo.</summary>
    public const int MaxTentativasLogin = 5;
    public const int MinutosBloqueio = 15;

    // Construtor usado pelo repositório ao reconstruir a entidade a partir do banco.
    public Usuario(int id, string nome, string email, string senhaHash, PerfilUsuario perfil, bool ativo,
        DateTime? bloqueadoAte = null, int versaoToken = 1)
    {
        Id = id; Nome = nome; Email = email; SenhaHash = senhaHash; Perfil = perfil; Ativo = ativo;
        BloqueadoAte = bloqueadoAte;
        VersaoToken = versaoToken;
    }

    /// <summary>Usado depois da troca de senha, para emitir o novo token já com a versão nova.</summary>
    public void AtualizarVersaoToken(int versao) => VersaoToken = versao;

    private Usuario() { }

    /// <summary>Fábrica para novos clientes: valida os dados antes de criar.</summary>
    public static Usuario NovoCliente(string nome, string email, string senhaHash)
    {
        nome = (nome ?? string.Empty).Trim();
        email = NormalizarEmail(email);

        if (nome.Length < 3 || nome.Length > 100)
            throw new RegraNegocioException("Informe seu nome completo (3 a 100 caracteres).");
        if (!EmailValido(email))
            throw new RegraNegocioException("Informe um e-mail válido.");

        return new Usuario { Nome = nome, Email = email, SenhaHash = senhaHash, Perfil = PerfilUsuario.Cliente };
    }

    /// <summary>Administrador inicial (criado a partir das variáveis de ambiente).</summary>
    public static Usuario NovoAdministrador(string nome, string email, string senhaHash)
    {
        var u = NovoCliente(nome, email, senhaHash);
        u.Perfil = PerfilUsuario.Admin;
        return u;
    }

    public static string NormalizarEmail(string? email) => (email ?? string.Empty).Trim().ToLowerInvariant();

    public static bool EmailValido(string email) => email.Length <= 120 && FormatoEmail.IsMatch(email);

    /// <summary>Senhas mais usadas no Brasil (vazamentos públicos): nunca são aceitas.</summary>
    private static readonly HashSet<string> SenhasComuns = new(StringComparer.OrdinalIgnoreCase)
    {
        "senha123", "senha1234", "senha12345", "senha2024", "senha2025", "senha2026", "12345678a", "123456789a",
        "a12345678", "abc12345", "abcd1234", "qwerty123", "password1", "password123", "brasil123", "brasil2026",
        "flamengo1", "flamengo123", "corinthians1", "palmeiras1", "mudar123", "admin123", "admin2026",
        "jogabonito1", "jogabonito2026", "futebol123", "teste123", "iloveyou1", "1q2w3e4r", "q1w2e3r4"
    };

    /// <summary>
    /// Política de senha: 8+ caracteres com letras e números, até 72 bytes (limite do BCrypt — acima
    /// disso o algoritmo ignoraria o resto), fora da lista de senhas comuns e sem repetir o e-mail.
    /// </summary>
    public static void ValidarForcaSenha(string? senha, string? email = null)
    {
        if (string.IsNullOrWhiteSpace(senha) || senha.Length < 8 || System.Text.Encoding.UTF8.GetByteCount(senha) > 72
            || !senha.Any(char.IsLetter) || !senha.Any(char.IsDigit))
            throw new RegraNegocioException("A senha deve ter de 8 a 72 caracteres, com letras e números.");

        if (SenhasComuns.Contains(senha) || senha.Distinct().Count() <= 3)
            throw new RegraNegocioException("Essa senha é muito comum. Escolha outra, de preferência uma frase.");

        var usuarioEmail = NormalizarEmail(email).Split('@')[0];
        if (usuarioEmail.Length >= 4 && senha.Contains(usuarioEmail, StringComparison.OrdinalIgnoreCase))
            throw new RegraNegocioException("A senha não pode conter o seu e-mail.");
    }

    public static PerfilUsuario PerfilDeTexto(string? texto) =>
        string.Equals(texto, "Admin", StringComparison.OrdinalIgnoreCase) ? PerfilUsuario.Admin : PerfilUsuario.Cliente;
}
