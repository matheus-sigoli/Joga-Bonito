# ADR 008 — Verificação final de 08/11/2026: pipeline, site publicado e VLibras 7.12

**Data:** 08/11/2026 · **Situação:** aceita e aplicada

## Contexto
A análise do projeto contra o *Manual do PIM IV — ADS 2026/2* (grade das matérias, 07/11/2026)
apontou que a última execução do GitHub Actions (29/10, commit "Joga Bonito — PIM IV") estava
vermelha e que a acessibilidade e o site publicado ainda não tinham sido conferidos num navegador real.

## O que foi encontrado
| Onde | Problema | Causa |
|---|---|---|
| Workflow **CI-CD** | 1 de 30 testes E2E falhou (`test_17`, checkout): `#cep` não apareceu em 30 s | O passo `entrar()` do teste clicava em "Entrar" e seguia sem esperar a resposta. Na máquina mais lenta do GitHub, o teste abria o carrinho com o login ainda em andamento, a navegação cortava a requisição e a sessão nunca era gravada; "Finalizar" então levava à tela de login. Erro do teste, não da loja. Localmente os 30 testes passam. |
| Workflow **Site público** | Falha em todo push: "Get Pages site failed" | O GitHub Pages não está ativado; o site oficial sai pela Vercel. |
| Ações do GitHub | Aviso de Node.js 20 obsoleto | `checkout@v4`, `setup-node@v4`, `setup-python@v5`, `setup-dotnet@v4`, `upload-artifact@v4`. |
| `Site/IMG/Jogadores` | 11 fotos originais soltas (`messi.jpg`, `cr7 1.jpg`, `Kaka.avif`…) que o site não usa | Enviadas junto com as fotos novas em 28/10. |

## Decisão e correções
- `test_loja.py`: `entrar()` espera a resposta de `/api/auth/login` e, se deu certo, a saída da tela
  de login (a causa real, achada pelo diagnóstico da primeira correção).
- `test_loja.py`: novo passo `abrir_checkout()` (espera a rede ficar parada, clica, espera a janela do
  checkout e tenta mais uma vez); se não abrir, o teste falha mostrando a URL e o aviso da página.
  Usado nos testes 8 e 17.
- `site-publico.yml` passa a rodar **só manualmente** (Actions › Site público › Run workflow).
  Continua disponível se o grupo quiser ativar o GitHub Pages.
- Ações atualizadas para as primeiras versões em Node 24: `checkout@v5`, `setup-node@v5`,
  `setup-python@v6`, `setup-dotnet@v5`, `upload-artifact@v6`.
- `Site/backend/Dockerfile`: copia `Javascript/catalogo-local.js` para a etapa de build. Com os testes
  verdes, o job da imagem rodou pela primeira vez e 2 testes do sincronizador falharam dentro do
  container porque não achavam o catálogo.
- As 11 fotos foram **movidas** (não apagadas) para `Site/IMG/Jogadores/outras/originais/`, e o
  `publicar_estatico.py` deixa essa pasta fora do site público. Mover em vez de apagar evita que um
  `git pull` no PC apague os arquivos.

## Site publicado conferido no navegador (https://joga-bonito-sigma.vercel.app)
Teste feito no navegador do app Claude no PC, em 08/11/2026:
- abre direto na página inicial, sem imagens quebradas;
- **VLibras 7.12:** o plugin novo não usa mais o `<div vw>` e cria o próprio botão (shadow DOM, fixo
  à direita). O botão aparece, abre o avatar e traduz. O plugin tenta carregar o **PostHog**
  (estatísticas de uso do VLibras) de `cdn.jsdelivr.net/npm/posthog-js`; a CSP bloqueia de propósito.
  O VLibras trata a falha e funciona normalmente, e nenhum dado de uso sai para terceiros.
  O `<div vw>` antigo de `layout.js` fica vazio e invisível; foi mantido por compatibilidade.
- login de demonstração **Cliente** com um clique;
- compra completa: camisa id 10 (M), CEP preenchido pelo ViaCEP, Joga Junto de R$ 4,00, aviso de
  pagamento simulado, Pix e "Pedido confirmado" com código de rastreio;
- painel do **Administrador**: 7 abas, o pedido aparece em Pedidos com origem **Web** e status Pago;
- teclado: o primeiro Tab vai para "Pular para o conteúdo".

## Planilha de backlog (fora do repositório, ADR 006)
- Sprint 6 estendida até 10/11 como sprint de fechamento.
- Item 20 (plano Azure) concluído; 21 (documento ABNT) em revisão; 22 (testes de aceitação) em andamento.
- 4 tarefas novas no Sprint Backlog; Kanban com a situação de 08/11. Pontos: 157 de 165 (95%).

## O que continua com o grupo
- Rodar o app num celular Android real (roteiro 5) e mostrar a compra com origem **Mobile**.
- Leitor de tela: NVDA no site e TalkBack no app (roteiros 1 e 2).
- Decidir se a banca verá a loja no Azure (ADR 002); o manual pede só o plano.
- Vídeo de demonstração, postagem no sistema da UNIP e cópia impressa.
