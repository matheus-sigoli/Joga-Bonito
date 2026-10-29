# Relatório de segurança — Joga Bonito (PIM IV)

Auditoria do sistema inteiro (API .NET, banco SQL Server, site e app Flutter) feita do ponto de vista de quem procura falhas. Cada achado traz o risco, o que foi corrigido e onde está a correção. No fim estão o que já estava protegido e os riscos aceitos.

Data da auditoria: outubro de 2026.

## Resumo

| # | Achado | Gravidade | Situação |
|---|---|---|---|
| 1 | Chave JWT de desenvolvimento publicada no repositório, com a API aberta para a rede | Alta | Corrigido |
| 2 | Token de sessão do site no `localStorage` (roubável por XSS) | Alta | Corrigido |
| 3 | Endereço e telefone dos clientes em texto aberto no banco | Alta | Corrigido |
| 4 | CSRF (consequência de usar cookie de sessão) | Média | Corrigido |
| 5 | Login revelava pelo tempo de resposta quais e-mails têm conta | Média | Corrigido |
| 6 | Política de senha: aceitava senhas comuns e havia conflito com o limite de 72 bytes do BCrypt | Média | Corrigido |
| 7 | Painel e console mostravam e-mail e IP completos | Média | Corrigido |
| 8 | `/health/ready` expunha detalhes da infraestrutura em produção | Média | Corrigido |
| 9 | Imagem de produto aceitava qualquer URL (`javascript:`, sites externos, `../../`) | Média | Corrigido |
| 10 | Log de acessos (e-mail + IP) guardado para sempre | Média (LGPD) | Corrigido |
| 11 | Dependência vulnerável: `Azure.Identity` 1.10.3 via SqlClient 5.1.5 (CVE-2024-35255) | Média | Corrigido |
| 12 | Validação de cupom sem limite próprio (descoberta de códigos por tentativa) | Baixa | Corrigido |
| 13 | Cabeçalho `Server: Kestrel` anunciava a tecnologia | Baixa | Corrigido |
| 14 | Firewall do Azure SQL com "AllowAllWindowsAzureIps": o banco aceitava conexões de qualquer serviço hospedado no Azure, inclusive de outros clientes | Alta | Corrigido |

## Achados e correções

### 1. Chave JWT pública e API aberta na rede
**Risco:** `appsettings.Development.json` trazia uma chave fixa e a API escutava em `0.0.0.0`. Quem conhece a chave (qualquer pessoa com acesso ao repositório) gera um token de **administrador** válido para qualquer computador do grupo na mesma rede (sala de aula, Wi-Fi público).

**Correção:**
- sem chave configurada, cada computador gera a sua na primeira execução, em `%LOCALAPPDATA%\JogaBonito`, fora do projeto (`SegredosLocais`);
- a API escuta só em `localhost`; o acesso pela rede é opcional (`iniciar-projeto.bat -Rede`, perfil "rede local" do Visual Studio).

**Arquivos:** `Infrastructure/Seguranca/ProtecaoDados.cs`, `Program.cs`, `appsettings*.json`.

### 2. Token no `localStorage`
**Risco:** qualquer script que rodasse na página (um XSS, uma extensão maliciosa) lia o token e o usava de outro lugar por 8 horas.

**Correção:** o site agora recebe a sessão num cookie:
- `HttpOnly`: o JavaScript não o enxerga;
- `SameSite=Strict`;
- `Secure` com o prefixo `__Host-` sob HTTPS.

O corpo do login não traz mais o token para o site. O `localStorage` guarda só nome, perfil e validade, para montar o menu. O app Flutter continua com `Authorization: Bearer` e o token no Keystore/Keychain.

**Arquivos:** `Infrastructure/Seguranca/CookieSessao.cs`, `Endpoints.cs`, `Javascript/api.js`. **Testes:** E2E 22.

### 3. Dados pessoais em texto aberto
**Risco:** um backup copiado, um login de leitura vazado ou uma consulta mal filtrada expunham o endereço de entrega dos clientes.

