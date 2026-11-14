# QA — PRD-002

Data: 2026-10-23 · Executado por: QA (Maestro)

## Testes ponta a ponta (Playwright, Chromium headless, API simulada)
Comando: `python Site/tests/e2e/test_loja.py` → **12 de 12 aprovados** (≈22 s).

| # | Cenário | Resultado |
|---|---|---|
| 01 | 36 produtos idênticos à planilha (ID, nome, preço); 12 chuteiras com marca e solado | OK |
| 02 | Todas as imagens existem; nenhum arquivo Froggy | OK |
| 03 | CSP e nosniff nas respostas | OK |
| 04 | Nenhum handler/script inline no site | OK |
| 05 | Home: Seleções (5) x Clubes (6), Retrô | OK |
| 06 | Filtro de marca só em Chuteiras (adidas → 6) | OK |
| 07 | Ficha da chuteira (Nike · TF — society), grade 37–44 | OK |
| 08 | Compra: carrinho → login → BEMVINDO10 → endereço → Pix → Meus pedidos | OK |
| 09 | 5 senhas erradas bloqueiam; senha certa continua barrada | OK |
| 10 | Trocar senha exige a atual | OK |
| 11 | Admin › Acessos lista falha e sucesso | OK |
| 12 | Sem rolagem horizontal em 390 px | OK |

Nenhum erro de JavaScript nem violação de CSP no console durante a suíte.

## Pendente na máquina do time
- `dotnet test Site/tests/JogaBonito.Tests` (inclui `SegurancaCatalogoTests.cs`): não há SDK .NET no ambiente de construção; o código foi revisado manualmente.
- `flutter pub get && flutter test` (novo pacote `flutter_svg`).
- Conferir o widget VLibras com a CSP ativa, servido pela API real.

## Rodada 2 — 2026-10-23 (fotos, trocas de produto e sessões)
Mudanças: produto 5 vira Espanha; 22 Santos 2011 Neymar; 23 Real Madrid 2017; 24 Fiorentina 1998/99;
25–28 Umbro Pro 5 Bump, Joma Top Flex Rebound, Nike Lunar Gato, Umbro Adamant ProBump (preços mantidos);
fotos de jogadores no login/cadastro; revogação de sessões (VersaoToken), sair de todos, limite global por IP,
CORS/Swagger por ambiente, rehash BCrypt, status das conexões no painel.

Resultado: `python Site/tests/e2e/test_loja.py` → **14 de 14 aprovados** (novos: 13 sessões, 14 fotos de jogador).
Novos xUnit (rodar na máquina do time): rehash, versão do token na troca de senha, ValidadorSessao (4 casos).

## Rodada 3 — 2026-10-24 (lista de complementação do grupo)
| Item da lista | Situação |
|---|---|
| 1. Endereço da API por ambiente | Feito: `config.js` + detecção (mesma origem quando publicado). Teste E2E 21 com domínio fictício |
| 2. Inicialização/atualização do banco | Feito: para no 1º erro essencial, readiness confere esquema e catálogo, seed incremental versionado, `demo.sql` separado. Teste de integração roda os scripts 2x |
| 3. Produção segura | Feito: `.env` gerado, `sa` e chave de exemplo recusados em produção, admin por variável, `seguranca(-azure).sql` com senha por variável, `verificar_publicacao.py` |
| 4. Moderação de avaliações | Feito: Status + `sp_ModerarAvaliacao` + aba Avaliações + vitrine só publicadas |
| 5. Sessão no app | Feito: `flutter_secure_storage`, migração do token antigo, HTTPS fora da rede local, token vencido não é enviado |
| 6. Testes de integração | Feito: `JogaBonito.IntegrationTests` (9 cenários) e job com SQL Server no CI; mobile obrigatório antes do deploy |
| 7. Nuvem | Feito como código: `infra/main.bicep`, migração e verificação no deploy, aviso quando o deploy não ocorre. **Implantação real depende da assinatura Azure do grupo** |
| 8. Acessibilidade | Feito: VLibras no admin, abas por teclado, rótulos (estrelas, faixa de preço, Pix), correção de rolagem lateral com fonte ampliada, semântica no app. TalkBack/VoiceOver: roteiro em `roteiros-manuais.md` |
| 9. Joga Junto | Feito: 1% calculado no banco, gravado no pedido, mostrado no checkout e no painel |
| 10. Privacidade | Feito: baixar dados e excluir conta (site e app), política atualizada |
| 11. Checkout Web/Mobile | Conferido: confirmação só após o servidor, carrinho preservado na falha (teste 17), aviso de pagamento simulado nas duas plataformas |

E2E: **21 de 21 aprovados**. Defeitos encontrados pelos testes novos e corrigidos: faixa de preço sem rótulo, campo Pix sem rótulo, estrelas lidas como "★", busca do topo empurrando a página com fonte ampliada.
Pendente na máquina do time / CI: `dotnet test` (unitários e integração), `flutter test`, `az deployment` do Bicep.
