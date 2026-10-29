// ============================================================================
// Regras de firewall do Azure SQL só para os IPs de saída do App Service da loja.
// Substitui a regra "AllowAllWindowsAzureIps" (0.0.0.0), que liberava o banco para
// QUALQUER serviço hospedado no Azure, inclusive de outros clientes.
// É um módulo porque os IPs só são conhecidos depois que o App Service existe.
// ============================================================================
param servidorSql string

@description('possibleOutboundIpAddresses do App Service (lista separada por vírgulas).')
param ipsSaida string

resource servidor 'Microsoft.Sql/servers@2021-11-01' existing = {
  name: servidorSql
}

resource regras 'Microsoft.Sql/servers/firewallRules@2021-11-01' = [for ip in union(split(ipsSaida, ','), []): {
  parent: servidor
  name: 'app-${replace(ip, '.', '-')}'
  properties: {
    startIpAddress: ip
    endIpAddress: ip
  }
}]
