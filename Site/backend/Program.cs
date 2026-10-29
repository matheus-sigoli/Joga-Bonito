// ============================================================================
// JOGA BONITO — API REST .NET 8 (PIM IV · UNIP 2026/2)
// Composition root: registra as camadas, segurança e o pipeline HTTP.
//
//   Domain/          entidades e regras de negócio (POO: herança, encapsulamento)
//   Application/     DTOs, interfaces e serviços (casos de uso)
//   Infrastructure/  SQL Server (ADO.NET), JWT, BCrypt
//   Endpoints/       rotas HTTP agrupadas por módulo
//   Middleware/      tratamento de erros e cabeçalhos de segurança
// ============================================================================

using System.Globalization;
using System.IO.Compression;
using System.Security.Claims;
using System.Threading.RateLimiting;
using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Application.Servicos;
using JogaBonito.Api.Domain.Entidades;
using JogaBonito.Api.Endpoints;
using JogaBonito.Api.Infrastructure.Cache;
using JogaBonito.Api.Infrastructure.Dados;
using JogaBonito.Api.Infrastructure.Repositorios;
using JogaBonito.Api.Infrastructure.Seguranca;
using JogaBonito.Api.Middleware;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.ResponseCompression;
using Microsoft.Extensions.FileProviders;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;

CultureInfo.DefaultThreadCurrentCulture = new CultureInfo("pt-BR");
CultureInfo.DefaultThreadCurrentUICulture = new CultureInfo("pt-BR");

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;

// ---------------------------------------------------------------------------
// 1. Configurações
// ---------------------------------------------------------------------------
var connectionString = config.GetConnectionString("DefaultConnection")
    ?? throw new InvalidOperationException("ConnectionStrings:DefaultConnection não configurada.");

// Desenvolvimento: se o SQL Server configurado não responder, procura outro neste computador
// (SQL Express, instância padrão ou LocalDB) — a loja funciona pelo Visual Studio sem configurar nada.
string? avisoSql = null;
if (builder.Environment.IsDevelopment())
    (connectionString, avisoSql) = await LocalizadorSqlLocal.ResolverAsync(connectionString);

// Em produção a aplicação usa o usuário de privilégio mínimo de banco/seguranca.sql, nunca "sa"
var usuarioBanco = new Microsoft.Data.SqlClient.SqlConnectionStringBuilder(connectionString).UserID;
if (builder.Environment.IsProduction() && string.Equals(usuarioBanco, "sa", StringComparison.OrdinalIgnoreCase)
    && !config.GetValue("Banco:PermitirSa", false))
    throw new InvalidOperationException(
        "Produção conectada como 'sa'. Rode banco/seguranca.sql e use o usuário jogabonito_app na connection string.");

// Pasta "Site" (HTML/CSS/JS/IMG e scripts do banco). Em Docker: /app
var raizSite = Path.GetFullPath(config["Site:Raiz"] ?? Path.Combine(builder.Environment.ContentRootPath, ".."));

var jwt = config.GetSection("Jwt").Get<JwtOpcoes>() ?? new JwtOpcoes();
// Desenvolvimento sem chave configurada: cada computador gera a sua (fora do projeto), em vez de
// usar uma chave publicada no repositório — com ela qualquer pessoa forjaria um token de admin.
if (string.IsNullOrWhiteSpace(jwt.Chave) && builder.Environment.IsDevelopment())
    jwt.Chave = SegredosLocais.ObterOuCriar("jwt");
var chaveJwt = jwt.ChaveAssinatura(); // falha cedo se a chave estiver vazia ou curta

// Em produção a API se recusa a subir com a chave de exemplo publicada no repositório
if (builder.Environment.IsProduction() && JwtOpcoes.EhChaveDeExemplo(jwt.Chave))
    throw new InvalidOperationException(
        "Chave JWT de exemplo em produção. Defina a variável de ambiente Jwt__Chave com um segredo próprio (32+ caracteres).");

