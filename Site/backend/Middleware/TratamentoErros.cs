using JogaBonito.Api.Domain.Excecoes;

namespace JogaBonito.Api.Middleware;

/// <summary>
/// Converte exceções em respostas JSON padronizadas: { "mensagem": "..." }.
/// Erros inesperados são registrados no log e não expõem detalhes internos ao cliente.
/// </summary>
public class TratamentoErrosMiddleware
{
    private readonly RequestDelegate _proximo;
    private readonly ILogger<TratamentoErrosMiddleware> _log;

    public TratamentoErrosMiddleware(RequestDelegate proximo, ILogger<TratamentoErrosMiddleware> log)
    {
        _proximo = proximo;
        _log = log;
    }

    public async Task InvokeAsync(HttpContext contexto)
    {
        try
        {
            await _proximo(contexto);
        }
        catch (Exception ex) when (!contexto.Response.HasStarted)
        {
            var (status, mensagem) = ex switch
            {
                RegraNegocioException => (StatusCodes.Status400BadRequest, ex.Message),
                BadHttpRequestException => (StatusCodes.Status400BadRequest, "Requisição inválida: verifique os dados enviados."),
                RecursoNaoEncontradoException => (StatusCodes.Status404NotFound, ex.Message),
                ContaBloqueadaException => (StatusCodes.Status423Locked, ex.Message),
                AcessoNegadoException when contexto.User.Identity?.IsAuthenticated != true
                    => (StatusCodes.Status401Unauthorized, ex.Message),
                AcessoNegadoException => (StatusCodes.Status403Forbidden, ex.Message),
                UnauthorizedAccessException => (StatusCodes.Status401Unauthorized, "Sessão inválida. Entre novamente."),
                _ => (StatusCodes.Status500InternalServerError, "Erro interno. Tente novamente em instantes.")
            };

            contexto.Response.StatusCode = status;
            if (status == StatusCodes.Status500InternalServerError)
            {
                // O cliente recebe só um código para o suporte; o detalhe fica no log do servidor
                _log.LogError(ex, "Erro não tratado {Codigo} em {Metodo} {Caminho}",
                    contexto.TraceIdentifier, contexto.Request.Method, contexto.Request.Path);
                await contexto.Response.WriteAsJsonAsync(new { mensagem, codigo = contexto.TraceIdentifier });
                return;
            }
            await contexto.Response.WriteAsJsonAsync(new { mensagem });
        }
    }
}

/// <summary>
/// Cabeçalhos HTTP de segurança (OWASP Secure Headers), incluindo a
/// Content-Security-Policy: o navegador só executa scripts do próprio site e do VLibras,
/// o que neutraliza a maior parte dos ataques de XSS mesmo se algum texto escapar sem tratamento.
/// </summary>
public class CabecalhosSegurancaMiddleware
{
    /// <summary>
    /// 'unsafe-eval'/'wasm-unsafe-eval' e blob: são exigidos pelo widget VLibras (Unity WebGL);
    /// 'unsafe-inline' em estilos cobre os atributos style="" das páginas. Nenhum script inline é permitido.
    /// </summary>
    public const string Csp =
        "default-src 'self'; " +
        "script-src 'self' https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/ 'unsafe-eval' 'wasm-unsafe-eval'; " +
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/; " +
        "font-src 'self' data: https://fonts.gstatic.com https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/; " +
        "img-src 'self' data: blob: https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/; " +
        "media-src 'self' blob: https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/; " +
        "connect-src 'self' https://viacep.com.br https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/; " +
        "worker-src 'self' blob:; " +
        "frame-src 'self' https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/; " +
        "object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self'";

    private readonly RequestDelegate _proximo;

    public CabecalhosSegurancaMiddleware(RequestDelegate proximo) => _proximo = proximo;

    public Task InvokeAsync(HttpContext contexto)
    {
        var h = contexto.Response.Headers;
        h["X-Content-Type-Options"] = "nosniff";
        h["X-Frame-Options"] = "SAMEORIGIN";
        h["Referrer-Policy"] = "strict-origin-when-cross-origin";
        h["Permissions-Policy"] = "camera=(), microphone=(), geolocation=(), payment=()";
        h["Cross-Origin-Opener-Policy"] = "same-origin";

        // O Swagger UI usa scripts inline próprios: a CSP vale para a loja, não para a documentação
        if (!contexto.Request.Path.StartsWithSegments("/swagger"))
            h["Content-Security-Policy"] = Csp;

        // Respostas da API com dados pessoais (pedidos, perfil, admin) nunca ficam em cache
        if (contexto.Request.Path.StartsWithSegments("/api") &&
            !contexto.Request.Path.StartsWithSegments("/api/produtos") &&
            !contexto.Request.Path.StartsWithSegments("/api/categorias"))
            h["Cache-Control"] = "no-store";

        return _proximo(contexto);
    }
}
