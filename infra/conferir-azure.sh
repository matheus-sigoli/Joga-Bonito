#!/usr/bin/env bash
# ============================================================================
# JOGA BONITO — conferência da produção no Azure (operação e segurança)
#
#   az login
#   bash infra/conferir-azure.sh rg-jogabonito
#
# Lê os nomes criados pelo Bicep (deployment "jogabonito") e confere:
#   App Service: rodando, HTTPS obrigatório, TLS 1.2, FTP desligado, health check, Always On
#   Configuração: Production, sem dados de demonstração, Swagger fechado, segredos só do Key Vault
#   Key Vault: identidade do App Service com acesso e todas as referências "Resolved"
#   Azure SQL: firewall sem "AllowAllWindowsAzureIps" nem faixas abertas, TLS 1.2, TDE ligada,
#              backups de curto e longo prazo
#   Monitoramento: Application Insights recebendo requisições, alertas ligados com e-mail
#   Site: /health/ready, contas de demonstração recusadas e verificar_publicacao.py
# Requer: Azure CLI, jq, curl e python3. Não altera nada.
# ============================================================================
set -uo pipefail
GRUPO="${1:?Uso: bash infra/conferir-azure.sh <grupo-de-recursos>}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
ok=0; falhas=0
passou() { echo "  [ok] $1"; ok=$((ok + 1)); }
falhou() { echo "  [FALHOU] $1${2:+ — $2}"; falhas=$((falhas + 1)); }
checar() { if [ "$2" = "true" ]; then passou "$1"; else falhou "$1" "${3:-}"; fi; }

saidas=$(az deployment group show -g "$GRUPO" -n jogabonito --query properties.outputs -o json) \
  || { echo "Deployment 'jogabonito' não encontrado em $GRUPO (rode infra/main.bicep com -n jogabonito)."; exit 2; }
val() { echo "$saidas" | jq -r ".$1.value"; }
APP=$(val nomeApp); SQL=$(val nomeServidorSql); BANCO=$(val nomeBanco); URL=$(val enderecoLoja); COFRE=$(val nomeCofre)
echo "Joga Bonito — produção: $URL (App $APP · SQL $SQL · Key Vault $COFRE)"

echo; echo "== App Service"
site=$(az webapp show -g "$GRUPO" -n "$APP" -o json)
cfg=$(az webapp config show -g "$GRUPO" -n "$APP" -o json)
checar "rodando" "$(jq -r '.state == "Running"' <<<"$site")" "$(jq -r .state <<<"$site")"
checar "HTTPS obrigatório" "$(jq -r '.httpsOnly' <<<"$site")"
checar "TLS mínimo 1.2" "$(jq -r '.minTlsVersion == "1.2"' <<<"$cfg")"
checar "FTP desligado" "$(jq -r '.ftpsState == "Disabled"' <<<"$cfg")"
checar "health check em /health/ready" "$(jq -r '.healthCheckPath == "/health/ready"' <<<"$cfg")"
checar "Always On" "$(jq -r '.alwaysOn' <<<"$cfg")"
checar "imagem do GHCR" "$(jq -r '.linuxFxVersion | startswith("DOCKER|ghcr.io/")' <<<"$cfg")" "$(jq -r .linuxFxVersion <<<"$cfg")"

echo; echo "== Configuração e segredos"
conf=$(az webapp config appsettings list -g "$GRUPO" -n "$APP" -o json)
v() { jq -r --arg n "$1" '.[] | select(.name == $n) | .value' <<<"$conf"; }
checar "ASPNETCORE_ENVIRONMENT=Production" "$([ "$(v ASPNETCORE_ENVIRONMENT)" = Production ] && echo true)"
checar "dados de demonstração desligados" "$([ "$(v Banco__CarregarDemonstracao)" = false ] && echo true)"
checar "Swagger fechado" "$([ "$(v Swagger__Habilitado)" != true ] && echo true)"
checar "HTTPS forçado na API" "$([ "$(v Seguranca__ForcarHttps)" = true ] && echo true)"
for s in Jwt__Chave Dados__ChaveCriptografia ConnectionStrings__DefaultConnection Banco__AdminSenha; do
  checar "$s vem do Key Vault (nada em texto no App Service)" "$([[ "$(v $s)" == @Microsoft.KeyVault* ]] && echo true)"
done
id=$(jq -r .id <<<"$site")
pendentes=$(az rest --method get --url "https://management.azure.com$id/config/configreferences/appsettings?api-version=2022-03-01" \
  --query "value[?properties.status!='Resolved'].name" -o tsv 2>/dev/null)