// Chave AES-256 dos dados pessoais cifrados no banco (endereço, telefone).
// Produção: Dados__ChaveCriptografia (Key Vault). Desenvolvimento: gerada por computador.
var chaveDados = config["Dados:ChaveCriptografia"];
if (string.IsNullOrWhiteSpace(chaveDados))
{
    if (!builder.Environment.IsDevelopment())
        throw new InvalidOperationException(
            "Dados:ChaveCriptografia não configurada. Gere com 'openssl rand -base64 32' e guarde no Key Vault " +
            "(variável Dados__ChaveCriptografia). Sem ela os endereços cifrados não podem ser lidos.");
    chaveDados = SegredosLocais.ObterOuCriar("dados", 32);
}
var protetorDados = ProtetorDados.DeBase64(chaveDados);

var forcarHttps = config.GetValue("Seguranca:ForcarHttps", false);
var origensCors = config.GetSection("Cors:Origens").Get<string[]>() ?? Array.Empty<string>();

// Limite de tamanho do corpo das requisições (nenhuma rota da loja precisa de mais que 1 MB)
builder.WebHost.ConfigureKestrel(o =>
{
    o.Limits.MaxRequestBodySize = 1_048_576;
    o.AddServerHeader = false;   // não anuncia "Server: Kestrel"
});

// ---------------------------------------------------------------------------
// 2. Injeção de dependências (camadas)
// ---------------------------------------------------------------------------
builder.Services.AddSingleton(jwt);
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton(protetorDados);
builder.Services.AddSingleton<IConexaoFactory>(
    new SqlConexaoFactory(connectionString, config.GetValue("Banco:TentativasConexao", 4)));

// Cache curto da vitrine (30 s), invalidado em alterações de produto, estoque e pedidos
builder.Services.AddMemoryCache(o => o.SizeLimit = 1000);
builder.Services.AddSingleton<ICacheCatalogo, CacheCatalogo>();
builder.Services.AddScoped<ValidadorSessao>();

builder.Services.AddScoped<IUsuarioRepositorio, UsuarioRepositorio>();
builder.Services.AddScoped<IProdutoRepositorio, ProdutoRepositorio>();
builder.Services.AddScoped<IPedidoRepositorio, PedidoRepositorio>();
builder.Services.AddScoped<IEstoqueRepositorio, EstoqueRepositorio>();
builder.Services.AddScoped<IRelatorioRepositorio, RelatorioRepositorio>();
builder.Services.AddScoped<IAvaliacaoRepositorio, AvaliacaoRepositorio>();
builder.Services.AddScoped<IPrivacidadeRepositorio, PrivacidadeRepositorio>();

builder.Services.AddSingleton<IHasherSenha, BCryptHasher>();
builder.Services.AddSingleton<IGeradorToken, JwtGeradorToken>();

builder.Services.AddScoped<AuthServico>();
// Termos que mandam uma avaliação para moderação (lista editável em appsettings › Moderacao)
var termosBloqueados = config.GetSection("Moderacao:TermosBloqueados").Get<string[]>() ?? Array.Empty<string>();
builder.Services.AddScoped(sp => new CatalogoServico(
    sp.GetRequiredService<IProdutoRepositorio>(), sp.GetRequiredService<ICacheCatalogo>(), termosBloqueados));
builder.Services.AddScoped<PrivacidadeServico>();
builder.Services.AddScoped<PedidoServico>();

