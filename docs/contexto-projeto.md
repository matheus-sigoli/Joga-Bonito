# Contexto do Projeto — Joga Bonito (PIM IV)
> Índice central da documentação. Os agentes do método Maestro (`Maestro/`) leem este arquivo ao iniciar.

## Projeto
Joga Bonito: loja de camisas da Temporada 2026, camisas retrô e chuteiras de campo, society e futsal
(PIM IV, ADS UNIP 2026/2). Site, API, banco de dados, app mobile e nuvem, nas cores verde (#0E552A) e amarelo (#FCCA0F).

## Situação
Concluído em 13/11/2026. Números dos testes e links em `README.md` (seção "Situação final");
decisões em `docs/adr/` (ADR 005, 009 e 010).

## Stack
- Site      : HTML5, CSS3 e JavaScript puro (`Site/HTML`, `Site/CSS`, `Site/Javascript`, `Site/IMG`)
- API       : .NET 8 em camadas, JWT, BCrypt, Swagger (`Site/backend`)
- Banco     : SQL Server — tabelas, views, funções, procedures e triggers (`Site/banco`)
- App       : Flutter (`Mobile`)
- Nuvem     : Azure como código em Bicep (`infra`)
- DevOps    : Docker Compose e GitHub Actions (`docker-compose.yml`, `.github/workflows`)
- Testes    : xUnit, Playwright, flutter test e aceitação contra a API real (`Site/tests`, `Mobile/test`, `Mobile/integracao`)

## Documentação (`docs/`)
| Arquivo / pasta                         | Conteúdo                                         |
|-----------------------------------------|--------------------------------------------------|
| adr/                                    | Decisões do projeto (001 a 010) e índice          |
| qa/roteiros-manuais.md                  | Roteiros e execuções dos testes manuais           |
| qa/qa-prd-002.md                        | Relatório de testes do PRD-002                    |
| prd/prd-001/prd-inicial.md              | PRD de negócio e catálogo                         |
| prd/prd-002/prd-turbinar.md             | Melhorias do PRD-002 e plano técnico              |
| arquitetura/arquitetura-atual.md        | Arquitetura técnica Web/API/Banco                 |
| design-system/design-system.md          | Identidade visual verde e amarelo                 |
| abnt/figuras/                           | Figuras do trabalho escrito e fontes `.dot`       |
| capturas/                               | Capturas de tela do site                          |
| glossario.md                            | Termos do projeto                                 |

O trabalho escrito (.docx/.pdf) e a planilha de backlog são entregues pelo sistema da UNIP e não ficam
no repositório público (ADR 006).

## PRDs
| ID      | Nome                                                    | Status    |
|---------|---------------------------------------------------------|-----------|
| PRD-001 | Rebranding e catálogo Joga Bonito                       | Entregue  |
| PRD-002 | Turbinar: catálogo de 36 itens, design, segurança, banco/API | Entregue |

## Última atualização
- Data   : 2026-11-13
- Motivo : organização final das pastas (documentação reunida em `docs/`, scripts de apoio em `scripts/`)
