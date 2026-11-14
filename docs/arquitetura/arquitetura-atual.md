# Arquitetura Atual — Joga Bonito (PIM IV)

## Stack
- Frontend : HTML5, CSS3 (design system base.css + paginas.css), JavaScript (api.js, layout.js + scripts por página)
- Backend  : ASP.NET Core 8 Minimal APIs em camadas (Domain / Application / Infrastructure / Endpoints)
- Banco    : SQL Server — JogaBonitoDB (12 tabelas, 3 views, 1 função, 6 procedures, 3 triggers)
- Mobile   : Flutter (Dart) — mesma API
- Infra    : Docker multi-stage, Docker Compose, GitHub Actions, plano Azure (App Service + Azure SQL)

## Componentes
| Componente | Responsabilidade |
|---|---|
| Domain | Entidades e regras: Produto→Camisa/Chuteira, Pedido, Cupom, RegraFrete, StatusPedido |
| Application | DTOs, interfaces de repositório/segurança, AuthServico, CatalogoServico, PedidoServico |
| Infrastructure | Repositórios ADO.NET parametrizados, InicializadorBanco, JwtGeradorToken, BCryptHasher, SqlHealthCheck |
| Endpoints | /api/auth, /api/produtos, /api/pedidos, /api/admin (política Admin) |

## Fluxo principal (compra)
1. Front/App → POST /api/pedidos/simular (preços oficiais, cupom, frete)
2. POST /api/pedidos → sp_RegistrarPedido (transação, UPDLOCK no estoque)
3. INSERT ItensPedido → trg_BaixaEstoqueAposPedido → trg_AuditoriaEstoque
4. INSERT/UPDATE Pedidos → trg_HistoricoStatusPedido (linha do tempo)

## Decisões arquiteturais
- Id do comprador sempre vem do token JWT.
- Console SQL livre removido: painel usa consultas pré-definidas somente-leitura.
- Front servido pela API apenas nas pastas HTML/CSS/Javascript/IMG.
- Senhas apenas em hash BCrypt (texto puro nunca autentica).

## Dívidas técnicas conhecidas
- Pagamento simulado (sem gateway real).
- Upload de imagens pelo painel ainda não implementado (URLs manuais).
