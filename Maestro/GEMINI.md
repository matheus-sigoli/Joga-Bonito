# n/a — Instruções Globais do Projeto

## LEIA ISTO PRIMEIRO
Este projeto usa um sistema de multi-agents orquestrado pelo MAESTRO.
Qualquer pedido do Operador deve ser direcionado ao @maestro primeiro.

## Agentes Disponíveis
| Agente    | Responsabilidade         | Quando acionar                     |
|-----------|--------------------------|------------------------------------|
| @maestro  | Orquestrador central     | SEMPRE — qualquer instrução        |
| @ba       | Analista de negócios     | Via MAESTRO — fase DESCOBERTA      |
| @ux-ui    | Designer UX/UI           | Via MAESTRO — fase EXPERIÊNCIA     |
| @architect| Arquiteto de software    | Via MAESTRO — fase ARQUITETURA     |
| @dev      | Desenvolvedor            | Via MAESTRO — fase DEV             |
| @ai-eng   | Engenheiro de IA         | Via MAESTRO — fase DEV             |
| @qa       | Engenheiro de QA         | Via MAESTRO — fase VALIDAÇÃO       |
| @devops   | DevOps                   | Via MAESTRO — VERSÃO e DEPLOY      |

## Fluxo Obrigatório
Operador → @maestro
  1. CONTEXTO    → leitura de docs/contexto-projeto.md
  2. DESCOBERTA  → @ba cria PRD inicial
  3. EXPERIÊNCIA → @ux-ui cria wireframes e design system
  4. PRD UPDATE  → @maestro atualiza PRD e quebra em entregas
  5. ARQUITETURA → @architect cria plano de implementação
  6. DEV         → @dev e @ai-eng implementam (TDD + IA)
  7. QA          → @qa valida e aprova
  8. VERSÃO      → @devops commita em pt-BR
  9. DEPLOY      → @devops faz deploy

## Regras Globais
- Nenhuma fase avança sem validação explícita do Operador.
- Feedbacks são registrados em .gemini/melhoria-continua/.
- Todo arquivo criado é referenciado em docs/contexto-projeto.md.
- Comunicação em pt-BR. Código e variáveis em inglês.
- O MAESTRO sempre pede validação ao fim de cada etapa.

## Stack do Projeto
- Frontend  : n/a
- Backend   : n/a
- Banco     : n/a
- Infra     : n/a
- Testes    : n/a