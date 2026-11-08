# ADR 005 — Prazo de 2 semanas: toda a lista entra no escopo

**Data:** 27/10/2026 · **Situação:** aceita

## Contexto
Lista de pendências de 27/10/2026, com prazo de entrega em até 2 semanas (até ~10/11/2026).

## Decisão
Todos os itens da lista entram no escopo. A ordem segue o que destrava o resto:

1. Ligar a pasta ao repositório GitHub ([ADR 001](001-repositorio-github.md)).
2. Instalar o Flutter e validar o app (analyze, testes, celular real) ([ADR 003](003-app-testado-em-celular-real.md)).
3. Integração Web + Mobile + API: compra pelo app aparece no mesmo histórico.
4. Acessibilidade manual: VLibras, contraste, leitor de tela (NVDA no site, TalkBack no app).
5. Conferir o site público publicado (aviso de pagamento simulado, sem chamar a API).
6. Azure, se for decidido publicar ([ADR 002](002-implantacao-azure-adiada.md)).

## Situação em 27/10/2026
| Item da lista | Situação |
|---|---|
| Executar todos os testes | Unitários 104, integração 9, Web 30, aceitação 75 e Flutter 15: OK |
| Validar o banco | 22/23 OK (a 23 só vale em produção) |
| Compra completa | OK pelos testes de aceitação e Web |
| Integração Web + Mobile + API | Web OK; Mobile pendente |
| Segurança | Testada localmente; HTTPS e banco restrito dependem do Azure |
| App Flutter | Flutter 3.47.8 instalado; analyze sem avisos, 15 testes OK, APK de depuração gerado. Falta o teste no celular (roteiro 5) |
| Azure | Pronto, publicação adiada |
| Acessibilidade | Automática OK; manual pendente |
| Joga Junto e privacidade | OK |
| Site público | https://joga-bonito-sigma.vercel.app aberto ao público, com aviso de pagamento simulado e VLibras. Ainda sem as 41 fotos novas (sobem no próximo push) |

## Situação em 08/11/2026
Detalhes em [ADR 008](008-verificacao-final-nov-2026.md).

| Item da lista | Situação |
|---|---|
| Executar todos os testes | Web 30/30 local; pipeline corrigido (teste do checkout e GitHub Pages) |
| Integração Web + Mobile + API | Web conferida no site publicado; **Mobile pendente** (celular real) |
| Acessibilidade | VLibras 7.12 e teclado conferidos no site publicado; **NVDA e TalkBack pendentes** |
| Site público | Conferido no navegador: inicial, login de demonstração, compra com Pix, painel admin |
| Azure | Plano pronto; publicação continua adiada ([ADR 002](002-implantacao-azure-adiada.md)) |
| Backlog | Sprint 6 estendida até 10/11; 157 de 165 pontos (95%) |