// ---------------------------------------------------------------------------
// 3. Segurança: JWT, perfis, CORS e limite de tentativas de login
// ---------------------------------------------------------------------------
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.RequireHttpsMetadata = forcarHttps;
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwt.Emissor,
            ValidateAudience = true,
            ValidAudience = jwt.Publico,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = chaveJwt,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(1),
            NameClaimType = ClaimTypes.Name,
            RoleClaimType = ClaimTypes.Role
        };
        o.MapInboundClaims = true;
        o.Events = new JwtBearerEvents
        {
            // Site: o token vem do cookie HttpOnly. App: do cabeçalho Authorization (prioridade).
            OnMessageReceived = ctx =>
            {
                if (string.IsNullOrEmpty(ctx.Request.Headers.Authorization))
                    ctx.Token = CookieSessao.Ler(ctx.Request);
                return Task.CompletedTask;
            },
            // Assinatura válida não basta: confere no banco se a conta, o perfil e a versão do token valem
            OnTokenValidated = async ctx =>
            {
                var motivo = await ctx.HttpContext.RequestServices.GetRequiredService<ValidadorSessao>()
                    .ValidarAsync(ctx.Principal!);
                if (motivo is not null) ctx.Fail(motivo);
            },
            // 401 e 403 sempre em JSON { "mensagem": ... }, como o resto da API
            OnChallenge = async ctx =>
            {
                ctx.HandleResponse();
                if (ctx.Response.HasStarted) return;
                // Cookie com sessão que não vale mais (expirou, senha trocada): apaga do navegador
                if (ctx.AuthenticateFailure is not null) CookieSessao.Apagar(ctx.HttpContext);
                var motivo = ctx.AuthenticateFailure?.Message;
                ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await ctx.Response.WriteAsJsonAsync(new
                {
                    mensagem = string.IsNullOrEmpty(motivo) ? "Faça login para continuar."
                             : motivo.StartsWith("IDX") ? "Sua sessão expirou. Entre novamente." : motivo
                });
            },
            OnForbidden = ctx =>
            {
                ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
                return ctx.Response.WriteAsJsonAsync(new { mensagem = "Acesso restrito ao administrador." });
            }
        };
    });

builder.Services.AddAuthorization(o => o.AddPolicy("Admin", p => p.RequireRole("Admin")));

// CORS: o site é servido pela própria API (mesma origem). Em desenvolvimento qualquer origem é aceita
// (Live Server, emulador); em produção, só as origens listadas em Cors:Origens. O app Flutter não é
// navegador, então não depende de CORS.
builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
{
    var cabecalhos = new[] { "Authorization", "Content-Type", CookieSessao.CabecalhoCsrf, CookieSessao.CabecalhoCliente };
    if (origensCors.Length > 0)
        p.WithOrigins(origensCors).WithHeaders(cabecalhos).WithMethods("GET", "POST", "PUT", "DELETE").AllowCredentials();
    else if (builder.Environment.IsDevelopment())
        // Live Server / emulador no próprio computador: só origens locais, com cookie de sessão
        p.SetIsOriginAllowed(origem => Uri.TryCreate(origem, UriKind.Absolute, out var u) && u.IsLoopback)
         .WithHeaders(cabecalhos).WithMethods("GET", "POST", "PUT", "DELETE").AllowCredentials();
    // produção sem lista: nenhuma origem externa
}));

builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    // Limite geral por IP para toda a API (arquivos estáticos ficam fora): 300 requisições por minuto
    o.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(ctx =>
        ctx.Request.Path.StartsWithSegments("/api")
            ? RateLimitPartition.GetSlidingWindowLimiter(ctx.Connection.RemoteIpAddress?.ToString() ?? "anonimo",
                _ => new SlidingWindowRateLimiterOptions
                {
                    PermitLimit = config.GetValue("Seguranca:RequisicoesPorMinuto", 300),
                    Window = TimeSpan.FromMinutes(1), SegmentsPerWindow = 6, QueueLimit = 0
                })
            : RateLimitPartition.GetNoLimiter("estatico"));
    o.OnRejected = async (ctx, token) =>
    {
        ctx.HttpContext.Response.ContentType = "application/json";
        await ctx.HttpContext.Response.WriteAsync(
            "{\"mensagem\":\"Muitas tentativas em pouco tempo. Aguarde um minuto e tente de novo.\"}", token);
    };
    o.AddPolicy("login", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.Connection.RemoteIpAddress?.ToString() ?? "anonimo",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = config.GetValue("Seguranca:LoginsPorMinuto", 10), Window = TimeSpan.FromMinutes(1), QueueLimit = 0
        }));
    // Validação de cupom: impede descobrir códigos por tentativa e erro
    o.AddPolicy("cupom", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.Connection.RemoteIpAddress?.ToString() ?? "anonimo",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 20, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
    // Fechamento de pedido: por cliente (id do token) ou por IP
    o.AddPolicy("checkout", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.User.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? ctx.Connection.RemoteIpAddress?.ToString() ?? "anonimo",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = config.GetValue("Seguranca:PedidosPorMinuto", 15), Window = TimeSpan.FromMinutes(1), QueueLimit = 0
        }));
});

