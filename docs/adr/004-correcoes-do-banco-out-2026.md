# ADR 004 — Migração do Joga Junto e opções SET nos scripts do banco

**Data:** 27/10/2026 · **Situação:** aceita e aplicada

## Contexto
A `conferencia.sql` no banco local apontou 4 pedidos (criados antes da versão 4 do esquema)
com `ValorJogaJunto = 0`: a coluna foi criada com padrão 0 e nunca recalculada. Além disso,
`schema.sql`, `seed.sql` e `demo.sql` falhavam no `sqlcmd`, que vem com
`QUOTED_IDENTIFIER OFF` (o SSMS e a API usam ON), por causa dos índices filtrados.

## Decisão
- `schema.sql` recalcula o Joga Junto dos pedidos que ficaram com 0
  (`dbo.fn_CalcularJogaJunto(Subtotal - Desconto)`). É idempotente e roda a cada
  inicialização da API, então corrige o banco local e o do Azure sozinho.
- Os três scripts começam com `SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;`.

## Consequências
- Conferência do banco local: 22 de 23 regras OK. A regra 23 (contas de demonstração
  ausentes) só deve passar em produção.
- Os scripts podem ser rodados pelo SSMS, pelo Azure Data Studio ou pelo `sqlcmd`.
