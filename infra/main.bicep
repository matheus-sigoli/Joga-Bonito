// ============================================================================
// JOGA BONITO — infraestrutura no Azure como código (Bicep)
// PIM IV · UNIP 2026/2
//
// Cria, num grupo de recursos:
//   * App Service (Linux, container) com identidade gerenciada, HTTPS obrigatório,
//     health check em /health/ready e autoescala de 1 a 4 instâncias;
//   * Azure SQL Database (serverless) com firewall só para os IPs de saída do App Service,
//     backups de curto (7 dias) e longo prazo (4 semanas);
//   * Key Vault com os segredos (chave JWT, conexão do banco, senha do admin inicial),
//     lidos pelo App Service via identidade gerenciada — nenhum segredo no código;
//   * Log Analytics + Application Insights e alertas (erros 5xx, lentidão, CPU do banco).
//
// Uso (Azure CLI):
//   az group create -n rg-jogabonito -l brazilsouth
//   az deployment group create -g rg-jogabonito -n jogabonito -f infra/main.bicep \
//      -p sqlAdminSenha=... senhaApp=... jwtChave=... chaveDados=$(openssl rand -base64 32) adminSenhaInicial=... emailAlertas=...
// Depois do primeiro deploy, o pipeline (job deploy) roda schema.sql, seed.sql e
// seguranca-azure.sql no banco e publica a imagem do container.
// ============================================================================

@description('Prefixo dos nomes dos recursos (minúsculas, sem espaços).')
param nome string = 'jogabonito'

param local string = resourceGroup().location

@description('Imagem do container publicada pelo pipeline no GitHub Container Registry.')
param imagem string = 'ghcr.io/matheus-sigoli/jogabonito-api:latest'

param sqlAdminLogin string = 'jbadmin'

@secure()
@description('Senha do administrador do servidor SQL (usada só pelo pipeline para rodar os scripts).')
param sqlAdminSenha string

@secure()
@description('Senha do usuário jogabonito_app (privilégio mínimo) usado pela API.')
param senhaApp string

@secure()
@minLength(32)
param jwtChave string

@secure()
@minLength(44)
@description('Chave AES-256 (Base64 de 32 bytes) dos dados pessoais cifrados no banco. Gere com: openssl rand -base64 32. Perdê-la torna os endereços ilegíveis.')
param chaveDados string

param adminEmailInicial string = 'admin@jogabonito.com.br'

@secure()
param adminSenhaInicial string

@description('E-mail que recebe os alertas de monitoramento.')
param emailAlertas string

@description('Usuário do GitHub dono da imagem. Só é preciso se o pacote no GHCR for PRIVADO.')
param ghcrUsuario string = ''

@secure()
@description('Token do GitHub com permissão read:packages. Só é preciso se o pacote no GHCR for PRIVADO.')
param ghcrToken string = ''

var sufixo = uniqueString(resourceGroup().id)
var nomeBanco = 'JogaBonitoDB'

// ------------------------------------------------------------- Monitoramento
resource logs 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${nome}-logs-${sufixo}'
  location: local
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${nome}-insights'
  location: local
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

// ---------------------------------------------------------------- Banco SQL
resource sqlServer 'Microsoft.Sql/servers@2021-11-01' = {
  name: '${nome}-sql-${sufixo}'
  location: local
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminSenha
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// Firewall: só os IPs de saída do App Service (módulo firewall-app.bicep, no fim do arquivo).
// O pipeline abre uma regra temporária para o próprio IP durante a migração e a apaga em seguida.

resource banco 'Microsoft.Sql/servers/databases@2021-11-01' = {
  parent: sqlServer
  name: nomeBanco
  location: local
  sku: {
    name: 'GP_S_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  properties: {
    autoPauseDelay: 60
    minCapacity: json('0.5')
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    requestedBackupStorageRedundancy: 'Local'
  }
}

resource backupCurto 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2021-11-01' = {
  parent: banco
  name: 'default'
  properties: {
    retentionDays: 7
  }
}

resource backupLongo 'Microsoft.Sql/servers/databases/backupLongTermRetentionPolicies@2021-11-01' = {
  parent: banco
  name: 'default'
  properties: {
    weeklyRetention: 'P4W'
  }
}

// --------------------------------------------------------------- Key Vault
resource cofre 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: take('${nome}-kv-${sufixo}', 24)
  location: local
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true      // a chave dos dados pessoais não pode ser apagada de vez por engano
  }
}

resource segredoJwt 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: cofre
  name: 'JwtChave'
  properties: { value: jwtChave }
}

resource segredoDados 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: cofre
  name: 'ChaveDados'
  properties: { value: chaveDados }
}

resource segredoGhcr 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(ghcrToken)) {
  parent: cofre
  name: 'GhcrToken'
  properties: { value: ghcrToken }
}

resource segredoConexao 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: cofre
  name: 'ConexaoBanco'
  properties: {
    value: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${nomeBanco};User Id=jogabonito_app;Password=${senhaApp};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
  }
}

resource segredoSenhaApp 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: cofre
  name: 'SenhaApp'
  properties: { value: senhaApp }
}

resource segredoAdmin 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: cofre
  name: 'AdminSenhaInicial'
  properties: { value: adminSenhaInicial }
}