// Compressão das respostas (JSON, HTML, CSS, JS e SVG) — menos dados no celular
builder.Services.AddResponseCompression(o =>
{
    o.EnableForHttps = true; // exceto /api/auth (ver pipeline abaixo)
    o.Providers.Add<BrotliCompressionProvider>();
    o.Providers.Add<GzipCompressionProvider>();
    o.MimeTypes = ResponseCompressionDefaults.MimeTypes.Concat(new[] { "image/svg+xml" });
});
builder.Services.Configure<BrotliCompressionProviderOptions>(o => o.Level = CompressionLevel.Fastest);
builder.Services.Configure<GzipCompressionProviderOptions>(o => o.Level = CompressionLevel.Fastest);

// Atrás de proxy/balanceador (Azure App Service, Nginx): usa o IP real do cliente e o esquema HTTPS
builder.Services.Configure<ForwardedHeadersOptions>(o =>
{
    o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    if (config.GetValue("Seguranca:ConfiarProxy", false))
    {
        o.KnownNetworks.Clear();
        o.KnownProxies.Clear();
    }
});

if (forcarHttps)
    builder.Services.AddHsts(o => { o.MaxAge = TimeSpan.FromDays(180); o.IncludeSubDomains = true; });

// ---------------------------------------------------------------------------
// 4. Documentação (Swagger) e monitoramento (health check)
// ---------------------------------------------------------------------------
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(o =>
{
    o.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Joga Bonito API",
        Version = "v1",
        Description = "API REST da loja Joga Bonito — PIM IV UNIP 2026/2"
    });
    var esquema = new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
    };
    o.AddSecurityDefinition("Bearer", esquema);
    o.AddSecurityRequirement(new OpenApiSecurityRequirement { [esquema] = Array.Empty<string>() });
});

builder.Services.AddSingleton<EstadoBanco>();
builder.Services.AddHostedService<RotinaRetencao>();   // apaga logs de acesso com mais de 180 dias

// Catálogo local (Javascript/catalogo-local.js) → banco, ao iniciar e sempre que o arquivo for salvo
var sincronizarCatalogo = config.GetValue("Banco:SincronizarCatalogoLocal", false);
if (sincronizarCatalogo)
{
    builder.Services.AddSingleton(sp => new SincronizadorCatalogoLocal(connectionString,
        Path.Combine(raizSite, "Javascript", "catalogo-local.js"),
        sp.GetRequiredService<ILogger<SincronizadorCatalogoLocal>>()));
    builder.Services.AddHostedService<ObservadorCatalogoLocal>();

    // Fotos: o que estiver em IMG/Produtos/<id>/ vira a galeria do produto (ao iniciar e a cada mudança)
    builder.Services.AddSingleton(sp => new SincronizadorImagens(connectionString,
        Path.Combine(raizSite, "IMG", "Produtos"), sp.GetRequiredService<ILogger<SincronizadorImagens>>()));
    builder.Services.AddHostedService<ObservadorImagens>();
}

