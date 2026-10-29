# Implantação no Azure e validação completa

Roteiro para publicar a Joga Bonito e provar que tudo funciona. Os comandos são para **Azure Cloud Shell** (bash) ou um terminal com Azure CLI; os de teste, para o Windows do grupo.

## 0. Antes de começar

- Assinatura do Azure (a *Azure for Students* serve). Se a política da assinatura bloquear `brazilsouth`, use `-l eastus` no passo 1.
- Repositório no GitHub com o projeto (hoje `matheus-sigoli/Joga-Bonito` tem só o README — veja o passo 3).
- Guarde num gerenciador de senhas os valores gerados no passo 1. **A `chaveDados` não pode mudar nem se perder**: os endereços dos clientes são cifrados com ela.

## 1. Criar a infraestrutura (uma vez)

```bash
GRUPO=rg-jogabonito
az group create -n $GRUPO -l brazilsouth

SQL_ADMIN_SENHA='<forte, 12+ caracteres>'     # conta administradora do SQL (só a migração usa)
SENHA_APP='<forte, 12+ caracteres>'           # usuário jogabonito_app (a API usa)
JWT=$(openssl rand -base64 48)
DADOS=$(openssl rand -base64 32)               # GUARDE: chave dos endereços cifrados
ADMIN_SENHA='<senha do primeiro admin da loja>'

az deployment group create -g $GRUPO -n jogabonito -f infra/main.bicep -p \
  sqlAdminSenha="$SQL_ADMIN_SENHA" senhaApp="$SENHA_APP" jwtChave="$JWT" chaveDados="$DADOS" \
  adminSenhaInicial="$ADMIN_SENHA" emailAlertas=<email-do-grupo>
```

O nome do deployment precisa ser **`jogabonito`** (`-n jogabonito`): é dele que o pipeline lê o nome do App Service, do servidor SQL e o endereço da loja. Nada fica fixo no workflow.

Ao rodar o Bicep de novo, use **os mesmos** `jwtChave` e `chaveDados`. Trocar a `chaveDados` torna ilegíveis os endereços já gravados.

**Imagem privada no GHCR?** Ou torne o pacote público (GitHub › Packages › `jogabonito-api` › *Package settings* › *Change visibility*), ou acrescente `ghcrUsuario=matheus-sigoli ghcrToken=<token com read:packages>` ao comando acima. O token vai para o Key Vault. O pipeline confere isso antes de implantar e explica o que falta.

**Firewall do banco:** o Bicep libera só os IPs de saída do App Service. O pipeline abre uma regra temporária para o próprio IP durante a migração e a apaga no fim, mesmo se der erro.

## 2. Dar ao GitHub acesso ao Azure (OIDC, sem senha guardada)

```bash
APP_ID=$(az ad app create --display-name jogabonito-github --query appId -o tsv)
az ad sp create --id $APP_ID
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "github-producao",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:matheus-sigoli/Joga-Bonito:environment:producao",
  "audiences": ["api://AzureADTokenExchange"] }'
az role assignment create --assignee $APP_ID --role Contributor --scope $(az group show -n $GRUPO --query id -o tsv)

echo "AZURE_CLIENT_ID=$APP_ID"
echo "AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)"
```

No GitHub: *Settings › Environments › New environment* `producao`.

| Tipo | Nome | Valor |
|---|---|---|
| Variável | `AZURE_RESOURCE_GROUP` | `rg-jogabonito` |
| Variável | `URL_LOJA` | `https://<app>.azurewebsites.net` (saída `enderecoLoja`; o APK usa) |
| Variável | `DEPLOY_OBRIGATORIO` | `true` (o pipeline falha se faltar configuração) |
| Segredo | `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` | do bloco acima |
| Segredo | `AZURE_SQL_ADMIN` | `jbadmin` |
| Segredo | `AZURE_SQL_ADMIN_SENHA` | `$SQL_ADMIN_SENHA` |
| Segredo | `AZURE_SQL_SENHA_APP` | `$SENHA_APP` (a mesma do Bicep) |

`URL_LOJA` também precisa existir como variável do repositório (*Settings › Secrets and variables › Actions › Variables*), porque o job do app não usa o ambiente `producao`.

