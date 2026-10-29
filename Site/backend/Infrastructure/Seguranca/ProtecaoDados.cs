using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace JogaBonito.Api.Infrastructure.Seguranca;

/// <summary>
/// Segredos de DESENVOLVIMENTO gerados na primeira execução e guardados fora do projeto
/// (Windows: %LOCALAPPDATA%\JogaBonito · Linux/macOS: ~/.local/share/JogaBonito).
/// Assim nenhum segredo fica no repositório: cada computador tem a sua chave JWT e a sua
/// chave de criptografia. Em produção os valores vêm de variáveis de ambiente / Key Vault.
/// </summary>
public static class SegredosLocais
{
    public static string Pasta { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData,
            Environment.SpecialFolderOption.Create), "JogaBonito");

    /// <summary>Lê o segredo <paramref name="nome"/>; se não existir, cria um aleatório de <paramref name="bytes"/> bytes.</summary>
    public static string ObterOuCriar(string nome, int bytes = 48)
    {
        if (!Regex.IsMatch(nome, "^[a-z0-9-]{1,40}$")) throw new ArgumentException("Nome de segredo inválido.", nameof(nome));
        Directory.CreateDirectory(Pasta);
        var arquivo = Path.Combine(Pasta, nome + ".chave");
        if (File.Exists(arquivo))
        {
            var lido = File.ReadAllText(arquivo).Trim();
            if (lido.Length >= 32) return lido;
        }

        var valor = Convert.ToBase64String(RandomNumberGenerator.GetBytes(bytes));
        // Grava só se outro processo não gravou ao mesmo tempo
        try
        {
            using (var fs = new FileStream(arquivo, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            using (var w = new StreamWriter(fs, new UTF8Encoding(false)))
                w.Write(valor);
            if (!OperatingSystem.IsWindows())
                File.SetUnixFileMode(arquivo, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        }
        catch (IOException) when (File.Exists(arquivo))
        {
            return File.ReadAllText(arquivo).Trim();
        }
        return valor;
    }
}

/// <summary>
/// Criptografia dos dados pessoais guardados no banco (endereço e telefone) com AES-256-GCM:
/// confidencialidade + integridade (um valor adulterado no banco não abre). Cada valor recebe
/// um nonce aleatório próprio, então o mesmo endereço gera textos cifrados diferentes.
///
/// Formato gravado: "enc1:" + Base64(nonce[12] | tag[16] | cifra).
/// Valores sem o prefixo (bancos antigos, dados de demonstração, "Removido (LGPD)") são lidos
/// como estão e cifrados na próxima inicialização.
/// </summary>
public sealed class ProtetorDados
{
    public const string Prefixo = "enc1:";
    private readonly byte[] _chave;

    public ProtetorDados(byte[] chave)
    {
        if (chave.Length != 32) throw new ArgumentException("A chave de criptografia precisa ter 32 bytes (AES-256).");
        _chave = chave;
    }

    /// <summary>Aceita a chave em Base64 (44 caracteres) como vem do Key Vault / .env.</summary>
    public static ProtetorDados DeBase64(string? base64)
    {
        if (string.IsNullOrWhiteSpace(base64))
            throw new InvalidOperationException("Dados:ChaveCriptografia não configurada (Base64 de 32 bytes).");
        byte[] bytes;
        try { bytes = Convert.FromBase64String(base64.Trim()); }
        catch (FormatException) { throw new InvalidOperationException("Dados:ChaveCriptografia não é Base64 válido."); }
        if (bytes.Length != 32) throw new InvalidOperationException("Dados:ChaveCriptografia precisa ter 32 bytes (gere com: openssl rand -base64 32).");
        return new ProtetorDados(bytes);
    }

    public static bool EstaProtegido(string? valor) => valor is not null && valor.StartsWith(Prefixo, StringComparison.Ordinal);

    public string? Proteger(string? texto)
    {
        if (texto is null || EstaProtegido(texto)) return texto;
        var dados = Encoding.UTF8.GetBytes(texto);
        var saida = new byte[12 + 16 + dados.Length];
        var nonce = saida.AsSpan(0, 12);
        RandomNumberGenerator.Fill(nonce);
        using var aes = new AesGcm(_chave, 16);
        aes.Encrypt(nonce, dados, saida.AsSpan(28), saida.AsSpan(12, 16));
        return Prefixo + Convert.ToBase64String(saida);
    }

    public string? Abrir(string? valor)
    {
        if (!EstaProtegido(valor)) return valor;
        var bytes = Convert.FromBase64String(valor![Prefixo.Length..]);
        if (bytes.Length < 28) throw new CryptographicException("Valor cifrado incompleto.");
        var texto = new byte[bytes.Length - 28];
        using var aes = new AesGcm(_chave, 16);
        aes.Decrypt(bytes.AsSpan(0, 12), bytes.AsSpan(28), bytes.AsSpan(12, 16), texto);
        return Encoding.UTF8.GetString(texto);
    }
}

/// <summary>Máscaras para mostrar dado pessoal só até onde a tela precisa (painel, consultas, logs).</summary>
public static class Mascara
{
    /// <summary>"matheus@estudante.com" → "ma*****@estudante.com".</summary>
    public static string Email(string? email)
    {
        if (string.IsNullOrEmpty(email)) return "";
        var arroba = email.IndexOf('@');
        if (arroba <= 0) return "***";
        var nome = email[..arroba];
        var visivel = nome.Length <= 2 ? nome[..1] : nome[..2];
        return visivel + new string('*', Math.Max(3, nome.Length - visivel.Length)) + email[arroba..];
    }

    /// <summary>IPv4 "200.150.10.27" → "200.150.10.x" · IPv6 mantém só o prefixo /48.</summary>
    public static string? Ip(string? ip)
    {
        if (string.IsNullOrEmpty(ip)) return ip;
        if (ip.Contains('.') && !ip.Contains(':'))
        {
            var p = ip.Split('.');
            return p.Length == 4 ? $"{p[0]}.{p[1]}.{p[2]}.x" : "x.x.x.x";
        }
        var partes = ip.Split(':', StringSplitOptions.RemoveEmptyEntries);
        return partes.Length >= 3 ? $"{partes[0]}:{partes[1]}:{partes[2]}::x" : "::x";
    }

    /// <summary>"(11) 98888-7777" → "(**) *****-7777".</summary>
    public static string? Telefone(string? telefone)
    {
        if (string.IsNullOrEmpty(telefone)) return telefone;
        var digitos = new string(telefone.Where(char.IsDigit).ToArray());
        return digitos.Length < 4 ? "****" : "(**) *****-" + digitos[^4..];
    }
}
