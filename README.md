# Joga Bonito — PIM IV (ADS · UNIP 2026/2)

Solução completa de comércio eletrônico para a **Joga Bonito**, loja de camisas da Temporada 2026, camisas retrô e chuteiras de campo, society e futsal.

| Parte | Tecnologia | Pasta |
|---|---|---|
| Site | HTML5 · CSS3 · JavaScript | `Site/HTML`, `Site/CSS`, `Site/Javascript` |
| API REST | .NET 8 (camadas, JWT, BCrypt, Swagger) | `Site/backend` |
| Testes | xUnit (unitários) · xUnit + SQL Server (integração) · Playwright (E2E) · flutter test | `Site/tests`, `Mobile/test` |
| Banco de dados | SQL Server (13 tabelas, 12 índices, 3 views, 2 funções, 10 procedures, 3 triggers) | `Site/banco` |
| App | Flutter (Android/iOS) | `Mobile` |
| Nuvem | Azure (App Service, Azure SQL, Key Vault, Application Insights) como código | `infra/main.bicep` |
| DevOps | Docker, Docker Compose, GitHub Actions | `docker-compose.yml`, `.github/workflows` |
| Ágil | Backlog, sprints, cronograma, Kanban, burndown (planilha `.xlsx`) | entregue com o trabalho |
| Documento | Trabalho ABNT do PIM IV (.docx + PDF); figuras e fontes dos diagramas | entregue pelo sistema da UNIP; figuras em `ABNT/figuras` |

> O trabalho escrito e a planilha de backlog não ficam neste repositório público: o manual do PIM (seção 7) trata a publicação do próprio trabalho como autoplágio, e a UNIP compara a entrega com o que está na internet. Ver `Maestro/docs/adr/006-documentos-fora-do-repositorio.md`.

## Como rodar no computador

### Opção 1 — Windows: liga uma vez, depois é só fazer login
Requisitos: **.NET 8 SDK** e um **SQL Server** (Express, instância padrão ou LocalDB do Visual Studio). Se faltar algum, o lançador avisa e oferece instalar pelo `winget`.

**Na primeira vez**, dê dois cliques em `iniciar-projeto.bat`. Ele:
1. encontra o SQL Server e liga o serviço se estiver parado;
2. compila e sobe a API sem janela;
3. cria o banco `JogaBonitoDB` com os 36 produtos e as contas de demonstração;
4. abre a tela de login;
5. **liga a API junto com o Windows** e cria o atalho **Joga Bonito** na área de trabalho.

**Daí em diante** a API já está no ar quando o computador liga: abra http://localhost:5000 (ou o atalho) e faça login. Na tela de login, com a loja rodando no computador, os botões **Cliente**, **Administrador** e **Professor** entram com um clique nas contas de demonstração.

| Arquivo | O que faz |
|---|---|
| `iniciar-projeto.bat` / atalho **Joga Bonito** | Liga a loja (se ainda não estiver no ar) e abre o login |
| `parar-projeto.bat` | Desliga a API (necessário só para depurar pelo Visual Studio) |
| `desligar-com-o-windows.bat` / `ligar-com-o-windows.bat` | Desliga ou religa o início automático |

**Sem "erro de conexão" no login:**
- **Página aberta fora da API** (Live Server do VS Code, `127.0.0.1:5500` ou HTML aberto com dois cliques): ela é reaberta na loja servida pela API, onde a sessão funciona.
- **API ainda ligando:** o login mostra "Ligando a loja…" e entra sozinho quando ela responder.
- **Banco fora do ar:** a mensagem diz qual conexão falhou.
- **Visual Studio / `dotnet run`:** se o `.\SQLEXPRESS` não responder, a API procura sozinha outro SQL Server no computador (instância padrão ou LocalDB). Se o banco não estiver pronto ao ligar, ela tenta de novo a cada 20 s.

**VS Code:** ao abrir a pasta do projeto, a tarefa "Joga Bonito: ligar a API" roda sozinha (o VS Code pede permissão uma vez). F5 depura a API e já desliga a do lançador antes.

**Visual Studio:** F5 abre a loja no login. Se aparecer "a porta já está em uso", a loja já está no ar pelo início automático: rode `parar-projeto.bat` antes de depurar.

O log fica em `%LOCALAPPDATA%\JogaBonito\logs\api.log`. Para testar o app num **celular físico** na mesma rede: `iniciar-projeto.bat -Rede`.

