# ADR 001 — O repositório GitHub existente é a fonte do CI/CD

**Data:** 27/10/2026 · **Situação:** aceita; pasta ligada a `github.com/matheus-sigoli/Joga-Bonito` (branch `main`)

## Contexto
O projeto já tem um repositório no GitHub, mas a pasta de trabalho no PC (OneDrive) não é um
repositório git. Os workflows `.github/workflows/ci-cd.yml` (testes, container, APK) e
`site-publico.yml` (site público) só rodam a partir do GitHub.

## Decisão
Usar o repositório existente. A pasta local é ligada a ele e as correções de outubro/2026
(ver [ADR 004](004-correcoes-do-banco-out-2026.md)) vão para lá.

## Comparação feita em 27/10/2026
A pasta foi ligada sem alterar arquivos (`git init` + `git reset origin/main`, `core.autocrlf true`).
Ela estava **mais nova** que o GitHub (último commit: 24/10, "Corrige o VLibras no site publicado"):
- 41 fotos (11 de jogadores, 30 de produtos, 3 MB) nunca enviadas, e o `catalogo-local.js`
  regenerado com elas. As 358 imagens referenciadas pelo catálogo existem. Precisam ir
  juntos no mesmo commit, senão o site público aponta para fotos que não existem.
- As correções do [ADR 004](004-correcoes-do-banco-out-2026.md), dos testes de integração e do
  `Program.cs` (porta 5000 ocupada), além destes ADRs e do glossário.
- As 61 fotos de `Site/IMG/Produtos/_originais/` ficam fora de propósito (`.gitignore`).

## Consequências
- O `.gitignore` precisa manter fora: `.env`, `bin/`, `obj/`, `publico/`, `Mobile/build/`.
- O APK de produção e o site público passam a sair do GitHub Actions.
