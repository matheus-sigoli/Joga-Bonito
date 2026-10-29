using System.Security.Claims;
using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Application.Servicos;
using JogaBonito.Api.Domain.Entidades;
using JogaBonito.Api.Infrastructure.Seguranca;

namespace JogaBonito.Api.Endpoints;

// ============================================================================
// ROTAS DA API REST — cada módulo registra seu grupo de endpoints.
//   /api/auth      → login, cadastro, perfil, troca de senha (público / autenticado)
//   /api/...       → catálogo, avaliações, cupons         (público)
//   /api/pedidos   → checkout e histórico                 (cliente autenticado)
//   /api/admin     → dashboard, estoque, pedidos, produtos, log de acessos (somente Admin)
// ============================================================================

public static class AuthEndpoints
{
    public static RouteGroupBuilder MapAuth(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/api/auth").WithTags("Autenticação");

        g.MapPost("/login", async (LoginRequest req, HttpContext ctx, AuthServico auth) =>
                Results.Ok(EntregarSessao(ctx, await auth.LoginAsync(req, ctx.Connection.RemoteIpAddress?.ToString()))))
         .RequireRateLimiting("login")
         .WithSummary("Autentica. App: token JWT no corpo. Site (X-JB-Cliente: web): cookie HttpOnly, sem token no corpo. " +
                      "5 senhas erradas bloqueiam a conta por 15 min");

        g.MapPost("/sair", (HttpContext ctx) =>
            {
                CookieSessao.Apagar(ctx);
                return Results.NoContent();
            })
         .WithSummary("Encerra a sessão do site (apaga o cookie)");

        g.MapPost("/cadastro", async (CadastroRequest req, AuthServico auth) =>
            Results.Created("/api/auth/me", await auth.CadastrarAsync(req)))
         .RequireRateLimiting("login")
         .WithSummary("Cria conta de cliente (senha com hash BCrypt)");

        g.MapGet("/me", async (ClaimsPrincipal user, AuthServico auth) =>
            Results.Ok(await auth.ObterPerfilAsync(user.UsuarioId())))
         .RequireAuthorization()
         .WithSummary("Dados do usuário logado");

        g.MapPost("/trocar-senha", async (TrocarSenhaRequest req, HttpContext ctx, ClaimsPrincipal user, AuthServico auth,
                ValidadorSessao sessoes) =>
            {
                var id = user.UsuarioId();
                var novaSessao = await auth.TrocarSenhaAsync(id, req);
                sessoes.Invalidar(id);
                return Results.Ok(EntregarSessao(ctx, novaSessao));
            })
         .RequireAuthorization()
         .RequireRateLimiting("login")
         .WithSummary("Troca a senha (exige a atual), encerra as outras sessões e devolve um token novo");

        g.MapPost("/sair-de-todos", async (HttpContext ctx, ClaimsPrincipal user, AuthServico auth, ValidadorSessao sessoes) =>
            {
                var id = user.UsuarioId();
                await auth.SairDeTodosAsync(id);
                sessoes.Invalidar(id);
                CookieSessao.Apagar(ctx);
                return Results.NoContent();
            })
         .RequireAuthorization()
         .WithSummary("Encerra a sessão em todos os aparelhos (invalida todos os tokens emitidos)");

        // ---- LGPD: direitos do titular ----
        g.MapGet("/meus-dados", async (ClaimsPrincipal user, PrivacidadeServico s) =>
                Results.Ok(await s.ExportarAsync(user.UsuarioId())))
         .RequireAuthorization()
         .WithSummary("Exporta todos os dados pessoais do usuário logado (LGPD art. 18)");

        g.MapPost("/excluir-conta", async (ExcluirContaRequest req, HttpContext ctx, ClaimsPrincipal user, PrivacidadeServico s,
                ValidadorSessao sessoes) =>
            {
                var id = user.UsuarioId();
                await s.ExcluirContaAsync(id, req);
                sessoes.Invalidar(id);
                CookieSessao.Apagar(ctx);
                return Results.NoContent();
            })
         .RequireAuthorization()
         .RequireRateLimiting("login")
         .WithSummary("Exclui a conta (anonimiza os dados pessoais; pedidos ficam por obrigação fiscal)");

        return g;
    }