**Correção:** CEP, rua, número, complemento, bairro e telefone são gravados cifrados com **AES-256-GCM**, que dá sigilo e também detecta adulteração (prefixo `enc1:`, nonce aleatório por valor).
- A chave fica no Key Vault em produção (`Dados__ChaveCriptografia`), no `.env` no Docker e é gerada por computador em desenvolvimento.
- Dados antigos são cifrados automaticamente na inicialização (`MigradorCriptografia`).
- Cidade e UF continuam abertas para os relatórios por região.

Além da criptografia, o banco ganhou mascaramento dinâmico (**Dynamic Data Masking**) em e-mail e IP: quem consulta o banco sem a permissão `UNMASK` vê `mXXX@XXXX.com`. Só o usuário da aplicação recebe `UNMASK`.

**Arquivos:** `ProtecaoDados.cs`, `ProtecaoBanco.cs`, `PedidoRepositorio.cs`, `PrivacidadeRepositorio.cs`, `schema.sql` (versão 5), `seguranca*.sql`, `infra/main.bicep`. **Testes:** `ProtetorDadosTests`.

> **Guarde a chave de criptografia.** Sem ela os endereços cifrados não podem ser lidos. No Azure, o Key Vault tem proteção contra exclusão definitiva.

### 4. CSRF
Com sessão em cookie, outro site poderia tentar fazer o navegador do cliente enviar requisições. Há três barreiras:
1. `SameSite=Strict`;
2. toda escrita autenticada por cookie exige o cabeçalho `X-JB-Requisicao: 1`, que um formulário de outro site não consegue enviar e que um `fetch` de outro site só envia se o CORS liberar (não libera);
3. o cabeçalho `Origin`, quando presente, precisa ser a própria loja ou uma origem de `Cors:Origens`.

**Testes:** `CookieSessaoTests` e E2E 23.

### 5. Enumeração de contas pelo tempo do login
**Risco:** com e-mail inexistente a API respondia na hora; com e-mail existente gastava ~100 ms no BCrypt. Medindo o tempo, dava para descobrir quem é cliente.

**Correção:** e-mail inexistente também verifica a senha contra um hash fictício de mesmo custo.

**Arquivo:** `AuthServico.cs`.

### 6. Política de senha
**Correção:**
- de 8 a **72 bytes**, o limite real do BCrypt (acima disso o algoritmo ignorava o resto);
- recusa as senhas mais usadas no Brasil (`senha123`, `brasil2026`…) e senhas com 3 caracteres diferentes ou menos;
- recusa senha que contenha o nome do e-mail;
- frases são bem-vindas.

**Testes:** `DominioTests`, E2E 24.

### 7. Exposição de e-mail e IP no painel
**Correção:** a aba Acessos e o console de consultas mostram `ma*****@estudante.com` e `200.150.10.x`. A informação continua útil para investigar ataques, mas não serve para montar uma lista de clientes.

**Arquivo:** `AdminRepositorios.cs` (`Mascara`).

### 8. Health check falante
**Correção:** em produção, `/health/ready` responde só `{"status":"Healthy"}` para o público. Os nomes de objetos e as mensagens do SQL Server aparecem apenas para o admin logado ou em desenvolvimento.

### 9. Imagens de produto
**Correção:** o painel admin e a sincronização do catálogo só aceitam arquivos de `../IMG/` com extensão de imagem. URL externa, `javascript:`, `data:` e `../../` são recusados.

**Arquivos:** `CatalogoServico.ValidarImagem`, `SincronizadorCatalogoLocal`. **Testes:** `ImagemProdutoTests`.

### 10. Retenção do log de acessos (LGPD art. 15 e 16)
**Correção:** a procedure `sp_ExpurgarRegistrosAntigos` apaga tentativas de login com mais de 180 dias. Ela roda uma vez por dia (`RotinaRetencao`) e não aceita prazo menor que 30 dias.

### 11. Dependência vulnerável
**Correção:** `Microsoft.Data.SqlClient` foi de 5.1.5 para **5.1.6**, que traz `Azure.Identity` 1.11.4 (correção do CVE-2024-35255). As demais dependências (JwtBearer 8.0.2, BCrypt.Net-Next 4.0.3, Swashbuckle 6.5.0) não têm vulnerabilidade conhecida nessas versões.

