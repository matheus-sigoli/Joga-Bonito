# PRD-002 — Turbinar o Joga Bonito (catálogo, design, segurança, banco/API)

> Status: **Concluído** (aprovado pelo Operador em 2026-10-23) · Data: 2026-10-23 · Origem: pedido do Operador + planilha `catalogo_de_produtos.xlsx` + Manual PIM IV

## 1. Contexto e problema
O projeto já cumpre as 9 etapas do manual, mas o catálogo ainda é o provisório (18 itens, fotos trocadas e fotos da antiga marca Froggy nas chuteiras) e há pontos técnicos que um avaliador de Segurança, Banco de Dados e Web pode cobrar: sem bloqueio de conta após tentativas de login, sem política de conteúdo (CSP), conexões ao banco sem retentativa, nenhum cache, sem testes ponta a ponta versionados.

## 2. Catálogo definido pelo Operador (planilha)
| Grupo | Itens | Faixa de preço | Campos |
|---|---|---|---|
| Temporada 2026 | 12 (5 seleções, 7 clubes) | R$ 329,90 – 399,90 | Linha, Equipe, Ano |
| Camisas Retrô | 12 (2 seleções, 10 clubes) | R$ 299,90 – 329,90 | Linha, Equipe, Ano de referência |
| Chuteiras Futsal | 4 (Nike, adidas) | R$ 399,90 – 499,90 | Marca, Tipo de solado (IC/Indoor) |
| Chuteiras Society | 4 | R$ 499,90 – 599,90 | Marca, Tipo de solado (TF) |
| Chuteiras Campo | 4 | R$ 799,90 – 899,90 | Marca, Tipo de solado (FG) |

Total: **36 produtos**, IDs 1–36 exatamente como na planilha. Todos respeitam os preços mínimos (camisa ≥ R$ 160, chuteira ≥ R$ 250).

## 3. Melhorias indicadas

### 3.1 Banco de dados (Etapa 7)
| # | Melhoria | Por quê |
|---|---|---|
| B1 | Novo seed com os 36 produtos da planilha (IDs 1–36) | Catálogo oficial do Operador |
| B2 | Colunas **Marca** e **Solado** em Produtos (+ índice por Marca) | Chuteiras são filtradas por marca e tipo de solado |
| B3 | Colunas de **bloqueio de login** em Usuarios + tabela **LogAcessos** | Auditoria de segurança e bloqueio após 5 erros |
| B4 | Procedure **sp_RegistrarTentativaLogin** | Regra de bloqueio no banco, atômica |
| B5 | Script **seguranca.sql** com usuário de aplicação de privilégio mínimo (sem `sa`) | Boa prática exigida em produção |
| B6 | Galeria gerada só com arquivos que existem de fato | Fim de miniaturas quebradas |

### 3.2 API / conexões (Etapas 4 e 6)
| # | Melhoria | Por quê |
|---|---|---|
| A1 | **Retentativa automática** de conexão/comando (SqlClient Retry Logic, erros transitórios) + pool configurado | Banco na nuvem tem falhas momentâneas |
| A2 | **Cache em memória** do catálogo (30 s), invalidado quando o admin altera produto/estoque | Menos consultas, vitrine mais rápida |
| A3 | **Compressão** de respostas (Brotli/Gzip) | Menos dados no celular |
| A4 | Filtros novos: `marca`, `precoMax`, e retorno de `marca`/`solado` | Planilha e catálogo |
| A5 | Health check separado: `/health/live` e `/health/ready` | Orquestrador na nuvem (Etapa 8) |

### 3.3 Segurança
| # | Melhoria | Por quê |
|---|---|---|
| S1 | **Bloqueio de conta** por 15 min após 5 senhas erradas + log de acessos (IP, sucesso/falha) | Força bruta (OWASP A07) |
| S2 | **Content-Security-Policy** e remoção de `onclick` inline | XSS (OWASP A03) |
| S3 | **HTTPS + HSTS** em produção | Dados de login em trânsito |
| S4 | API **não sobe em produção com a chave JWT padrão** | Segredo vazado no repositório |
| S5 | Limite de tamanho de requisição (1 MB) e rate limit também no checkout | Abuso / negação de serviço |
| S6 | Endpoint **trocar senha** (exige senha atual) | Ciclo de vida da credencial |

### 3.4 Design / experiência (Etapas 3 e 4)
| # | Melhoria | Por quê |
|---|---|---|
| D1 | **Imagem desenhada** por produto quando não há foto: camisa nas cores do time com o ano, chuteira com a sola do piso | Hoje aparecem fotos erradas ou da Froggy |
| D2 | Fotos reais reaproveitadas só onde batem com o produto (Brasil, Corinthians, Real, Barcelona, Milan…) | Honestidade da vitrine |
| D3 | Filtro por **marca** e selo de **tipo de solado** nas chuteiras | Planilha |
| D4 | Home: Temporada com seleções x clubes, Retrô com os ícones (Pelé 62, Zico 81, Tetra 94) | Conteúdo novo |
| D5 | Fontes servidas pelo próprio site (fallback local) e `preload` | Desempenho / layout estável |

