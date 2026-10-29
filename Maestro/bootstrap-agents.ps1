# ==============================================================================
# bootstrap-agents.ps1
# Sistema Multi-Agent para Gemini CLI — Bootstrap v2
# ==============================================================================

$ErrorActionPreference = "Stop"

# ==============================================================================
# MENU INTERATIVO
# ==============================================================================

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║         GEMINI CLI — SISTEMA MULTI-AGENT v2          ║" -ForegroundColor Cyan
    Write-Host "  ║              Bootstrap & Gestão de Projeto            ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Menu {
    Show-Header
    Write-Host "  Escolha uma opção:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1]  Instalar estrutura de agentes no projeto atual"
    Write-Host "  [2]  Criar novo PRD"
    Write-Host "  [3]  Ver PRDs existentes"
    Write-Host "  [4]  Registrar feedback de melhoria contínua"
    Write-Host "  [5]  Ver histórico de melhoria contínua de um agente"
    Write-Host "  [6]  Ver estrutura de arquivos do projeto"
    Write-Host "  [Q]  Sair"
    Write-Host ""
    $choice = Read-Host "  Opção"
    return $choice.Trim().ToUpper()
}

# ==============================================================================
# HELPER — ESCREVER ARQUIVO UTF-8 SEM BOM
# ==============================================================================

function Write-TextFile {
    param(
        [string]$RelativePath,
        [string]$Content
    )
    $fullPath = Join-Path (Get-Location).Path $RelativePath
    $parent = Split-Path $fullPath -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($fullPath, $Content, $utf8)
    Write-Host "    + $RelativePath" -ForegroundColor Green
}

# ==============================================================================
# HELPER — PRÓXIMO NÚMERO DE PRD
# ==============================================================================

function Get-NextPrdNumber {
    $prdBase = Join-Path (Get-Location).Path "docs\prd"
    if (-not (Test-Path $prdBase)) { return "001" }
    $existing = Get-ChildItem -Path $prdBase -Directory -Filter "prd-*" |
        ForEach-Object { ($_.Name -replace "prd-", "") -as [int] } |
        Where-Object { $_ -ne $null } |
        Sort-Object
    if (-not $existing) { return "001" }
    $next = ($existing | Measure-Object -Maximum).Maximum + 1
    return ([string]$next).PadLeft(3, "0")
}

# ==============================================================================
# OPÇÃO 1 — INSTALAR ESTRUTURA COMPLETA
# ==============================================================================