### Opção 2 — Site público (GitHub Pages ou Vercel), sem servidor
Para divulgar a loja num link, há uma versão que roda inteira no navegador de quem visita:
- o link abre direto na página inicial;
- o visitante entra com as contas de demonstração (botões na tela de login) ou cria conta, compra, acompanha pedidos e usa o painel do administrador;
- as regras são as mesmas da API (estoque, cupons, frete, Joga Junto, moderação, segurança da sessão);
- os dados ficam só no navegador dele, e a faixa amarela no topo tem o botão "Recomeçar a demonstração".

**Por que não "ligar o `.bat` pelo link"?** Nenhum site consegue executar programas no computador de quem o visita: os navegadores bloqueiam isso por segurança. Por isso, a versão pública não precisa do `.bat` nem de servidor. A loja completa, com .NET e SQL Server de verdade, fica para o seu computador (opções 1 e 3) ou para a nuvem ([infra/IMPLANTACAO.md](infra/IMPLANTACAO.md)).

**GitHub Pages:**
1. Envie o projeto para o GitHub.
2. Em *Settings › Pages › Source*, escolha **GitHub Actions**.

A cada push na `main`, o workflow `site-publico.yml` organiza as fotos, gera o site e publica em `https://<usuario>.github.io/<repositorio>/`.

**Vercel:** *Add New › Project* e importe o repositório. O `vercel.json` da raiz já define o build (fotos + site público), a pasta `publico/` e os cabeçalhos de segurança. Não precisa configurar nada.

**Testar no seu computador:**
```bash
python Site/ferramentas/publicar_estatico.py
python -m http.server 8080 -d publico
```
Depois abra http://localhost:8080.

### Opção 3 — Docker
```bash
powershell -ExecutionPolicy Bypass -File gerar-env.ps1   # Windows (ou: sh gerar-env.sh)
docker compose up -d --build
```
O `gerar-env` cria um `.env` com senha do SQL Server, chave JWT e chave de criptografia dos dados (`DADOS_CHAVE`) aleatórias, só deste computador — guarde uma cópia da `DADOS_CHAVE`. Rodando de novo, ele só acrescenta o que faltar. Sem ele o Docker Compose não sobe. O banco fica acessível apenas em `127.0.0.1:1433`.

### Abrir o site por outro servidor (Live Server, hospedagem separada)
O site descobre sozinho onde está a API (`Site/Javascript/config.js`): servido pela própria API usa a mesma origem (local ou publicado); aberto no próprio computador por outro servidor usa `http://localhost:5000`. Para hospedar o site num lugar e a API em outro, preencha `apiBase` em `config.js` e libere a origem em `Cors__Origens__0`.

### App mobile
Veja `Mobile/README.md` (`flutter create .` → `flutter run`). O app aceita HTTP só para o PC na rede local (10.0.2.2, 192.168.x.x…); fora dela, exige HTTPS.

## Contas de demonstração (somente Development)

| Perfil | E-mail | Senha |
|---|---|---|
| Administrador | admin@jogabonito.com | Admin@2026 |
| Cliente | matheus@estudante.com | Cliente@2026 |
| Avaliador | professor@unip.br | Unip@2026 |

Cupons: `BEMVINDO10` (10%), `HEXA2026` (5%), `RETRO15` (15% acima de R$ 500).

Essas contas vêm de `Site/banco/demo.sql`, que **não é carregado em produção**. Em produção o administrador inicial é criado a partir de `Banco__AdminEmail` e `Banco__AdminSenha` (guardada no Key Vault).

## Testes

**Tudo de uma vez no Windows:** `testar-tudo.bat`. Ele roda unitários, integração com o SQL Server local, E2E, aceitação contra a API real e o app Flutter, e mostra um resumo.

**Validação de aceitação contra a API real** (75 verificações: sessão, 36 produtos, cupom, frete, Joga Junto, compra, cancelamento com devolução do estoque, permissões, painel admin, moderação e LGPD):

```bash
python Site/tests/aceitacao/validar_loja.py http://localhost:5000
```

Depois, `Site/banco/conferencia.sql` confere no banco 23 regras de consistência: totais, frete, Joga Junto, estoque × auditoria, criptografia e LGPD.


```bash
dotnet test Site/tests/JogaBonito.Tests             # unitários (regras, segurança, moderação, Joga Junto, LGPD)
python Site/tests/e2e/test_loja.py                  # 26 testes no navegador com API simulada (Site/tests/e2e/README.md)
cd Mobile && flutter test                           # modelos, sessão segura, carrinho e leitor de tela
```

**Integração com a API real e o SQL Server** (cadastro, compra, baixa de estoque, cancelamento, duas compras simultâneas da última peça, permissões, moderação, LGPD, revogação de sessão, scripts rodando duas vezes sem duplicar):