### 3.5 Mobile (Etapa 5)
| # | Melhoria |
|---|---|
| M1 | Mesma imagem desenhada no app quando não há foto; mostra marca/solado |
| M2 | Trocar senha no Perfil |

### 3.6 Qualidade / testes (QA)
| # | Melhoria |
|---|---|
| Q1 | Testes **ponta a ponta com Playwright** versionados (`Site/tests/e2e`), com API simulada para rodar sem .NET |
| Q2 | Novos testes xUnit: bloqueio de login, filtro de marca, cache |
| Q3 | Pipeline CI roda os testes E2E |

### 3.7 Documentação ABNT
Atualizar capítulos 2, 5, 8 e 10 (catálogo de 36 itens, novas medidas de segurança, novas tabelas/procedure, backlog da sprint 6) e regenerar o .docx/.pdf.

## 4. Fora de escopo
Gateway de pagamento real, upload de imagens pelo painel, troca de banco de dados.

## 5. Critérios de aceite
- Vitrine, catálogo e app mostram exatamente os 36 produtos da planilha, com IDs, nomes e preços idênticos.
- 5 senhas erradas seguidas bloqueiam a conta por 15 min; o painel mostra o log de acessos.
- Nenhuma imagem quebrada ou de outra marca na loja.
- Testes E2E e unitários passam no CI.
- Documento ABNT atualizado, dentro de 20–30 páginas de desenvolvimento.

## 6. Experiência (UX-UI)
- Card de chuteira: marca + solado (ex.: “Nike · TF — society”).
- Catálogo: filtro **Marca** aparece só quando a categoria é Chuteiras.
- Produto sem foto: ilustração plana (camisa com listras/cores do time, número = ano abreviado) — nunca foto de outro produto.
- Perfil/Pedidos: “Trocar senha” discreto; mensagem de bloqueio clara (“Conta bloqueada por 15 minutos por segurança”).

## 7. Plano técnico (Architect)
| Camada | Arquivos |
|---|---|
| Banco | `Site/banco/schema.sql` (migração idempotente), `seed.sql` (36 itens), `seguranca.sql` (novo) |
| Domain/Application | `Usuario` (bloqueio), `Dtos` (marca/solado/trocar senha), `AuthServico`, `CatalogoServico` (cache) |
| Infrastructure | `ConexaoSql` (retry), repositórios (marca, log de acesso) |
| Program | compressão, HSTS, CSP, limites, health live/ready, validação da chave |
| Front | `api.js` (imagem desenhada), `catalogo.*`, `inicial.*`, `produto.js`, remoção de inline handlers, `admin` (log de acessos) |
| Mobile | `modelos`, `widgets/comum.dart` (imagem desenhada), `perfil_tela.dart` |
| QA | `Site/tests/e2e/*`, `DominioTests.cs`, `.github/workflows/ci-cd.yml` |
| Docs | ABNT .docx/.pdf, README, contexto-projeto |

## 8. Riscos
- CSP pode bloquear recursos do VLibras (domínios liberados; testar o widget no navegador).
- Sem SDK .NET/Flutter no ambiente de construção: código revisado manualmente; rodar `dotnet test` e `flutter test` localmente.
- Banco já criado na máquina: a migração adiciona colunas, mas o **seed só recria o catálogo se a tabela Produtos estiver vazia** — apagar o banco `JogaBonitoDB` uma vez para carregar os 36 produtos.

## 9. Entrega (Dev + QA)
| Item | Situação |
|---|---|
| B1–B6 banco | Feito: seed gerado por `ferramentas/gerar_catalogo.py`, migração idempotente, `LogAcessos`, `sp_RegistrarTentativaLogin`, `seguranca.sql` |
| A1–A5 API | Feito: Retry Logic + pool, cache 30 s com invalidação, Brotli/Gzip, filtros `marca`/`precoMax`, `/health/live` e `/health/ready` |
| S1–S6 segurança | Feito: bloqueio 5×/15 min (HTTP 423), CSP sem inline, HSTS opcional, chave JWT de exemplo recusada em produção, 1 MB, rate limit no checkout, trocar senha |
| D1–D4 design | Feito: ilustrações SVG para 31 produtos sem foto, fotos reais só onde batem (1, 7, 9, 10, 19), filtro de marca, ficha técnica, Temporada seleções x clubes, Retrô 62/81/94 |
| D5 fontes locais | Não feito: o ambiente de construção não acessa o Google Fonts para baixar os arquivos; o site segue com Google Fonts + fontes de reserva |
| M1–M2 mobile | Feito: `flutter_svg`, marca/solado, trocar senha no Perfil |
| Q1–Q3 QA | Feito: 12 testes E2E passando; 12 novos casos de teste xUnit; job E2E no CI. `dotnet test` e `flutter test` precisam rodar na máquina do time (sem SDK no ambiente de construção) |