// Monitoramento na nuvem: requisições, dependências SQL, exceções e métricas vão para o
// Application Insights quando APPLICATIONINSIGHTS_CONNECTION_STRING está configurada (Azure).
if (!string.IsNullOrWhiteSpace(config["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
    builder.Services.AddOpenTelemetry().UseAzureMonitor();
builder.Services.AddHealthChecks().AddCheck<SqlHealthCheck>("sqlserver", tags: new[] { "pronto" });

var app = builder.Build();

// ---------------------------------------------------------------------------
// 5. Banco de dados: cria/atualiza estrutura e carga inicial
// ---------------------------------------------------------------------------
//    Desenvolvimento: cria tudo sozinho (schema + seed + demo).
//    Produção: Banco:CriarAutomaticamente=false — o usuário restrito da aplicação não tem
//    permissão de DDL; os scripts rodam uma vez com uma conta administrativa (ver README).
if (avisoSql is not null) app.Logger.LogWarning("{Aviso}", avisoSql);

var estadoBanco = app.Services.GetRequiredService<EstadoBanco>();
async Task PrepararBancoAsync()
{
    if (config.GetValue("Banco:CriarAutomaticamente", false))
    {
        var inicializador = new InicializadorBanco(connectionString, Path.Combine(raizSite, "banco"),
            config.GetValue("Banco:CarregarDemonstracao", false),
            app.Services.GetRequiredService<ILogger<InicializadorBanco>>());
        await inicializador.ExecutarAsync(estadoBanco);
    }
    if (!estadoBanco.Sucesso) return;

    if (sincronizarCatalogo)
    {
        try
        {
            await app.Services.GetRequiredService<SincronizadorCatalogoLocal>()
                .SincronizarAsync(app.Services.GetRequiredService<ICacheCatalogo>());
        }
        catch (Exception ex)
        {
            app.Logger.LogWarning("catalogo-local.js não foi levado ao banco: {Erro}", ex.Message);
        }
    }
    if (sincronizarCatalogo)
    {
        try
        {
            await app.Services.GetRequiredService<SincronizadorImagens>()
                .SincronizarAsync(app.Services.GetRequiredService<ICacheCatalogo>());
        }
        catch (Exception ex)
        {
            app.Logger.LogWarning("Fotos das pastas não foram levadas ao banco: {Erro}", ex.Message);
        }
    }
    // Endereços e telefones gravados antes da criptografia (ou pelos dados de demonstração) são cifrados agora
    await MigradorCriptografia.ExecutarAsync(app.Services.GetRequiredService<IConexaoFactory>(), protetorDados, app.Logger);
}
await PrepararBancoAsync();

// Desenvolvimento: se o banco não ficou pronto (SQL Server ainda ligando junto com o Windows, serviço
// parado), a API continua no ar e tenta de novo a cada 20 s — quando der certo, o login passa a funcionar
// sem reiniciar nada. /health/ready mostra o motivo enquanto isso.
if (!estadoBanco.Sucesso && app.Environment.IsDevelopment() && config.GetValue("Banco:CriarAutomaticamente", false))
{
    _ = Task.Run(async () =>
    {
        var parar = app.Lifetime.ApplicationStopping;
        while (!estadoBanco.Sucesso && !parar.IsCancellationRequested)
        {
            try { await Task.Delay(TimeSpan.FromSeconds(20), parar); } catch (OperationCanceledException) { return; }
            app.Logger.LogInformation("Tentando preparar o banco de novo...");
            await PrepararBancoAsync();
        }
        if (estadoBanco.Sucesso) app.Logger.LogInformation("Banco pronto: a loja já aceita login.");
    });
}

// Administrador inicial vindo do ambiente (produção não tem contas com senha pública)
await GarantirAdministradorAsync(app, config);

// ---------------------------------------------------------------------------
// 6. Pipeline HTTP
// ---------------------------------------------------------------------------
app.UseForwardedHeaders();
app.UseMiddleware<TratamentoErrosMiddleware>();
app.UseMiddleware<CabecalhosSegurancaMiddleware>();

if (forcarHttps)
{
    app.UseHsts();               // navegador passa a usar só HTTPS por 180 dias
    app.UseHttpsRedirection();
}

app.UseResponseCompression();
// Respostas de login/troca de senha carregam o token: nunca comprimir sob HTTPS (ataque BREACH)
app.Use((ctx, proximo) =>
{
    if (ctx.Request.Path.StartsWithSegments("/api/auth") &&
        ctx.Features.Get<Microsoft.AspNetCore.Http.Features.IHttpsCompressionFeature>() is { } f)
        f.Mode = Microsoft.AspNetCore.Http.Features.HttpsCompressionMode.DoNotCompress;
    return proximo(ctx);
});

// Front-end servido pela própria API — somente as pastas públicas
// (o código do backend e os scripts SQL NÃO ficam acessíveis pelo navegador)
foreach (var pasta in new[] { "HTML", "CSS", "Javascript", "IMG" })
{
    var caminho = Path.Combine(raizSite, pasta);
    if (Directory.Exists(caminho))
        app.UseStaticFiles(new StaticFileOptions
        {
            FileProvider = new PhysicalFileProvider(caminho),
            RequestPath = "/" + pasta,
            // Imagens podem ficar 7 dias no navegador; HTML/CSS/JS são revalidados a cada acesso
            OnPrepareResponse = ctx => ctx.Context.Response.Headers.CacheControl =
                pasta == "IMG" ? "public, max-age=604800" : "no-cache"
        });
}

app.UseCors();
app.Use(CookieSessao.Middleware(origensCors, app.Environment.IsDevelopment()));
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

// Documentação interativa: ligada em desenvolvimento; em produção só com Swagger:Habilitado=true
if (app.Environment.IsDevelopment() || config.GetValue("Swagger:Habilitado", false))
{
    app.UseSwagger();
    app.UseSwaggerUI(o => o.DocumentTitle = "Joga Bonito API");
}

app.MapGet("/", () => Results.Redirect("/HTML/inicial.html")).ExcludeFromDescription();
// Monitoramento: /health/live = processo no ar · /health/ready = API + banco prontos
app.MapHealthChecks("/health");
app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false });
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = c => c.Tags.Contains("pronto"),
    // JSON com o estado de cada conexão (usado pelo painel admin e pelo app em Perfil › Servidor)
    ResponseWriter = (ctx, relatorio) =>
        // Detalhes (nomes de objetos, mensagens do SQL Server) só para o admin ou em desenvolvimento;
        // para o resto do mundo, apenas o estado — sem pistas da infraestrutura.
        !app.Environment.IsDevelopment() && !ctx.User.IsInRole("Admin")
        ? ctx.Response.WriteAsJsonAsync(new { status = relatorio.Status.ToString() })
        : ctx.Response.WriteAsJsonAsync(new StatusConexaoResponse(
        relatorio.Status.ToString(),
        relatorio.Entries.Select(e => new StatusComponenteResponse(e.Key, e.Value.Status.ToString(),
            e.Value.Description, Math.Round(e.Value.Duration.TotalMilliseconds, 1))).ToList(),
        Math.Round(relatorio.TotalDuration.TotalMilliseconds, 1)))
});