    /// <summary>Site recebe a sessão em cookie HttpOnly (e o corpo vai sem token); o app recebe o token.</summary>
    private static LoginResponse EntregarSessao(HttpContext ctx, LoginResponse sessao)
    {
        if (!CookieSessao.EhSite(ctx.Request)) return sessao;
        CookieSessao.Gravar(ctx, sessao.Token, sessao.ExpiraEm);
        return sessao with { Token = string.Empty };
    }
}

public static class CatalogoEndpoints
{
    public static RouteGroupBuilder MapCatalogo(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/api").WithTags("Catálogo");

        g.MapGet("/categorias", async (CatalogoServico s) => Results.Ok(await s.CategoriasAsync()));

        g.MapGet("/produtos", async (string? categoria, string? linha, string? busca, string? ordem, bool? destaque,
                string? marca, decimal? precoMax, CatalogoServico s) =>
            Results.Ok(await s.ListarAsync(new FiltroProdutos(categoria, linha, busca, ordem, destaque, marca, precoMax))))
         .WithSummary("Lista produtos com filtros: categoria (slug), linha, marca, precoMax, busca, ordem, destaque");

        g.MapGet("/produtos/{id:int}", async (int id, CatalogoServico s) => Results.Ok(await s.DetalharAsync(id)))
         .WithSummary("Detalhe do produto com galeria e estoque por tamanho");

        g.MapGet("/produtos/{id:int}/avaliacoes", async (int id, CatalogoServico s) =>
            Results.Ok(await s.AvaliacoesAsync(id)));

        g.MapPost("/produtos/{id:int}/avaliacoes", async (int id, AvaliacaoRequest req, ClaimsPrincipal user,
                CatalogoServico s) =>
                Results.Ok(await s.AvaliarAsync(id, user.UsuarioId(), req)))
         .RequireAuthorization()
         .WithSummary("Avalia um produto já comprado (nota de 1 a 5); textos com link ou termo bloqueado vão para moderação");

        g.MapPost("/cupons/validar", async (ValidarCupomRequest req, PedidoServico s) =>
            Results.Ok(await s.ValidarCupomAsync(req)))
         .RequireRateLimiting("cupom");

        return g;
    }
}

public static class PedidoEndpoints
{
    public static RouteGroupBuilder MapPedidos(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/api/pedidos").WithTags("Pedidos").RequireAuthorization();

        g.MapPost("/simular", async (SimularPedidoRequest req, PedidoServico s) => Results.Ok(await s.SimularAsync(req)))
         .WithSummary("Calcula subtotal, desconto, frete e total sem gravar");

        g.MapPost("", async (CriarPedidoRequest req, ClaimsPrincipal user, PedidoServico s) =>
            {
                // O id do comprador vem do TOKEN, nunca do corpo da requisição
                var criado = await s.CriarAsync(user.UsuarioId(), req);
                return Results.Created($"/api/pedidos/{criado.PedidoId}", criado);
            })
         .RequireRateLimiting("checkout")
         .WithSummary("Fecha o pedido (procedure transacional + trigger de baixa de estoque)");

        g.MapGet("/meus", async (ClaimsPrincipal user, PedidoServico s) =>
            Results.Ok(await s.MeusPedidosAsync(user.UsuarioId())));

        g.MapGet("/{id:int}", async (int id, ClaimsPrincipal user, PedidoServico s) =>
            Results.Ok(await s.ObterAsync(id, user.UsuarioId(), user.EhAdmin())));

        g.MapPost("/{id:int}/cancelar", async (int id, ClaimsPrincipal user, PedidoServico s) =>
            {
                await s.CancelarPeloClienteAsync(id, user.UsuarioId());
                return Results.NoContent();
            })
         .WithSummary("Cliente cancela o pedido antes da separação (estoque é devolvido)");

        return g;
    }
}

