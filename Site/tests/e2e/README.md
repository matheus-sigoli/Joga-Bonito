# Testes ponta a ponta (E2E) — Playwright

Os testes abrem a loja em um Chromium sem janela e fazem o que um cliente e o administrador fazem: navegar, filtrar, comprar, errar a senha, trocar a senha e consultar o log de acessos.

Para rodar em qualquer máquina, eles usam uma **API simulada** (`mock-api.js`). Ela segue o mesmo contrato da API .NET: mesmas rotas, códigos HTTP, JSON e cabeçalho Content-Security-Policy. Os produtos vêm de `Javascript/catalogo-local.js`, que é gerado da mesma fonte do `banco/seed.sql`.

## Como rodar

```bash
# uma vez
pip install playwright
python -m playwright install chromium

# na raiz do repositório (a porta 5000 precisa estar livre)
python Site/tests/e2e/test_loja.py
```

São necessários Node.js 18+ e Python 3.10+.

## O que é verificado

| # | Teste | Requisito |
|---|---|---|
| 01 | Os 36 produtos com ID, nome e preço idênticos à planilha (com as trocas do grupo); marca e solado em todas as chuteiras (4 futsal, 4 society, 4 campo) | Catálogo |
| 02 | Toda imagem e galeria aponta para um arquivo que existe; nenhuma imagem Froggy | Vitrine |
| 03 | Cabeçalhos CSP e nosniff | Segurança |
| 04 | Nenhum `onclick`/`onerror` nem `<script>` inline (a CSP os bloquearia) | Segurança |
| 05 | Página inicial: Temporada com Seleções x Clubes, vitrine Retrô | UX |
| 06 | Filtro **Marca** aparece só em Chuteiras e filtra de verdade (Umbro → 2) | Planilha |
| 07 | Página da chuteira mostra a ficha com marca e tipo de solado | Planilha |
| 08 | Compra completa: carrinho, login, cupom BEMVINDO10, endereço, Pix e pedido em "Meus pedidos" | Fluxo principal |
| 09 | 5 senhas erradas bloqueiam a conta; a senha certa continua barrada | Segurança |
| 10 | Troca de senha exige a senha atual | Segurança |
| 11 | Painel admin lista o log de acessos (falha e sucesso) | Segurança |
| 12 | Nenhuma página rola na horizontal no celular (390 px) | Responsividade |
| 13 | Trocar a senha derruba as outras sessões; "sair de todos" derruba todas | Segurança |
| 14 | Login e cadastro mostram a foto do jogador | Design |
| 15 | Avaliação com link vai para moderação; admin exige motivo para ocultar e publica pela aba Avaliações | Responsabilidade social |
| 16 | Baixar meus dados (JSON) e excluir conta com senha; o e-mail deixa de entrar | LGPD |
| 17 | Aviso de pagamento simulado, valor do Joga Junto e carrinho preservado quando o servidor recusa a compra | Checkout |
| 18 | Teclado: "pular para o conteúdo", abas do painel com setas/End; VLibras no painel | Acessibilidade |
| 19 | Todo campo tem rótulo e toda imagem tem `alt` (9 páginas) | Acessibilidade |
| 20 | Fonte ampliada 4 vezes no celular não cria rolagem lateral nem esconde "Adicionar ao carrinho" | Acessibilidade |
| 21 | Site num domínio publicado usa a própria origem para a API (nunca o localhost do visitante) | Publicação |

Qualquer erro de JavaScript ou violação de CSP no console reprova o teste em andamento.

O pipeline do GitHub Actions (`.github/workflows/ci-cd.yml`, job **web**) roda esta suíte a cada push.

Esta suíte prova o **front-end**. As regras do banco (procedures, triggers, transações, concorrência) são provadas pelos testes de integração em `Site/tests/JogaBonito.IntegrationTests`, contra a API real e um SQL Server de verdade.