```bash
# PowerShell
$env:JB_TESTE_SQL = "Server=.\SQLEXPRESS;Trusted_Connection=True;TrustServerCertificate=True"
dotnet test Site/tests/JogaBonito.IntegrationTests
```
Os testes criam um banco temporário `JogaBonitoTeste_...` e o apagam no fim. Sem `JB_TESTE_SQL`, aparecem como ignorados. No GitHub Actions eles rodam sempre, com um SQL Server 2022 em container.

## Arquitetura da API

```
Site/backend/
├── Domain/          Usuario, Produto (abstrata) ← Camisa / Chuteira, Pedido, Cupom, RegraFrete,
│                    RegraJogaJunto, ModeracaoAvaliacao
├── Application/     DTOs, interfaces e serviços (Auth, Catálogo, Pedido, Privacidade)
├── Infrastructure/  Repositórios ADO.NET, inicializador do banco, JWT, BCrypt, sessão, cache, health check
├── Endpoints/       /api/auth · /api/produtos · /api/pedidos · /api/admin
├── Middleware/      tratamento de erros e cabeçalhos de segurança
└── Program.cs       injeção de dependências e pipeline HTTP
```

## Banco de dados: criação e atualização

| Script | Quando roda | O que faz |
|---|---|---|
| `schema.sql` | sempre | Tabelas, migrações (`ALTER TABLE` para bancos antigos), índices, views, funções, procedures, triggers |
| `catalogo-local.js` | sempre (Development) | Se o arquivo mudou, leva nome, preço, descrição, fotos e destaque para o banco — **inclusive com a API ligada** (salvou, em ~2 s a loja mostra) |
| `seed.sql` | sempre | Categorias, cupons, estoque que falta e o catálogo **versionado**: insere produtos ausentes e, se a lista mudou em `gerar_catalogo.py`, atualiza os 36 e refaz a galeria — sem apagar pedidos nem clientes |
| `demo.sql` | só Development | Contas, pedidos e avaliações de demonstração |
| `seguranca.sql` / `seguranca-azure.sql` | uma vez, como admin | Usuário `jogabonito_app` com privilégio mínimo; a senha vem por variável do `sqlcmd` (`-v SENHA_APP=...`), nunca do arquivo |

Se um lote de `schema.sql` ou `seed.sql` falhar, a inicialização **para** e `/health/ready` responde `Unhealthy` com o motivo. O `/health/ready` também confere se todos os objetos do esquema existem e se há produtos ativos.

## Segurança

Relatório completo da auditoria, com cada falha encontrada e a correção: **[SEGURANCA.md](SEGURANCA.md)**.

- **Sessão do site** em cookie `HttpOnly` + `SameSite=Strict` (o JavaScript não vê o token) com proteção CSRF (cabeçalho obrigatório + conferência de origem). O app usa token no Keystore/Keychain.
- **Dados dos clientes protegidos no banco:** endereço e telefone cifrados com AES-256-GCM (chave no Key Vault); e-mail e IP com mascaramento dinâmico para quem não é a aplicação; log de acessos apagado após 180 dias.
- **Login:** BCrypt, bloqueio por 15 min após 5 senhas erradas, senhas comuns recusadas, mesmo tempo de resposta para e-mail existente ou não; revogação de sessões na troca de senha.
- **Sem segredos no repositório:** em desenvolvimento cada computador gera suas chaves em `%LOCALAPPDATA%\JogaBonito`; em produção a API não sobe sem chave JWT própria, sem chave de criptografia ou conectada como `sa`.
- **Limites:** 300 req/min por IP, 10 logins/min, 15 pedidos/min, 20 validações de cupom/min; CSP sem scripts inline; HTTPS + HSTS em produção.
- **Conferir o site publicado:** `python3 Site/ferramentas/verificar_publicacao.py https://endereco-da-loja`.

## Funcionalidades de responsabilidade social

- **Moderação de avaliações:** comentários com link, contato ou termos da lista `Moderacao:TermosBloqueados` entram como *Pendente*; o admin publica ou oculta (com motivo) na aba **Avaliações**. A loja só mostra avaliações publicadas; `sp_ModerarAvaliacao` registra quem moderou, quando e por quê.
- **Joga Junto:** 1% do valor dos produtos de cada pedido (com desconto, sem frete) é calculado no banco (`fn_CalcularJogaJunto`), gravado no pedido e somado no painel e na consulta `joga-junto`.
- **LGPD:** em Meus pedidos › Meus dados o cliente baixa todos os seus dados (JSON) ou exclui a conta com a senha; `sp_AnonimizarUsuario` apaga nome, e-mail, endereços e avaliações e mantém os pedidos sem dados pessoais (obrigação fiscal).
- **Acessibilidade:** VLibras em todas as páginas (inclusive o painel), ajuste de fonte, alto contraste, navegação por teclado (abas com setas), rótulos em todos os campos e rótulos para TalkBack/VoiceOver no app — verificados pelos testes E2E e de widget.