### 14. Firewall do banco na nuvem
**Risco:** a regra `0.0.0.0` do Azure SQL não significa "só a nossa loja", e sim qualquer serviço dentro do Azure, de qualquer cliente. Com a senha de um usuário do banco, qualquer máquina virtual no Azure chegaria ao banco.

**Correção:**
- o Bicep cria regras só para os IPs de saída do App Service da loja (`infra/firewall-app.bicep`);
- o pipeline abre uma regra para o próprio IP apenas durante a migração e a apaga no fim, mesmo se der erro;
- `infra/conferir-azure.sh` falha se encontrar faixa aberta ou regra esquecida.

### 12 e 13. Cupom e cabeçalho do servidor
**Correção:** validação de cupom limitada a 20 por minuto por IP; `Server: Kestrel` removido das respostas.

## O que já estava protegido (verificado)

- **SQL Injection:**
  - todas as consultas são parametrizadas;
  - `ORDER BY` só aceita uma lista fechada;
  - `LIKE` escapa `%`, `_` e `[`;
  - o console admin executa só SQL fixo, escolhido por nome.
- **IDOR:** o dono do pedido vem do token, nunca do corpo. Pedido de outro cliente devolve 404, e o cancelamento confere o dono.
- **Mass assignment:** cada rota recebe um DTO próprio; perfil e preço nunca vêm do cliente.
- **XSS:**
  - todo texto vindo da API passa por `JB.esc()` antes de ir para o HTML;
  - a CSP proíbe scripts inline;
  - um teste E2E garante que nenhum arquivo usa `onclick`/`onerror`.
- **Força bruta:** 10 logins por minuto por IP e bloqueio da conta por 15 minutos depois de 5 senhas erradas, com log.
- **Sessão:** a versão do token é conferida no banco a cada requisição. Trocar a senha, "Sair de todos os aparelhos" ou excluir a conta derruba as sessões na hora.
- **Cartão:** número, validade e CVV nunca saem do navegador (o pagamento é simulado); nada disso chega à API ou ao banco.
- **Open redirect:** o parâmetro `volta` do login só aceita páginas `*.html` do próprio site.
- **Cabeçalhos:**
  - CSP, `nosniff`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy` e COOP;
  - `Cache-Control: no-store` em dados pessoais;
  - HSTS em produção;
  - respostas de `/api/auth` sem compressão sob HTTPS (BREACH).
- **Banco:** usuário `jogabonito_app` com privilégio mínimo. Em produção a API se recusa a conectar como `sa`, a usar chave JWT de exemplo e a subir sem chave de criptografia.
- **Segredos:** nenhum no repositório; Key Vault em produção, `.env` gerado por computador no Docker.
- **SSRF / upload / XXE:** não se aplicam; a API não busca URLs, não recebe arquivos e não lê XML.

## Riscos aceitos e próximos passos recomendados

| Risco | Por que foi aceito | Recomendação |
|---|---|---|
| O cadastro avisa "Este e-mail já está cadastrado" | Sem serviço de e-mail, é a única forma de o cliente saber que já tem conta | Confirmação por e-mail no cadastro; limite de 10/min já reduz a coleta em massa |
| Alguém pode travar a conta de outra pessoa por 15 min errando a senha 5 vezes | É o custo do bloqueio por conta | Bloqueio progressivo + CAPTCHA depois de 3 erros |
| CSP com `'unsafe-eval'` | Exigido pelo widget VLibras (acessibilidade em Libras) | Carregar o VLibras numa página isolada (iframe) quando o governo oferecer |
| E-mail não é cifrado | É a chave do login e precisa ser único | Coberto por mascaramento dinâmico, TDE (padrão no Azure SQL) e privilégio mínimo; alternativa futura: índice cego (HMAC) |
| IDs de pedido sequenciais | O acesso é protegido pelo dono; só revelam o volume de vendas | Código público aleatório para o pedido |
| Admin sem segundo fator | Fora do escopo do PIM | 2FA (TOTP) para o perfil Admin |

## Como verificar

```bash
dotnet test Site/tests/JogaBonito.Tests        # criptografia, máscaras, CSRF, imagens, senha, catálogo
python Site/tests/e2e/test_loja.py             # 26 testes, incluindo cookie HttpOnly, CSRF e senha comum
python3 Site/ferramentas/verificar_publicacao.py https://endereco-da-loja
```