function Install-Agents {
    Show-Header
    Write-Host "  Instalando estrutura multi-agent em:" -ForegroundColor Yellow
    Write-Host "  $(Get-Location)" -ForegroundColor White
    Write-Host ""

    $confirm = Read-Host "  Confirmar instalação? (s/n)"
    if ($confirm -ne "s") {
        Write-Host "  Cancelado." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "  Criando pastas..." -ForegroundColor Cyan

    $dirs = @(
        ".gemini",
        ".gemini\agents",
        ".gemini\melhoria-continua",
        "docs",
        "docs\prd",
        "docs\arquitetura",
        "docs\design-system",
        "docs\deploys"
    )
    foreach ($dir in $dirs) {
        New-Item -ItemType Directory -Force -Path (Join-Path (Get-Location).Path $dir) | Out-Null
    }

    Write-Host ""
    Write-Host "  Coletando informações do projeto..." -ForegroundColor Cyan
    Write-Host ""
    $projNome      = Read-Host "  Nome do projeto"
    $projDescricao = Read-Host "  Descrição curta (1-2 linhas)"
    $projObjetivo  = Read-Host "  Objetivo de negócio principal"
    $projFrontend  = Read-Host "  Stack Frontend (ex: Next.js, TypeScript)"
    $projBackend   = Read-Host "  Stack Backend (ex: Node.js, Prisma)"
    $projBanco     = Read-Host "  Banco de dados (ex: PostgreSQL)"
    $projInfra     = Read-Host "  Infra/Deploy (ex: Vercel, Supabase)"
    $projTestes    = Read-Host "  Stack de testes (ex: Vitest, Playwright)"
    $dataHoje      = (Get-Date).ToString("yyyy-MM-dd")

    Write-Host ""
    Write-Host "  Criando arquivos raiz..." -ForegroundColor Cyan

# ---- GEMINI.md ----
$geminiMd = @"
# $projNome — Instruções Globais do Projeto

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
| @qa       | Engenheiro de QA         | Via MAESTRO — fase VALIDAÇÃO       |
| @devops   | DevOps                   | Via MAESTRO — VERSÃO e DEPLOY      |

## Fluxo Obrigatório
Operador → @maestro
  1. CONTEXTO    → leitura de docs/contexto-projeto.md
  2. DESCOBERTA  → @ba cria PRD inicial
  3. EXPERIÊNCIA → @ux-ui cria wireframes e design system
  4. PRD UPDATE  → @maestro atualiza PRD e quebra em entregas
  5. ARQUITETURA → @architect cria plano de implementação
  6. DEV         → @dev implementa com TDD
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
- Frontend  : $projFrontend
- Backend   : $projBackend
- Banco     : $projBanco
- Infra     : $projInfra
- Testes    : $projTestes
"@

# ---- settings.json ----
$settingsJson = @'
{
  "tools": {
    "sandbox": "docker"
  },
  "agents": {
    "overrides": {
      "maestro":   { "model": "gemini-2.5-pro", "max_turns": 50 },
      "dev":       { "max_turns": 60, "timeout_mins": 40 },
      "qa":        { "max_turns": 40, "timeout_mins": 25 },
      "devops":    { "max_turns": 40, "timeout_mins": 30 }
    }
  }
}
'@

# ---- contexto-projeto.md ----
$contextoProjeto = @"
# Contexto do Projeto — $projNome
> ÍNDICE CENTRAL. Máximo 300 linhas.
> Todo agente lê ao iniciar. Todo agente atualiza ao criar arquivos.

## Projeto
$projDescricao

## Objetivo de Negócio
$projObjetivo

## Stack
- Frontend  : $projFrontend
- Backend   : $projBackend
- Banco     : $projBanco
- Infra     : $projInfra
- Testes    : $projTestes

## Estrutura de Pastas
| Pasta                       | Propósito                                  |
|-----------------------------|--------------------------------------------|
| .gemini/agents/             | Definição dos agentes                      |
| .gemini/melhoria-continua/  | Aprendizados incrementais por agente       |
| docs/contexto-projeto.md    | Este índice central                        |
| docs/prd/                   | PRDs por demanda                           |
| docs/arquitetura/           | Documentação arquitetural                  |
| docs/design-system/         | Design system                              |
| docs/deploys/               | Histórico de deploys                       |

## PRDs
| ID  | Nome | Status   | Fase Atual |
|-----|------|----------|------------|
| —   | —    | —        | —          |

## Arquivos Registrados
| Arquivo                                    | Responsável | Descrição                |
|--------------------------------------------|-------------|--------------------------|
| GEMINI.md                                  | Sistema     | Instruções globais       |
| README-AGENTS.md                           | Sistema     | Guia de uso              |
| .gemini/settings.json                      | Sistema     | Config do Gemini CLI     |
| .gemini/agents/maestro.md                  | Sistema     | Orquestrador             |
| .gemini/agents/ba.md                       | Sistema     | Analista de negócios     |
| .gemini/agents/ux-ui.md                    | Sistema     | Designer UX/UI           |
| .gemini/agents/architect.md                | Sistema     | Arquiteto                |
| .gemini/agents/dev.md                      | Sistema     | Desenvolvedor            |
| .gemini/agents/qa.md                       | Sistema     | QA                       |
| .gemini/agents/devops.md                   | Sistema     | DevOps                   |
| docs/contexto-projeto.md                   | Sistema     | Índice central           |
| docs/arquitetura/arquitetura-atual.md      | Sistema     | Arquitetura              |
| docs/design-system/design-system.md        | Sistema     | Design system            |

## Última Atualização
- Data    : $dataHoje
- Por     : bootstrap v2
- Motivo  : inicialização do projeto
"@

# ---- README-AGENTS.md ----
$readmeAgents = @"
# $projNome — Guia Rápido de Agentes

## Iniciar
```powershell
cd seu-projeto
gemini
```

## Uso
Sempre fale com o MAESTRO primeiro:

@maestro quero implementar login com Google
@maestro quero criar onboarding para aumentar conversão
@maestro feedback para o dev: ignorou TDD no módulo de pagamentos
@maestro em que fase estamos no PRD-001?

## Fluxo
1. CONTEXTO → 2. DESCOBERTA → 3. EXPERIÊNCIA → 4. PRD UPDATE
5. ARQUITETURA → 6. DESENVOLVIMENTO → 7. QA → 8. VERSÃO → 9. DEPLOY

## Criar novo PRD
Execute: .\bootstrap-agents.ps1 → opção 2

## Registrar feedback
Execute: .\bootstrap-agents.ps1 → opção 4
Ou diga ao MAESTRO: feedback para @dev: ...
"@

# ---- arquitetura ----
$arquiteturaAtual = @"
# Arquitetura Atual — $projNome

## Status
Aguardando primeira fase arquitetural.

## Stack
- Frontend  : $projFrontend
- Backend   : $projBackend
- Banco     : $projBanco
- Infra     : $projInfra

## Seções a preencher pelo ARCHITECT
- Visão geral
- Componentes
- Fluxos principais
- Dependências externas
- Modelo de dados
- Decisões arquiteturais
- Riscos técnicos
- Dívidas técnicas conhecidas
"@

# ---- design system ----
$designSystem = @"
# Design System — $projNome

## Status
Aguardando fase de EXPERIÊNCIA.

## Seções a preencher pelo UX-UI
- Princípios de UX
- Tipografia
- Cores
- Grid e spacing
- Componentes
- Estados (vazio, carregando, erro, sucesso)
- Interações e animações
- Acessibilidade
- Responsividade
"@

# ---- MAESTRO ----
$maestro = @'
---
name: maestro
description: >
  ORQUESTRADOR PRINCIPAL. Sempre acionado primeiro. Recebe qualquer pedido
  do Operador, interpreta, identifica a fase, delega para o agente correto
  e garante que nenhuma etapa seja pulada. Use para qualquer instrução inicial.
tools:
  - read_file
  - write_file
  - list_directory
  - run_shell_command
model: gemini-2.5-pro
max_turns: 50
timeout_mins: 30
---

# Identidade
Você é o MAESTRO — gerente e orquestrador do time de desenvolvimento.
Você NÃO implementa código diretamente.
Você pensa, planeja, delega, acompanha e garante o processo.
Fala em português brasileiro.

# Missão Principal
1. Interpretar o pedido do Operador.
2. Ler `docs/contexto-projeto.md`.
3. Identificar a fase atual do processo.
4. Carregar `.gemini/melhoria-continua/<agente>.md` relevante.
5. Delegar ao agente correto com briefing claro.
6. Solicitar validação do Operador ao fim de cada etapa.
7. Registrar feedbacks na melhoria contínua.
8. Atualizar `docs/contexto-projeto.md` quando arquivos forem criados.

# Processo Obrigatório (nunca pule sem validação)
1. CONTEXTO    → ler índice e contexto do projeto
2. DESCOBERTA  → @ba levanta viabilidade e cria PRD
3. EXPERIÊNCIA → @ux-ui define fluxo, wireframe e design system
4. PRD UPDATE  → revisar PRD com base na experiência definida
5. ARQUITETURA → @architect define solução técnica e plano
6. DEV         → @dev implementa com TDD
7. QA          → @qa valida testes e cobertura
8. VERSÃO      → @devops commita
9. DEPLOY      → @devops sobe para ambiente

# Regra Fundamental
Se o Operador pedir para implementar algo, você NÃO começa pelo código.
Antes:
- refina em negócio
- cria PRD
- define experiência
- cria plano técnico
- só então executa

# Gestão de Feedback
Ao receber feedback do Operador sobre qualquer agente:
1. Identifique o agente ou fase.
2. Classifique o tipo: BUG | PROCESSO | COMUNICAÇÃO | QUALIDADE | UX | NEGÓCIO | ARQUITETURA
3. Grave em `.gemini/melhoria-continua/<agente>.md` seguindo o template.
4. Confirme ao Operador que foi registrado.
5. Na próxima vez que esse agente for acionado, inclua o arquivo de MC no contexto.

# Delegação
- DESCOBERTA  → @ba
- EXPERIÊNCIA → @ux-ui
- ARQUITETURA → @architect
- DEV         → @dev
- VALIDAÇÃO   → @qa
- VERSÃO/DEPLOY → @devops

# Formato de Resposta Obrigatório ao Encerrar Etapa

✅ FASE CONCLUÍDA: [nome]

📋 RESUMO
- [bullet 1]
- [bullet 2]
- [bullet 3]

📁 EVIDÊNCIAS
- [caminho/arquivo-1]
- [caminho/arquivo-2]

⚠️ PENDÊNCIAS / RISCOS
- [item ou "nenhum"]

⏭️ PRÓXIMA FASE: [nome]

Deseja prosseguir?
  → sim          (avança)
  → ajustar: ... (ajuste antes de avançar)
  → feedback: ... (registra melhoria contínua)
'@

# ---- BA ----
$ba = @'
---
name: ba
description: >
  Analista de Negócios. Acionado pelo MAESTRO na fase DESCOBERTA.
  Faz perguntas de viabilidade, pesquisa benchmarks e cria PRD inicial.
  Só trabalha em soluções com potencial real de retorno.
tools:
  - read_file
  - write_file
  - list_directory
  - web_search
  - web_fetch
model: gemini-2.5-pro
max_turns: 40
timeout_mins: 25
---

# Identidade
Você é o BA — analista de negócios sênior com mentalidade de produto.
Você não aceita soluções sem valor claro, sem público definido ou sem monetização viável.
Fala em pt-BR. Tom consultivo e direto.

# Inicialização Obrigatória
Sempre leia antes de qualquer ação:
- `docs/contexto-projeto.md`
- `.gemini/melhoria-continua/ba.md`

# Processo
1. Entender o briefing do MAESTRO.
2. Pesquisar mercado, concorrentes e benchmarks relevantes via web.
3. Formular e apresentar perguntas de viabilidade ao Operador.
4. Garantir que TUDO foi respondido antes de criar o PRD.
5. Criar o PRD inicial no diretório correto.

# Perguntas Obrigatórias
- Qual problema real estamos resolvendo?
- Quem é o cliente e quem é o usuário final?
- Qual a dor atual e o custo dela?
- Como a solução gera receita ou reduz custo?
- Qual é o tamanho do mercado?
- Quais concorrentes ou alternativas existem?
- Qual o diferencial competitivo?
- Como mediremos sucesso?
- Quais são os principais riscos?
- Qual o escopo mínimo viável?
- O que NÃO entra agora?

# Regras
- Pressione por respostas claras.
- Se a ideia tiver risco alto, sinalize com franqueza.
- Sempre traga benchmarks com fontes.

# Saída Obrigatória
Criar `docs/prd/prd-NNN/prd-inicial.md` com:
- Contexto e problema
- Público-alvo e personas
- Benchmarks (com fontes)
- Proposta de valor
- Monetização e retorno esperado
- Escopo inicial
- Fora de escopo
- KPIs e critérios de sucesso
- Riscos
- Fases sugeridas de entrega

Informar o MAESTRO ao concluir.
'@

# ---- UX-UI ----
$uxui = @'
---
name: ux-ui
description: >
  Designer de UX/UI. Acionado pelo MAESTRO na fase EXPERIÊNCIA.
  Pensa na perspectiva do cliente, define fluxos ponta a ponta,
  cria wireframes em HTML/CSS/JS puro e mantém o design system.
tools:
  - read_file
  - write_file
  - list_directory
  - web_search
  - web_fetch
model: gemini-2.5-pro
max_turns: 40
timeout_mins: 25
---

# Identidade
Você é o UX-UI — designer sênior focado em experiência, conversão e clareza.
Você pensa do ponto de vista do usuário ANTES de pensar em tecnologia.
Fala em pt-BR. Tom criativo e pragmático.

# Inicialização Obrigatória
Sempre leia antes de qualquer ação:
- `docs/contexto-projeto.md`
- PRD atual
- `.gemini/melhoria-continua/ux-ui.md`
- `docs/design-system/design-system.md` (se existir)

# Processo
1. Ler PRD atual e benchmarks levantados pelo BA.
2. Pesquisar referências visuais e de UX relevantes.
3. Fazer perguntas ao Operador (mínimo 5) sobre:
   - perfil do usuário
   - fluxos prioritários
   - preferências visuais
   - restrições técnicas ou de marca
   - contexto de uso
4. Desenhar o fluxo ponta a ponto em texto/ASCII.
5. Criar wireframes em HTML + CSS + JS puro (sem frameworks).
6. Validar com o Operador antes de qualquer design final.
7. Criar ou atualizar o design system.

# Regras
- Wireframe é funcional e simples. Sem cores finais ou assets reais.
- Sempre cobrir os estados: vazio, carregando, erro, sucesso.
- Pensar em acessibilidade e responsividade desde o início.
- Não pular validação do Operador.

# Saídas Obrigatórias
- `docs/prd/prd-NNN/fluxo-ux.md`
- `docs/prd/prd-NNN/wireframes/*.html` (um por tela/fluxo)
- `docs/design-system/design-system.md` (criado ou atualizado)

Informar o MAESTRO ao concluir.
'@

# ---- ARCHITECT ----
$architect = @'
---
name: architect
description: >
  Arquiteto de software. Acionado pelo MAESTRO na fase ARQUITETURA.
  Define solução técnica evitando overengineering, respeitando a stack
  e a complexidade adequada ao problema.
tools:
  - read_file
  - write_file
  - list_directory
  - web_search
model: gemini-2.5-pro
max_turns: 40
timeout_mins: 25
---

# Identidade
Você é o ARCHITECT — arquiteto pragmático.
Soluções simples devem ser simples.
Soluções complexas devem ter organização proporcional à complexidade.
Fala em pt-BR.

# Inicialização Obrigatória
Sempre leia antes de qualquer ação:
- `docs/contexto-projeto.md`
- PRD atualizado
- Wireframes aprovados
- `docs/arquitetura/arquitetura-atual.md`
- `.gemini/melhoria-continua/architect.md`

# Processo
1. Analisar PRD e experiência aprovada.
2. Avaliar arquitetura atual. Identificar reutilização vs. novo.
3. Definir solução técnica para a fase.
4. Aplicar checklist anti-overengineering.
5. Criar plano de implementação.

# Checklist Anti-Overengineering
Antes de qualquer decisão complexa:
- Isso resolve o problema atual ou um hipotético futuro?
- Existe solução mais simples?
- O time consegue sustentar essa decisão?
- O custo de manutenção vale o benefício?

# Saídas Obrigatórias
- `docs/arquitetura/arquitetura-atual.md` atualizado
- `docs/prd/prd-NNN/plano-implementacao-fase-N.md` com:
  - objetivo técnico
  - arquivos a criar/alterar
  - ordem de implementação
  - contratos de API
  - modelo de dados
  - dependências
  - riscos técnicos
  - critérios de pronto
  - diagrama ASCII quando útil

Informar o MAESTRO ao concluir.
'@

# ---- DEV ----
$dev = @'
---
name: dev
description: >
  Desenvolvedor sênior. Acionado pelo MAESTRO na fase DEV.
  Implementa seguindo TDD obrigatoriamente, boas práticas e o plano do ARCHITECT.
tools:
  - read_file
  - write_file
  - list_directory
  - run_shell_command
model: gemini-2.5-pro
max_turns: 60
timeout_mins: 40
---

# Identidade
Você é o DEV — desenvolvedor sênior com mentalidade de craftsman.
Você escreve código limpo, testável e manutenível.
TDD não é opcional. Jamais.
Fala em pt-BR. Código e variáveis em inglês.

# Inicialização Obrigatória
Sempre leia antes de qualquer ação:
- `docs/contexto-projeto.md`
- Plano de implementação da fase atual
- `docs/design-system/design-system.md`
- `.gemini/melhoria-continua/dev.md` ← LEIA COM ATENÇÃO — contém erros anteriores

# Processo TDD (sem exceções)
Para cada unidade:
1. RED → escreva o teste que falha
2. GREEN → implemente o mínimo para passar
3. REFACTOR → limpe sem quebrar

# Regras
- Nunca escreva código sem teste primeiro.
- Nunca desvie do plano sem avisar o MAESTRO.
- Tratar erros em todas as operações async.
- Sem console.log de debug no código final.
- Atualizar `docs/contexto-projeto.md` ao criar arquivos.
- Não instalar dependências fora do plano.

# Saída Esperada
Relatório ao MAESTRO com:
- arquivos criados/modificados
- testes criados
- cobertura estimada
- desvios do plano (se houver) com justificativa

Informar o MAESTRO ao concluir.
'@

# ---- QA ----
$qa = @'
---
name: qa
description: >
  Engenheiro de QA. Acionado pelo MAESTRO na fase VALIDAÇÃO.
  Sugere cenários antes da implementação, valida testes unitários,
  funcionais, cobertura e semântica. Não aprova sem evidência.
tools:
  - read_file
  - write_file
  - list_directory
  - run_shell_command
model: gemini-2.5-pro
max_turns: 40
timeout_mins: 25
---

# Identidade
Você é o QA — engenheiro de qualidade rigoroso.
Você não aprova sem evidência real.
Você protege o produto de regressões e falhas de cobertura.
Fala em pt-BR.

# Inicialização Obrigatória
Sempre leia antes de qualquer ação:
- `docs/contexto-projeto.md`
- PRD atual (critérios de aceite)
- Plano de implementação da fase atual
- `.gemini/melhoria-continua/qa.md`

# Quando acionado ANTES do DEV
Sugira cenários de teste para o DEV implementar:
- happy path
- edge cases
- erros esperados
- segurança e inputs maliciosos
- performance (se relevante)

# Quando acionado APÓS o DEV
1. Executar testes unitários e reportar output completo.
2. Executar testes e2e (se existirem).
3. Verificar cobertura — mínimo 80% nas áreas críticas.
4. Validar semântica e acessibilidade básica (se aplicável).
5. Se falhas encontradas: gravar em `.gemini/melhoria-continua/dev.md`.

# Saída Obrigatória
Criar `docs/prd/prd-NNN/relatorio-qa-fase-N.md` com:
- Status: APROVADO ou REPROVADO
- Testes executados
- Cobertura
- Problemas encontrados (com severidade)
- Cenários não cobertos
- Recomendação

Se REPROVADO → informar MAESTRO para acionar DEV.
Se APROVADO → informar MAESTRO para acionar DEVOPS.
'@

# ---- DEVOPS ----
$devops = @'
---
name: devops
description: >
  Especialista em DevOps. Acionado pelo MAESTRO após aprovação do QA.
  Responsável por commits em pt-BR, versionamento SemVer, variáveis
  de ambiente, migrações e deploy em QA/HML/PROD.
tools:
  - read_file
  - write_file
  - list_directory
  - run_shell_command
model: gemini-2.5-pro
max_turns: 40
timeout_mins: 30
---

# Identidade
Você é o DEVOPS — especialista em entrega segura e rastreável.
Você garante que o código correto chega no ambiente correto, com segurança.
Fala em pt-BR.

# Inicialização Obrigatória
Sempre leia antes de qualquer ação:
- `docs/contexto-projeto.md`
- Relatório de QA da fase
- `.gemini/melhoria-continua/devops.md`

# VERSIONAMENTO
1. Listar arquivos alterados na fase.
2. Agrupar em commits lógicos.
3. Criar commits com mensagens em pt-BR:
   - feat(escopo): descrição
   - fix(escopo): descrição
   - chore(escopo): descrição
   - docs(escopo): descrição
4. Criar tag SemVer se for release.

# DEPLOY
1. Confirmar ambiente alvo com MAESTRO: QA / HML / PROD.
2. Validar variáveis de ambiente — alertar se faltar algo.
3. Executar pipeline do ambiente.
4. Rodar migrações se necessário (backup antes em PROD).
5. Validar saúde pós-deploy.
6. Documentar em `docs/deploys/deploy-YYYY-MM-DD-<ambiente>.md`.

# Segurança
- NUNCA commitar secrets ou API keys.
- SEMPRE confirmar com MAESTRO antes de PROD.
- SEMPRE fazer backup antes de migração em PROD.
- Variáveis sensíveis ficam apenas em .env ou no painel do serviço.

# Saídas
- Lista de commits (hash + mensagem)
- Documento de deploy criado
- Confirmação: URL, versão e status de saúde
'@

# ---- MELHORIA CONTÍNUA ----
$mcTemplate = @'
# Melhoria Contínua
> Arquivo incremental. Nunca apagar entradas.
> Lido automaticamente pelo MAESTRO antes de acionar o agente correspondente.

## Formato de Registro
## [YYYY-MM-DD] — Tipo: [BUG | PROCESSO | COMUNICAÇÃO | QUALIDADE | UX | NEGÓCIO | ARQUITETURA | OUTRO]
**Contexto:** [fase / PRD]
**Problema:** [descrição objetiva]
**Impacto:** [efeito causado]
**Ação corretiva:** [o que deve mudar]
**Status:** [ABERTO | APLICADO]

## Histórico
'@

# ---- WIREFRAME INICIAL ----
$wireframe = @'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Wireframe Inicial</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: Arial, sans-serif; background: #f0f0f0; color: #222; padding: 24px; }
    h1 { font-size: 18px; margin-bottom: 8px; }
    h2 { font-size: 14px; margin-bottom: 8px; color: #444; }
    p  { font-size: 13px; color: #666; line-height: 1.5; }
    .page { max-width: 900px; margin: 0 auto; }
    .box { background: #fff; border: 1px dashed #aaa; padding: 16px; margin-bottom: 16px; }
    .row { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 16px; }
    .col { flex: 1 1 240px; background: #fff; border: 1px dashed #aaa; padding: 16px; }
    .btn { display: inline-block; padding: 8px 16px; border: 1px solid #333; background: #fff; cursor: pointer; font-size: 13px; margin-top: 8px; }
    .btn:hover { background: #eee; }
    .badge { display: inline-block; padding: 2px 8px; border: 1px solid #333; font-size: 11px; }
    nav { display: flex; gap: 12px; padding: 12px; background: #fff; border: 1px dashed #aaa; margin-bottom: 16px; }
    nav a { font-size: 13px; color: #333; text-decoration: none; }
    nav a:hover { text-decoration: underline; }
    footer { text-align: center; font-size: 11px; color: #999; padding-top: 16px; }
  </style>
</head>
<body>
<div class="page">

  <div class="box">
    <h1>Wireframe Inicial — Validação de Fluxo</h1>
    <p>Arquivo de estrutura para revisão com o Operador. Sem design final.</p>
  </div>

  <nav>
    <a href="#">Início</a>
    <a href="#">Seção A</a>
    <a href="#">Seção B</a>
    <a href="#" style="margin-left:auto;">Ação</a>
  </nav>

  <div class="row">
    <div class="col">
      <h2>Entrada</h2>
      <p>Área de entrada do usuário ou ponto de partida do fluxo.</p>
      <button class="btn">Ação principal</button>
    </div>
    <div class="col">
      <h2>Conteúdo principal</h2>
      <p>Área central da experiência. Conteúdo principal da tela.</p>
    </div>
    <div class="col">
      <h2>Lateral / Resumo</h2>
      <p>Informações complementares ou contexto de apoio.</p>
    </div>
  </div>

  <div class="box">
    <h2>Estados da tela</h2>
    <p>
      <span class="badge">Vazio</span>&nbsp;
      <span class="badge">Carregando</span>&nbsp;
      <span class="badge">Erro</span>&nbsp;
      <span class="badge">Sucesso</span>
    </p>
  </div>

  <div class="box">
    <h2>Ações disponíveis</h2>
    <button class="btn">Confirmar</button>&nbsp;
    <button class="btn">Cancelar</button>&nbsp;
    <button class="btn">Ver mais</button>
  </div>

  <footer>Wireframe — para validação de fluxo — não representa design final</footer>
</div>
</body>
</html>
'@

    Write-Host ""
    Write-Host "  Criando arquivos..." -ForegroundColor Cyan

    Write-TextFile "GEMINI.md"                                          $geminiMd
    Write-TextFile "README-AGENTS.md"                                   $readmeAgents
    Write-TextFile ".gemini\settings.json"                              $settingsJson
    Write-TextFile "docs\contexto-projeto.md"                           $contextoProjeto
    Write-TextFile "docs\arquitetura\arquitetura-atual.md"              $arquiteturaAtual
    Write-TextFile "docs\design-system\design-system.md"                $designSystem

    Write-TextFile ".gemini\agents\maestro.md"                          $maestro
    Write-TextFile ".gemini\agents\ba.md"                               $ba
    Write-TextFile ".gemini\agents\ux-ui.md"                            $uxui
    Write-TextFile ".gemini\agents\architect.md"                        $architect
    Write-TextFile ".gemini\agents\dev.md"                              $dev
    Write-TextFile ".gemini\agents\qa.md"                               $qa
    Write-TextFile ".gemini\agents\devops.md"                           $devops

    Write-TextFile ".gemini\melhoria-continua\maestro.md"               $mcTemplate
    Write-TextFile ".gemini\melhoria-continua\ba.md"                    $mcTemplate
    Write-TextFile ".gemini\melhoria-continua\ux-ui.md"                 $mcTemplate
    Write-TextFile ".gemini\melhoria-continua\architect.md"             $mcTemplate
    Write-TextFile ".gemini\melhoria-continua\dev.md"                   $mcTemplate
    Write-TextFile ".gemini\melhoria-continua\qa.md"                    $mcTemplate
    Write-TextFile ".gemini\melhoria-continua\devops.md"                $mcTemplate

    New-Item -ItemType Directory -Force -Path (Join-Path (Get-Location).Path "docs\prd\prd-001\wireframes") | Out-Null
    Write-TextFile "docs\prd\prd-001\wireframes\wireframe-inicial.html" $wireframe

    Write-Host ""
    Write-Host "  Instalação concluída." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Próximos passos:" -ForegroundColor Yellow
    Write-Host "  1. Abra o Docker Desktop"
    Write-Host "  2. Execute: gemini"
    Write-Host "  3. Inicie com: @maestro quero implementar ..."
    Write-Host ""
    Read-Host "  Pressione ENTER para voltar ao menu"
}

# ==============================================================================
# OPÇÃO 2 — CRIAR NOVO PRD
# ==============================================================================

function New-Prd {
    Show-Header
    Write-Host "  Criar novo PRD" -ForegroundColor Yellow
    Write-Host ""

    $prdNum  = Get-NextPrdNumber
    $prdId   = "prd-$prdNum"
    $prdNome = Read-Host "  Nome/título da demanda"
    $prdDesc = Read-Host "  Descrição curta do pedido"
    $dataHoje = (Get-Date).ToString("yyyy-MM-dd")

    $prdDir = "docs\prd\$prdId"
    New-Item -ItemType Directory -Force -Path (Join-Path (Get-Location).Path "$prdDir\wireframes") | Out-Null

    $prdConteudo = @"
# PRD-$prdNum — $prdNome
> Criado em $dataHoje

## Contexto
$prdDesc

## Problema
[a preencher pelo BA]

## Objetivo de Negócio
[a preencher pelo BA]

## Público-Alvo
[a preencher pelo BA]

## Personas
[a preencher pelo BA]

## Benchmarks
[a preencher pelo BA com fontes]

## Proposta de Valor
[a preencher pelo BA]

## Monetização / Retorno Esperado
[a preencher pelo BA]

## Escopo Inicial
[a preencher pelo BA]

## Fora de Escopo
[a preencher pelo BA]

## KPIs
[a preencher pelo BA]

## Riscos
[a preencher pelo BA]

## Fases de Entrega
- Fase 1:
- Fase 2:
- Fase 3:

## Critérios de Sucesso
[a preencher pelo BA]

## Status
| Fase | Status | Data | Responsável |
|------|--------|------|-------------|
| DESCOBERTA   | PENDENTE | — | @ba |
| EXPERIÊNCIA  | PENDENTE | — | @ux-ui |
| ARQUITETURA  | PENDENTE | — | @architect |
| DEV          | PENDENTE | — | @dev |
| QA           | PENDENTE | — | @qa |
| DEPLOY       | PENDENTE | — | @devops |
"@

    Write-TextFile "$prdDir\prd-inicial.md"  $prdConteudo

$fluxoUx = @"
# Fluxo UX — PRD-$prdNum — $prdNome

## Objetivo
[a preencher pelo UX-UI]

## Jornada Ponta a Ponta
[a preencher pelo UX-UI]

## Estados
- Vazio:
- Carregando:
- Sucesso:
- Erro:

## Dúvidas Abertas
[a preencher]
"@

    Write-TextFile "$prdDir\fluxo-ux.md"  $fluxoUx

$planoImpl = @"
# Plano de Implementação — PRD-$prdNum Fase 1

## Objetivo Técnico
[a preencher pelo ARCHITECT]

## Arquivos a Criar/Alterar
| Arquivo | Ação | Descrição |
|---------|------|-----------|

## Ordem de Implementação
1.
2.
3.

## Contratos de API
[a preencher]

## Modelo de Dados
[a preencher]

## Dependências
[a preencher]

## Riscos Técnicos
[a preencher]

## Critérios de Pronto
[a preencher]
"@

    Write-TextFile "$prdDir\plano-implementacao-fase-1.md"  $planoImpl

$relatorioQa = @"
# Relatório QA — PRD-$prdNum Fase 1

## Status Geral
PENDENTE

## Testes Executados
[a preencher]

## Cobertura
[a preencher]

## Problemas Encontrados
[a preencher]

## Cenários Não Cobertos
[a preencher]

## Recomendação
[a preencher]
"@

    Write-TextFile "$prdDir\relatorio-qa-fase-1.md"  $relatorioQa

    Write-Host ""
    Write-Host "  PRD-$prdNum criado em docs\prd\$prdId" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Para iniciar, rode o Gemini CLI e diga ao MAESTRO:" -ForegroundColor Yellow
    Write-Host "  @maestro iniciar descoberta do PRD-$prdNum" -ForegroundColor White
    Write-Host ""
    Read-Host "  Pressione ENTER para voltar ao menu"
}

# ==============================================================================
# OPÇÃO 3 — VER PRDS EXISTENTES
# ==============================================================================

function Show-Prds {
    Show-Header
    Write-Host "  PRDs Existentes" -ForegroundColor Yellow
    Write-Host ""

    $prdBase = Join-Path (Get-Location).Path "docs\prd"
    if (-not (Test-Path $prdBase)) {
        Write-Host "  Nenhum PRD encontrado. Execute a opção 2 para criar." -ForegroundColor Red
    } else {
        $prds = Get-ChildItem -Path $prdBase -Directory -Filter "prd-*"
        if (-not $prds) {
            Write-Host "  Nenhum PRD encontrado ainda." -ForegroundColor Red
        } else {
            foreach ($p in $prds) {
                $prdFile = Join-Path $p.FullName "prd-inicial.md"
                $titulo = if (Test-Path $prdFile) {
                    (Get-Content $prdFile | Select-Object -First 1) -replace "# ",""
                } else { "(sem título)" }
                Write-Host "  $($p.Name): $titulo" -ForegroundColor White
            }
        }
    }

    Write-Host ""
    Read-Host "  Pressione ENTER para voltar ao menu"
}

# ==============================================================================
# OPÇÃO 4 — REGISTRAR FEEDBACK DE MELHORIA CONTÍNUA
# ==============================================================================

function Add-Feedback {
    Show-Header
    Write-Host "  Registrar Feedback de Melhoria Contínua" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Agentes disponíveis: maestro, ba, ux-ui, architect, dev, qa, devops"
    Write-Host ""

    $agente    = Read-Host "  Agente"
    $tipo      = Read-Host "  Tipo [BUG | PROCESSO | COMUNICAÇÃO | QUALIDADE | UX | NEGÓCIO | ARQUITETURA | OUTRO]"
    $contexto  = Read-Host "  Contexto (fase / PRD)"
    $problema  = Read-Host "  Problema (descrição objetiva)"
    $impacto   = Read-Host "  Impacto"
    $corretiva = Read-Host "  Ação corretiva"
    $dataHoje  = (Get-Date).ToString("yyyy-MM-dd")

    $mcFile = ".gemini\melhoria-continua\$agente.md"
    $fullPath = Join-Path (Get-Location).Path $mcFile

    if (-not (Test-Path $fullPath)) {
        Write-Host "  Agente não encontrado. Verifique o nome digitado." -ForegroundColor Red
        Read-Host "  Pressione ENTER"
        return
    }

    $novaEntrada = @"


## [$dataHoje] — Tipo: $tipo
**Contexto:** $contexto
**Problema:** $problema
**Impacto:** $impacto
**Ação corretiva:** $corretiva
**Status:** ABERTO
"@

    Add-Content -Path $fullPath -Value $novaEntrada -Encoding UTF8

    Write-Host ""
    Write-Host "  Feedback registrado em $mcFile" -ForegroundColor Green
    Write-Host ""
    Read-Host "  Pressione ENTER para voltar ao menu"
}

# ==============================================================================
# OPÇÃO 5 — VER MELHORIA CONTÍNUA DE UM AGENTE
# ==============================================================================

function Show-Mc {
    Show-Header
    Write-Host "  Ver Melhoria Contínua" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Agentes: maestro, ba, ux-ui, architect, dev, qa, devops"
    Write-Host ""
    $agente = Read-Host "  Agente"
    $mcFile = Join-Path (Get-Location).Path ".gemini\melhoria-continua\$agente.md"

    if (-not (Test-Path $mcFile)) {
        Write-Host "  Arquivo não encontrado." -ForegroundColor Red
    } else {
        Write-Host ""
        Get-Content $mcFile | ForEach-Object { Write-Host "  $_" }
    }
    Write-Host ""
    Read-Host "  Pressione ENTER para voltar ao menu"
}

# ==============================================================================
# OPÇÃO 6 — VER ESTRUTURA DE ARQUIVOS
# ==============================================================================

function Show-Structure {
    Show-Header
    Write-Host "  Estrutura de Arquivos do Projeto" -ForegroundColor Yellow
    Write-Host ""

    $items = @(
        "GEMINI.md",
        "README-AGENTS.md",
        ".gemini\settings.json",
        ".gemini\agents\",
        ".gemini\melhoria-continua\",
        "docs\contexto-projeto.md",
        "docs\arquitetura\",
        "docs\design-system\",
        "docs\prd\",
        "docs\deploys\"
    )

    foreach ($item in $items) {
        $full = Join-Path (Get-Location).Path $item
        if (Test-Path $full) {
            $type = if ((Get-Item $full).PSIsContainer) { "[DIR] " } else { "[ARQ] " }
            Write-Host "  $type$item" -ForegroundColor White
        } else {
            Write-Host "  [---] $item (não criado ainda)" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Read-Host "  Pressione ENTER para voltar ao menu"
}

# ==============================================================================
# LOOP PRINCIPAL
# ==============================================================================

do {
    $opt = Show-Menu
    switch ($opt) {
        "1" { Install-Agents }
        "2" { New-Prd }
        "3" { Show-Prds }
        "4" { Add-Feedback }
        "5" { Show-Mc }
        "6" { Show-Structure }
        "Q" { Write-Host "" ; Write-Host "  Saindo..." -ForegroundColor DarkGray ; Write-Host "" }
        default { Write-Host "  Opção inválida." -ForegroundColor Red ; Start-Sleep 1 }
    }
} while ($opt -ne "Q")