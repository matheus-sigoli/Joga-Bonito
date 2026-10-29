namespace JogaBonito.Api.Infrastructure.Seguranca;

/// <summary>
/// Sessão do SITE em cookie HttpOnly (o JavaScript não consegue ler o token, então um XSS não
/// consegue roubá-lo), SameSite=Strict (o navegador não envia o cookie em requisições vindas de
/// outros sites) e Secure sob HTTPS — com o prefixo __Host-, que impede sobrescrita por subdomínio.
///
/// O app Flutter não é navegador: continua recebendo o token no corpo e enviando em
/// "Authorization: Bearer" (guardado no Keystore/Keychain).
///
/// Proteção contra CSRF em duas camadas, além do SameSite:
///   1. toda requisição que altera dados e chega autenticada pelo cookie precisa do cabeçalho
///      X-JB-Requisicao: 1 — um formulário de outro site não consegue enviar cabeçalhos próprios,
///      e um fetch de outro site com cabeçalho próprio exige CORS, que a API não libera;
///   2. se o navegador informar a origem (Origin), ela precisa ser a própria loja ou uma origem
///      liberada em Cors:Origens.
/// </summary>
public static class CookieSessao
{
    public const string Nome = "jb_sessao";
    public const string NomeSeguro = "__Host-jb_sessao";
    public const string CabecalhoCliente = "X-JB-Cliente";
    public const string CabecalhoCsrf = "X-JB-Requisicao";

    /// <summary>O site se identifica no login; só ele recebe o cookie (e não recebe o token no corpo).</summary>
    public static bool EhSite(HttpRequest r) =>
        string.Equals(r.Headers[CabecalhoCliente], "web", StringComparison.OrdinalIgnoreCase);

    public static string? Ler(HttpRequest r) =>
        r.Cookies.TryGetValue(NomeSeguro, out var seguro) && !string.IsNullOrEmpty(seguro) ? seguro
        : r.Cookies.TryGetValue(Nome, out var comum) && !string.IsNullOrEmpty(comum) ? comum
        : null;

    public static void Gravar(HttpContext ctx, string token, DateTime expiraEmUtc)
    {
        var https = ctx.Request.IsHttps;
        ctx.Response.Cookies.Append(https ? NomeSeguro : Nome, token, new CookieOptions
        {
            HttpOnly = true,
            Secure = https,
            SameSite = SameSiteMode.Strict,
            Path = "/",
            Expires = new DateTimeOffset(DateTime.SpecifyKind(expiraEmUtc, DateTimeKind.Utc)),
            IsEssential = true
        });
    }

    public static void Apagar(HttpContext ctx)
    {
        foreach (var nome in new[] { Nome, NomeSeguro })
            if (ctx.Request.Cookies.ContainsKey(nome))
                ctx.Response.Cookies.Delete(nome, new CookieOptions
                {
                    Path = "/", Secure = nome == NomeSeguro || ctx.Request.IsHttps, HttpOnly = true, SameSite = SameSiteMode.Strict
                });
    }

    /// <summary>Middleware anti-CSRF (ver resumo da classe).</summary>
    public static Func<HttpContext, Func<Task>, Task> Middleware(IReadOnlyCollection<string> origensLiberadas, bool desenvolvimento) =>
        async (ctx, proximo) =>
        {
            var req = ctx.Request;
            var alteraDados = !(HttpMethods.IsGet(req.Method) || HttpMethods.IsHead(req.Method) || HttpMethods.IsOptions(req.Method));
            if (alteraDados && req.Path.StartsWithSegments("/api"))
            {
                var origem = req.Headers.Origin.ToString();
                if (!string.IsNullOrEmpty(origem) && !OrigemPermitida(origem, req, origensLiberadas, desenvolvimento))
                {
                    await Recusar(ctx, "Origem da requisição não permitida.");
                    return;
                }
                var porCookie = Ler(req) is not null && string.IsNullOrEmpty(req.Headers.Authorization);
                if (porCookie && req.Headers[CabecalhoCsrf] != "1")
                {
                    await Recusar(ctx, "Requisição recusada (proteção CSRF). Recarregue a página e tente de novo.");
                    return;
                }
            }
            await proximo();
        };

    public static bool OrigemPermitida(string origem, HttpRequest req, IReadOnlyCollection<string> liberadas, bool desenvolvimento)
    {
        if (string.Equals(origem, $"{req.Scheme}://{req.Host}", StringComparison.OrdinalIgnoreCase)) return true;
        if (liberadas.Any(o => string.Equals(o.TrimEnd('/'), origem, StringComparison.OrdinalIgnoreCase))) return true;
        // Em desenvolvimento o site pode vir do Live Server (localhost:5500) ou de um emulador local
        return desenvolvimento && Uri.TryCreate(origem, UriKind.Absolute, out var u) && u.IsLoopback;
    }

    private static Task Recusar(HttpContext ctx, string mensagem)
    {
        ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
        return ctx.Response.WriteAsJsonAsync(new { mensagem });
    }
}
