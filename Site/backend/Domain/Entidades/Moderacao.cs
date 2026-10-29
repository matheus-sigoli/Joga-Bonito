using System.Text.RegularExpressions;

namespace JogaBonito.Api.Domain.Entidades;

/// <summary>
/// Regras de moderação das avaliações (responsabilidade social: combate a conteúdo
/// ofensivo ou discriminatório). Comentários com link, contato pessoal ou termos da lista
/// de bloqueio não são publicados direto: entram como "Pendente" para o administrador revisar.
/// </summary>
public static class ModeracaoAvaliacao
{
    public const string Publicada = "Publicada";
    public const string Pendente = "Pendente";
    public const string Oculta = "Oculta";

    private static readonly Regex LinkOuContato = new(
        @"(https?://|www\.|\b[\w.-]+\.(com|net|org|br)\b|[\w.+-]+@[\w-]+\.\w+|(\d[\s.-]?){8,})",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    /// <summary>Situação com que a avaliação entra no banco.</summary>
    public static string StatusInicial(string? comentario, IEnumerable<string> termosBloqueados)
    {
        if (string.IsNullOrWhiteSpace(comentario)) return Publicada;
        if (LinkOuContato.IsMatch(comentario)) return Pendente;

        var texto = Normalizar(comentario);
        return termosBloqueados
            .Select(Normalizar)
            .Where(t => t.Length > 0)
            .Any(t => Regex.IsMatch(texto, $@"\b{Regex.Escape(t)}\b")) ? Pendente : Publicada;
    }

    public static bool StatusDeModeracaoValido(string? status) => status is Publicada or Oculta;

    /// <summary>Minúsculas e sem acentos, para "Idióta" e "idiota" serem o mesmo termo.</summary>
    private static string Normalizar(string texto)
    {
        var decomposto = texto.ToLowerInvariant().Normalize(System.Text.NormalizationForm.FormD);
        return new string(decomposto.Where(c =>
            System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c) != System.Globalization.UnicodeCategory.NonSpacingMark).ToArray());
    }
}