checar "referências do Key Vault resolvidas" "$([ -z "$pendentes" ] && echo true)" "$pendentes"
principal=$(jq -r .identity.principalId <<<"$site")
cofreId=$(az keyvault show -n "$COFRE" --query id -o tsv)
papel=$(az role assignment list --assignee "$principal" --scope "$cofreId" --query "[?roleDefinitionName=='Key Vault Secrets User'] | length(@)" -o tsv)
checar "App Service só lê segredos (Key Vault Secrets User)" "$([ "${papel:-0}" -ge 1 ] && echo true)"
checar "Key Vault com proteção contra exclusão" "$(az keyvault show -n "$COFRE" --query 'properties.enablePurgeProtection' -o tsv | tr A-Z a-z)"

echo; echo "== Azure SQL"
regras=$(az sql server firewall-rule list -g "$GRUPO" -s "$SQL" -o json)
checar "sem a regra AllowAllWindowsAzureIps (0.0.0.0)" "$(jq -r 'all(.[]; .startIpAddress != "0.0.0.0")' <<<"$regras")"
checar "nenhuma faixa de IPs aberta (só IPs únicos)" "$(jq -r 'all(.[]; .startIpAddress == .endIpAddress)' <<<"$regras")" \
  "$(jq -r '[.[] | select(.startIpAddress != .endIpAddress) | .name] | join(", ")' <<<"$regras")"
checar "sem regra temporária esquecida pelo pipeline" "$(jq -r 'all(.[]; (.name | startswith("pipeline-")) | not)' <<<"$regras")"
checar "TLS mínimo 1.2" "$(az sql server show -g "$GRUPO" -n "$SQL" --query "minimalTlsVersion=='1.2'" -o tsv | tr A-Z a-z)"
checar "criptografia em repouso (TDE) ligada" "$(az sql db tde show -g "$GRUPO" -s "$SQL" -d "$BANCO" --query "state=='Enabled'" -o tsv | tr A-Z a-z)"
curto=$(az sql db str-policy show -g "$GRUPO" -s "$SQL" -n "$BANCO" --query retentionDays -o tsv)
checar "backup de curto prazo ≥ 7 dias" "$([ "${curto:-0}" -ge 7 ] && echo true)" "$curto dias"
longo=$(az sql db ltr-policy show -g "$GRUPO" -s "$SQL" -n "$BANCO" --query weeklyRetention -o tsv)
checar "backup semanal de longo prazo" "$([ -n "$longo" ] && [ "$longo" != PT0S ] && echo true)" "$longo"

echo; echo "== Monitoramento"
alertas=$(az monitor metrics alert list -g "$GRUPO" --query "[?enabled] | length(@)" -o tsv)
checar "alertas ligados (5xx, lentidão, CPU do banco)" "$([ "${alertas:-0}" -ge 3 ] && echo true)" "$alertas ativos"
emails=$(az monitor action-group list -g "$GRUPO" --query "[].emailReceivers[].emailAddress" -o tsv)
checar "alertas enviam e-mail" "$([ -n "$emails" ] && echo true)" "$emails"
appi=$(az resource list -g "$GRUPO" --resource-type microsoft.insights/components --query "[0].name" -o tsv)
req=$(az monitor app-insights query -g "$GRUPO" --app "$appi" --analytics-query "requests | where timestamp > ago(24h) | count" \
  --query "tables[0].rows[0][0]" -o tsv 2>/dev/null)
checar "Application Insights recebendo requisições (24 h)" "$([ "${req:-0}" -gt 0 ] && echo true)" "${req:-sem dados} (acesse a loja e rode de novo)"

echo; echo "== Site publicado"
corpo=$(curl -fsS "$URL/health/ready" || true); [ -n "$corpo" ] || corpo='{}'
checar "/health/ready saudável" "$(jq -r '.status == "Healthy"' <<<"$corpo" 2>/dev/null)" "$corpo"
checar "/health/ready não expõe a infraestrutura ao público" "$(jq -r 'has("componentes") | not' <<<"$corpo" 2>/dev/null)"
for conta in "admin@jogabonito.com:Admin@2026" "matheus@estudante.com:Cliente@2026" "professor@unip.br:Unip@2026"; do
  st=$(curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" \
       -d "{\"email\":\"${conta%%:*}\",\"senha\":\"${conta#*:}\"}" "$URL/api/auth/login")
  checar "conta de demonstração ${conta%%:*} não entra" "$([ "$st" = 401 ] || [ "$st" = 429 ] && echo true)" "HTTP $st"
done
python3 "$RAIZ/Site/ferramentas/verificar_publicacao.py" "$URL" && passou "verificar_publicacao.py" || falhou "verificar_publicacao.py"

echo; echo "======================================================================"
echo "$ok verificações OK · $falhas falharam"
[ "$falhas" -eq 0 ]
