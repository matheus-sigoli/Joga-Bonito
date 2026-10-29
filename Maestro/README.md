# 🎼 Maestro AI Framework `v1.1.0`

**O Framework Definitivo para Orquestração de Agentes Autônomos de Elite.**

O Maestro AI é uma arquitetura escalável para gerenciar ciclos de vida de software usando múltiplos agentes IA especializados (Persona-Driven AI). Ele garante a aplicação rigorosa de processos, previne pulos de fase e gerencia a **Melhoria Contínua** do time artificial em tempo real.

---

## 🚀 Novidades da Versão v1.1.0

1. **Novo Agente: `@ai-eng` (Engenheiro de IA)**: Especialista nativo em Prompt Engineering, Vetores, Janelas de Contexto e RAG, atuando em paralelo com o `@dev`.
2. **Mecanismo de Auto-Sincronização Framework-First**: Nova rotina em PowerShell para exportar evoluções de agentes de projetos locais de volta para o núcleo do framework.
3. **Refinamento de Governança**: Checklists mentais do Maestro agora auditam a prova física de ativos (ex: migrations SQL) antes do encerramento da fase de arquitetura/dev.

---

## 🏗️ Arquitetura de Agentes

| Agente | Nome | Função Primária |
| :--- | :--- | :--- |
| **@maestro** | O Orquestrador | Gerente central. Interpreta, planeja e delega. |
| **@ba** | Business Analyst | Levanta viabilidade técnica e escreve a PRD inicial. |
| **@ux-ui** | UX Designer | Desenha o Wireframe e dita as regras de design system. |
| **@architect**| Arquiteto | Desenha o plano de implementação e as regras de dados. |
| **@dev** | Desenvolvedor | Implementa código focado em TDD e Clean Architecture. |
| **@ai-eng** | AI Engineer | Otimiza prompts, vetores e a "inteligência" do produto. |
| **@qa** | Quality Assurer | Valida cobertura de testes, corner cases e bugfixes. |
| **@devops** | DevOps | Versionamento, Commits padronizados e Infraestrutura. |

---

## 🔄 Ciclo de Vida Obrigatório (O Fluxo)

Operador ➡ **@maestro**
1. 📋 **CONTEXTO**: Análise fria dos ativos e regras atuais do repositório.
2. 💡 **DESCOBERTA**: `@ba` traduz o desejo do usuário em um escopo técnico (PRD).
3. 🎨 **EXPERIÊNCIA**: `@ux-ui` garante que a jornada seja premium e visualmente impecável.
4. 📐 **ARQUITETURA**: `@architect` decompõe a entrega em passos lógicos e seguros.
5. 🛠️ **DEV / IA**: `@dev` e `@ai-eng` constroem a funcionalidade lado a lado.
6. ✅ **VALIDAÇÃO**: `@qa` quebra o código e garante 100% de confiabilidade.
7. 📦 **VERSÃO / DEPLOY**: `@devops` empacota e entrega o valor gerado.

---

## 🔄 Rotina de Evolução Contínua

O Maestro aprende com seus erros. Feedbacks registrados em `.gemini/melhoria-continua/` modificam o comportamento dos agentes na próxima rodada.

### 📡 Como Sincronizar Evoluções com o Core
Criamos um script de bootstrap reverso para garantir que a evolução do seu framework acompanhe o uso real. No diretório de ferramentas:

```powershell
# Exporta agentes evoluídos de um projeto local de volta para a base do framework
.\scripts\sync-maestro-framework.ps1 -Action export

# Faz push das novidades de volta para o GitHub upstream
.\scripts\sync-maestro-framework.ps1 -Action push
```

---

## ⚖️ Licença

Licença MIT. Desenvolvido com ❤️ por Ivan Ltds e Inteligência Artificial Autônoma.