## 3. Publicar o código e rodar o pipeline

```bash
git clone https://github.com/matheus-sigoli/Joga-Bonito.git && cd Joga-Bonito
# copie para cá o conteúdo da pasta PIM (README do projeto substitui o atual)
git add . && git commit -m "Joga Bonito: projeto completo"
git push origin main
```

Cada push na `main` dispara, em ordem:
1. **Testes, todos obrigatórios:** unitários .NET; integração com API real + SQL Server 2022; **roteiro de aceitação de 75 verificações contra a API real** seguido do `conferencia.sql` no banco; 26 testes E2E Playwright; `flutter analyze`, `flutter test` e APK apontando para `URL_LOJA`.
2. **Imagem Docker** no GHCR.
3. **Deploy:**
   - login OIDC e leitura das saídas do Bicep;
   - conferência do acesso à imagem;
   - firewall temporário e migração do banco (`schema.sql`, `seed.sql` e `seguranca-azure.sql`, com o usuário de privilégio mínimo);
   - implantação da imagem e conferência das referências do Key Vault;
   - `/health/ready` e `verificar_publicacao.py`.

Pull requests para a `main` rodam só os testes.

## 4. Validar

| Item | Como validar | Onde |
|---|---|---|
| Testes automatizados | `testar-tudo.bat` (unitários, integração com o SQL local, E2E, aceitação, Flutter) — ou o próprio pipeline | Windows / GitHub Actions |
| Fluxo completo de compra | `python Site/tests/aceitacao/validar_loja.py http://localhost:5000` (75 verificações) | Windows |
| O mesmo em produção | `python Site/tests/aceitacao/validar_loja.py https://<loja> --admin-email <admin> --admin-senha <senha> --confirmo-producao` | qualquer PC |
| Dados corretos no banco | `Site/banco/conferencia.sql` no SSMS / Azure Data Studio (23 regras: totais, frete, Joga Junto, estoque × auditoria, cancelamentos, moderação, criptografia, LGPD) | SSMS |
| Funções administrativas | seções "Permissões e painel" e "Avaliações e moderação" do `validar_loja.py` + roteiro manual 2 | — |
| App em aparelho real | `Mobile/README.md` (endereço por ambiente) + roteiro manual 1 | Android |
| Pedido do app aparece no site | roteiro manual 3 | Android + navegador |
| Joga Junto, LGPD e acessibilidade | `validar_loja.py` (cálculo, exportar, excluir) + roteiros manuais 1, 2 e 5 | — |
| Segurança e operação em produção | `bash infra/conferir-azure.sh rg-jogabonito` (App Service, Key Vault, firewall, TDE, backups, alertas, App Insights, contas de demonstração) | Cloud Shell |

Os roteiros manuais estão em `Maestro/docs/qa/roteiros-manuais.md`.

**Validar em produção cria dados de teste:** dois clientes, pedidos e um produto. No fim, o script cancela os pedidos (o estoque volta), desativa o produto e exclui as contas (LGPD). Ficam pedidos cancelados de "Cliente removido".

## 5. Problemas comuns

| Sintoma | Causa provável |
|---|---|
| Pipeline: "Deployment 'jogabonito' não encontrado" | O Bicep rodou sem `-n jogabonito` ou em outro grupo |
| Pipeline: "imagem é privada e o App Service não tem credencial" | Torne o pacote público ou passe `ghcrUsuario`/`ghcrToken` ao Bicep |
| Pipeline: referências do Key Vault "não resolvidas" | A atribuição do papel ainda está propagando (rode de novo em 5 min) ou o papel "Key Vault Secrets User" foi removido |
| `/health/ready` 503 depois do deploy | Migração não rodou (veja o passo "Migrar banco") ou a senha do `jogabonito_app` difere entre o Key Vault e o segredo do GitHub |
| A API não sobe: "Dados:ChaveCriptografia não configurada" | Falta a `chaveDados` no Bicep |
| Login do admin falha em produção | O admin inicial só é criado se `adminSenhaInicial` atender à política (8+ caracteres, letras e números, fora da lista de senhas comuns) |