## Nuvem (Azure)

`infra/main.bicep` descreve toda a infraestrutura:
- **App Service** Linux com identidade gerenciada, health check e autoescala de 1 a 4 instâncias;
- **Azure SQL** serverless com firewall só para os IPs de saída do App Service e backups de 7 dias + 4 semanas;
- **Key Vault** com os segredos (JWT, conexão, chave dos dados pessoais);
- **Log Analytics + Application Insights**, com alertas de 5xx, lentidão e CPU do banco.

**Passo a passo completo — criar a infraestrutura, dar ao GitHub acesso por OIDC, publicar e validar: [infra/IMPLANTACAO.md](infra/IMPLANTACAO.md).**

A cada push na `main`, o pipeline:
1. testa tudo (unitários, integração com SQL Server, E2E, app);
2. publica a imagem no GHCR;
3. lê os nomes criados pelo Bicep;
4. abre o firewall só para o próprio IP e migra o banco;
5. implanta a imagem;
6. confere as referências do Key Vault, `/health/ready` e `verificar_publicacao.py`.

Sem configuração, o resumo do pipeline avisa **"Deploy NÃO realizado"**; com `DEPLOY_OBRIGATORIO=true`, o pipeline falha.

Depois de publicar, `bash infra/conferir-azure.sh rg-jogabonito` confere:
- HTTPS, TLS, segredos e firewall;
- TDE e backups;
- alertas e telemetria;
- que as contas de demonstração não entram.

## Catálogo e imagens dos produtos

O catálogo (36 itens, IDs 1–36) pode ser editado de dois jeitos:

1. **Direto em `Site/Javascript/catalogo-local.js`** (nome, preço, descrição, fotos, destaque): com a API ligada, ao salvar o arquivo o banco é atualizado em ~2 segundos. Cada produto é validado (categoria, linha, preço, imagem dentro de `IMG/Produtos/`); um produto inválido é ignorado e aparece no log. O estoque do banco não é sobrescrito, porque muda a cada venda.
2. **Pelo gerador** `Site/ferramentas/gerar_catalogo.py`, que também redesenha as ilustrações e atualiza o `seed.sql` usado na nuvem:

```bash
python3 Site/ferramentas/gerar_catalogo.py
```

> O gerador reescreve o `catalogo-local.js`. Se você editou o arquivo à mão, passe as mudanças para a lista do gerador antes de rodá-lo.

**Fotos:** coloque as fotos do produto em `Site/IMG/Produtos/<id>/`, com **qualquer nome e formato** (jpg, png, webp, avif). Não há passo manual:
- **Com a loja ligada no computador:** a API percebe a mudança na pasta e, em cerca de 2 s, as fotos viram a capa e a galeria do produto.
- **Com Python instalado:** o `iniciar-projeto.bat` padroniza as fotos ao ligar a loja (`1.jpg`, `2.jpg`…, até 1200 px). Os originais vão para `IMG/Produtos/_originais/`, nada é apagado.
- **No site público:** o build do GitHub Pages/Vercel faz a mesma padronização.

Na galeria, as fotos aparecem na ordem natural dos nomes, números primeiro (`1`, `2`, `10`, depois `costas`, `frente`), e a primeira é a capa. Produto sem foto mostra a ilustração; quando chega a primeira foto, a ilustração sai.

**Craques (`craques.html`):** as camisas levam só o nome do time; os jogadores ficam na página **Craques que vestiram o manto** e na vitrine da página inicial. Cada craque tem a sua história e o link para a camisa do time:
- Romário (Brasil 1994);
- Kaká (Milan 2006/07);
- Cristiano Ronaldo (Manchester United 2007/08);
- Mbappé (Real Madrid);
- Lamine Yamal (Barcelona).

As fotos ficam em `Site/IMG/Jogadores/` com estes nomes: `romario-1994.jpg`, `kaka.jpg`, `cr7-2008.jpg`, `mbappe.jpg` e `lamine-yamal.jpg`. Enquanto uma foto não existir, aparece um cartão com o número e as cores do time; colocou o arquivo, a foto aparece. Para acrescentar um craque (por exemplo, Pelé), inclua-o em `JB.craques`, em `Site/Javascript/vitrine-info.js`.
