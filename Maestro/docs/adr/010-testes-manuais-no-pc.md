# ADR 010 — Testes manuais no PC: pedido idempotente, foco no checkout, reflow e lançador em PC lento

**Data:** 11/11/2026 · **Situação:** aceita e aplicada

## Contexto
A lista de testes manuais (sessões 1 e 3 do checklist final) foi executada num PC real do grupo
(Windows, SQL Server Express, Wi-Fi 192.168.1.x), com o computador **muito carregado**: `/health/live`,
que nem toca no banco, chegou a levar 2 s, e o login e o pedido passaram de 10 s. Quatro falhas apareceram
que os testes automáticos (CI em máquina rápida) não pegavam:

| # | O que aconteceu | Risco |
|---|---|---|
| 1 | O site desistiu do `POST /api/pedidos` após 10 s e mostrou "reconectando"; o pedido **#17 foi gravado** mesmo assim. | O cliente confirma de novo e **compra duas vezes** (estoque baixado em dobro). Vale também para o app em Wi-Fi ruim. |
| 2 | No checkout, ao passar de Endereço para Pagamento (e ao confirmar), o foco saía da janela e ia para "Pular para o conteúdo". | Quem usa teclado ou leitor de tela fica perdido no meio da compra (WCAG 2.4.3). |
| 3 | `jogabonito.ps1 -Acao Status` dizia "API desligada" com a API no ar; a espera da inicialização tinha limite de 3 min com consultas de 4 s. | Lançador manda religar uma API que está funcionando; inicialização em PC lento termina em erro falso. |
| 4 | Com alto contraste e fonte em 140%, num celular (375 px), as abas Campo/Society/Futsal e o e-mail da Política de Privacidade passavam da largura da tela. | Rolagem lateral (WCAG 1.4.10). |

## Decisão
1. **Pedido idempotente.** O site e o app mandam o cabeçalho `Idempotency-Key` (UUID v4, um por tentativa
   de compra). A coluna `Pedidos.ChaveIdempotencia` tem índice único por cliente (`UX_Pedidos_Usuario_Chave`)
   e a `sp_RegistrarPedido` devolve o pedido já gravado quando a chave se repete, sem cobrar nem baixar estoque.
   Duas cópias simultâneas: a segunda bate no índice único e a API roda a procedure de novo, que devolve o pedido.
   - Site: a chave fica na sessão do navegador amarrada ao conteúdo do carrinho (fechar e abrir o checkout
     não gera outra) e o pedido tem 30 s de limite; a mensagem diz que pode confirmar de novo sem duplicar.
   - App: uma chave por tela de checkout, limite de 30 s.
   - Chave é opcional: clientes antigos continuam funcionando como antes.
2. **Foco no checkout.** Cada etapa leva o foco para o lugar certo (CEP, forma de pagamento escolhida, título
   "Pedido confirmado!"); depois de erro no envio, o foco volta para o botão de confirmar.
3. **Lançador tolerante a PC lento.** `/health/ready` com 10 s; sem resposta, testa `/health/live`: respondendo,
   o estado é **lenta** ("API ligada, mas respondendo devagar") e não "desligada". Espera da inicialização: 6 min.
4. **Reflow.** As abas de piso quebram linha no celular e textos legais quebram e-mails e links longos.

## Consequências
- O "comprou duas vezes" deixa de depender da velocidade do PC ou da rede.
- O banco ganha uma coluna e um índice (migração automática no `schema.sql`, sem perder dados).
- O PC de apresentação deve estar com poucos programas abertos: mesmo funcionando, tudo fica lento.

## Testes
- `validar_loja.py` (API real + SQL Server no pipeline): mesma chave duas vezes → mesmo `pedidoId` e estoque
  baixado uma vez só; chave nova → pedido novo.
- Flutter: `test/pedido_chave_test.dart` (UUID v4 válido e único por tentativa).
- Manual (este PC): checkout inteiro só pelo teclado, com alto contraste e fonte 120%; no SQL Server real, dois envios
  simultâneos e um terceiro com a mesma chave geraram um pedido só e baixaram uma peça.
- Reflow: as 11 páginas em 1280 px e 375 px com alto contraste e fonte 140%, sem rolagem lateral.