app.MapAuth();
app.MapCatalogo();
app.MapPedidos();
app.MapAdmin();

try
{
    app.Run();
}
catch (IOException ex) when (ex.Message.Contains("address already in use", StringComparison.OrdinalIgnoreCase)
                             || ex.InnerException is System.Net.Sockets.SocketException)
{
    // Comum em desenvolvimento: a API já está no ar (início automático com o Windows ou outra janela).
    // Direto no console: aqui o host já foi descartado e o app.Logger lançaria ObjectDisposedException.
    Console.Error.WriteLine(
        "A porta já está em uso — a loja provavelmente JÁ ESTÁ NO AR (http://localhost:5000). " +
        $"Para depurar pelo Visual Studio/VS Code, rode parar-projeto.bat antes. Detalhe: {ex.Message}");
    Environment.ExitCode = 1;
}

/// <summary>Exposto para testes de integração (WebApplicationFactory).</summary>
public partial class Program
{
    /// <summary>
    /// Cria o administrador definido em Banco:AdminEmail / Banco:AdminSenha se ele ainda não existir.
    /// A senha é gravada só como hash BCrypt; depois do primeiro login, troque-a pelo site.
    /// </summary>
    private static async Task GarantirAdministradorAsync(WebApplication app, IConfiguration config)
    {
        var email = Usuario.NormalizarEmail(config["Banco:AdminEmail"]);
        var senha = config["Banco:AdminSenha"];
        if (string.IsNullOrEmpty(email) || string.IsNullOrEmpty(senha)) return;
        try
        {
            Usuario.ValidarForcaSenha(senha, email);
            await using var escopo = app.Services.CreateAsyncScope();
            var usuarios = escopo.ServiceProvider.GetRequiredService<IUsuarioRepositorio>();
            if (await usuarios.EmailExisteAsync(email)) return;
            var hasher = escopo.ServiceProvider.GetRequiredService<IHasherSenha>();
            await usuarios.InserirAsync(Usuario.NovoAdministrador("Administrador Joga Bonito", email, hasher.GerarHash(senha)));
            app.Logger.LogInformation("Administrador inicial {Email} criado.", email);
        }
        catch (Exception ex)
        {
            app.Logger.LogError(ex, "Não foi possível criar o administrador inicial {Email}.", email);
        }
    }
}
