# Contexto do Projeto — Joga Bonito (PIM IV)
> ÍNDICE CENTRAL. Máximo 300 linhas.
> Todo agente lê ao iniciar. Todo agente atualiza ao criar arquivos.

## Projeto
Joga Bonito — E-commerce & Plataforma de Futebol e Artigos Esportivos (PIM IV - UNIP 2026.2).

## Objetivo de Negócio
Plataforma omnicanal (Web + Mobile) especializada na comercialização de mantos de futebol da Temporada 2026, camisas retrô nostálgicas de clubes/seleções e artigos esportivos de alta performance, com identidade visual nas cores Verde (#0E552A) e Amarelo (#FCCA0F).

## Stack
- Frontend  : HTML5, CSS3, JavaScript Vanilla
- Backend   : .NET 8 (C#) Minimal APIs / Camadas
- Banco     : SQL Server Express (Procedures, Triggers, Views)
- Mobile    : Flutter (Dart)
- Infra     : Docker Compose
- Testes    : MSTest / xUnit

## Estrutura de Pastas
| Pasta                       | Propósito                                  |
|-----------------------------|--------------------------------------------|
| .gemini/agents/             | Definição dos agentes Maestro              |
| .gemini/melhoria-continua/  | Aprendizados incrementais por agente       |
| docs/contexto-projeto.md    | Este índice central                        |
| docs/prd/                   | PRDs por demanda                           |
| docs/arquitetura/           | Documentação arquitetural                  |
| docs/design-system/         | Design system                              |
| docs/deploys/               | Histórico de deploys                       |
| Site/                       | Código-fonte da aplicação Web e API        |

## PRDs
| ID      | Nome                             | Status    | Fase Atual   |
|---------|----------------------------------|-----------|--------------|
| PRD-001 | Rebranding & Catálogo Joga Bonito| Concluído | Entregue     |
| PRD-002 | Turbinar: catálogo 36 itens, design, segurança, banco/API | Concluído | Entregue (QA aprovado) |

## Arquivos Registrados
| Arquivo                                       | Responsável | Descrição                                 |
|-----------------------------------------------|-------------|-------------------------------------------|
| GEMINI.md                                     | Sistema     | Instruções globais                        |
| README-AGENTS.md                              | Sistema     | Guia de uso                               |
| .gemini/agents/maestro.md                     | Sistema     | Orquestrador                              |
| docs/contexto-projeto.md                      | Sistema     | Índice central                            |
| docs/prd/prd-001/prd-inicial.md               | BA / Maestro| PRD de negócio e catálogo Joga Bonito     |
| docs/design-system/design-system.md           | UX-UI       | Design System Verde e Amarelo             |
| docs/arquitetura/arquitetura-atual.md         | Architect   | Arquitetura técnica Web/API/Banco         |
| docs/prd/prd-002/prd-turbinar.md              | BA / UX / Architect | Melhorias PRD-002 e plano técnico |
| docs/qa/qa-prd-002.md                         | QA          | Relatório de testes do PRD-002            |

## Última Atualização
- Data    : 2026-10-23
- Por     : Maestro
- Motivo  : PRD-002 implementado e validado (12/12 testes E2E)