// -------------------------------------------------------------- App Service
resource plano 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${nome}-plano'
  location: local
  kind: 'linux'
  sku: {
    name: 'S1'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    reserved: true
  }
}

resource site 'Microsoft.Web/sites@2023-01-01' = {
  name: '${nome}-api-${sufixo}'
  location: local
  kind: 'app,linux,container'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plano.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|${imagem}'
      alwaysOn: true
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      healthCheckPath: '/health/ready'
      appSettings: concat(empty(ghcrToken) ? [] : [
        // Pacote privado no GHCR: o App Service baixa a imagem com este usuário/token
        { name: 'DOCKER_REGISTRY_SERVER_USERNAME', value: ghcrUsuario }
        { name: 'DOCKER_REGISTRY_SERVER_PASSWORD', value: '@Microsoft.KeyVault(SecretUri=${segredoGhcr.properties.secretUri})' }
      ], [
        { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
        { name: 'WEBSITES_PORT', value: '5000' }
        { name: 'DOCKER_REGISTRY_SERVER_URL', value: 'https://ghcr.io' }
        { name: 'Jwt__Chave', value: '@Microsoft.KeyVault(SecretUri=${segredoJwt.properties.secretUri})' }
        { name: 'Dados__ChaveCriptografia', value: '@Microsoft.KeyVault(SecretUri=${segredoDados.properties.secretUri})' }
        { name: 'ConnectionStrings__DefaultConnection', value: '@Microsoft.KeyVault(SecretUri=${segredoConexao.properties.secretUri})' }
        { name: 'Banco__CriarAutomaticamente', value: 'false' }
        { name: 'Banco__CarregarDemonstracao', value: 'false' }
        { name: 'Banco__AdminEmail', value: adminEmailInicial }
        { name: 'Banco__AdminSenha', value: '@Microsoft.KeyVault(SecretUri=${segredoAdmin.properties.secretUri})' }
        { name: 'Seguranca__ForcarHttps', value: 'true' }
        { name: 'Seguranca__ConfiarProxy', value: 'true' }
        { name: 'Swagger__Habilitado', value: 'false' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: insights.properties.ConnectionString }
      ])
    }
  }
}

// O App Service lê os segredos com a própria identidade (papel "Key Vault Secrets User")
resource leituraSegredos 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cofre.id, site.id, 'kv-secrets-user')
  scope: cofre
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: site.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// --------------------------------------------------- Autoescala (1 a 4 instâncias)
resource autoescala 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: '${nome}-autoescala'
  location: local
  properties: {
    enabled: true
    targetResourceUri: plano.id
    profiles: [
      {
        name: 'cpu'
        capacity: { minimum: '1', maximum: '4', default: '1' }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: plano.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: { direction: 'Increase', type: 'ChangeCount', value: '1', cooldown: 'PT10M' }
          }
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: plano.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT20M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
            }
            scaleAction: { direction: 'Decrease', type: 'ChangeCount', value: '1', cooldown: 'PT20M' }
          }
        ]
      }
    ]
  }
}

// ------------------------------------------------------------------- Alertas
resource avisos 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${nome}-avisos'
  location: 'global'
  properties: {
    groupShortName: 'jogabonito'
    enabled: true
    emailReceivers: [
      { name: 'equipe', emailAddress: emailAlertas, useCommonAlertSchema: true }
    ]
  }
}

resource alertaErros 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${nome}-erros-5xx'
  location: 'global'
  properties: {
    description: 'Mais de 10 respostas 5xx em 5 minutos'
    severity: 1
    enabled: true
    scopes: [ site.id ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http5xx'
          criterionType: 'StaticThresholdCriterion'
          metricName: 'Http5xx'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Total'
        }
      ]
    }
    actions: [ { actionGroupId: avisos.id } ]
  }
}

resource alertaLentidao 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${nome}-lentidao'
  location: 'global'
  properties: {
    description: 'Tempo médio de resposta acima de 1,5 s'
    severity: 2
    enabled: true
    scopes: [ site.id ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'TempoResposta'
          criterionType: 'StaticThresholdCriterion'
          metricName: 'HttpResponseTime'
          operator: 'GreaterThan'
          threshold: json('1.5')
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [ { actionGroupId: avisos.id } ]
  }
}

resource alertaBanco 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${nome}-cpu-banco'
  location: 'global'
  properties: {
    description: 'CPU do Azure SQL acima de 80%'
    severity: 2
    enabled: true
    scopes: [ banco.id ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CpuBanco'
          criterionType: 'StaticThresholdCriterion'
          metricName: 'cpu_percent'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [ { actionGroupId: avisos.id } ]
  }
}

// ------------------------------------------------------------------- Saídas
module firewallApp 'firewall-app.bicep' = {
  name: 'firewall-sql-app'
  params: {
    servidorSql: sqlServer.name
    ipsSaida: site.properties.possibleOutboundIpAddresses
  }
}

output enderecoLoja string = 'https://${site.properties.defaultHostName}'
output nomeApp string = site.name
output servidorSql string = sqlServer.properties.fullyQualifiedDomainName
output nomeCofre string = cofre.name
output nomeServidorSql string = sqlServer.name
output nomeBanco string = nomeBanco