public static class AdminEndpoints
{
    public static RouteGroupBuilder MapAdmin(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/api/admin").WithTags("Administração").RequireAuthorization("Admin");

        g.MapGet("/dashboard", async (IRelatorioRepositorio r) => Results.Ok(await r.DashboardAsync()));

        // ---- Estoque ----
        g.MapGet("/estoque", async (IEstoqueRepositorio e) => Results.Ok(await e.RelatorioAsync()));

        g.MapPut("/estoque", async (AtualizarEstoqueRequest req, ClaimsPrincipal user, IEstoqueRepositorio e,
                ICacheCatalogo cache) =>
            {
                if (req.Quantidade is < 0 or > 9999)
                    return Results.BadRequest(new { mensagem = "Quantidade deve estar entre 0 e 9999." });
                var origem = $"Painel Admin ({user.FindFirst(ClaimTypes.Email)?.Value})";
                await e.AtualizarAsync(req.ProdutoId, req.Tamanho.Trim().ToUpperInvariant(), req.Quantidade, origem);
                cache.Invalidar();
                return Results.NoContent();
            })
         .WithSummary("Ajusta o saldo de um tamanho (sp_AtualizarEstoque + trigger de auditoria)");

        g.MapGet("/estoque/auditoria", async (int? limite, IEstoqueRepositorio e) =>
            Results.Ok(await e.AuditoriaAsync(Math.Clamp(limite ?? 50, 1, 500))));

        // ---- Pedidos ----
        g.MapGet("/pedidos", async (string? status, PedidoServico s) => Results.Ok(await s.ListarTodosAsync(status)));

        g.MapPut("/pedidos/{id:int}/status", async (int id, AtualizarStatusRequest req, PedidoServico s) =>
            {
                await s.AtualizarStatusAsync(id, req.Status);
                return Results.NoContent();
            });

        // ---- Produtos ----
        g.MapPost("/produtos", async (SalvarProdutoRequest req, CatalogoServico s) =>
            {
                var id = await s.CriarAsync(req);
                return Results.Created($"/api/produtos/{id}", new { id });
            });

        g.MapPut("/produtos/{id:int}", async (int id, SalvarProdutoRequest req, CatalogoServico s) =>
            {
                await s.AtualizarAsync(id, req);
                return Results.NoContent();
            });

        g.MapDelete("/produtos/{id:int}", async (int id, CatalogoServico s) =>
            {
                await s.DesativarAsync(id);
                return Results.NoContent();
            })
         .WithSummary("Exclusão lógica (Ativo = 0), preservando o histórico de vendas");

        // ---- Moderação de avaliações ----
        g.MapGet("/avaliacoes", async (string? status, IAvaliacaoRepositorio r) =>
            {
                if (status is not null && status is not ("Publicada" or "Pendente" or "Oculta"))
                    return Results.BadRequest(new { mensagem = "Status inválido. Use Publicada, Pendente ou Oculta." });
                return Results.Ok(await r.ListarAsync(status, 200));
            })
         .WithSummary("Avaliações para moderação (pendentes primeiro)");

        g.MapPut("/avaliacoes/{id:int}", async (int id, ModerarAvaliacaoRequest req, ClaimsPrincipal user,
                IAvaliacaoRepositorio r, ICacheCatalogo cache) =>
            {
                if (!ModeracaoAvaliacao.StatusDeModeracaoValido(req.Status))
                    return Results.BadRequest(new { mensagem = "Use Publicada ou Oculta." });
                var motivo = req.Motivo?.Trim();
                if (motivo is { Length: > 200 })
                    return Results.BadRequest(new { mensagem = "O motivo pode ter no máximo 200 caracteres." });
                await r.ModerarAsync(id, req.Status, user.UsuarioId(), motivo);
                cache.Invalidar(); // nota média e lista de avaliações da vitrine mudam
                return Results.NoContent();
            })
         .WithSummary("Publica ou oculta uma avaliação (sp_ModerarAvaliacao registra quem, quando e por quê)");

        // ---- Segurança ----
        g.MapGet("/acessos", async (int? limite, IRelatorioRepositorio r) =>
            Results.Ok(await r.AcessosAsync(Math.Clamp(limite ?? 50, 1, 500))))
         .WithSummary("Log de tentativas de login (sucesso/falha, IP, data)");

        // ---- Console do banco (somente consultas pré-definidas) ----
        g.MapGet("/consultas", (IRelatorioRepositorio r) => Results.Ok(r.ConsultasDisponiveis()));
        g.MapGet("/consultas/{nome}", async (string nome, IRelatorioRepositorio r) =>
            Results.Ok(await r.ExecutarConsultaAsync(nome)));

        return g;
    }
}
