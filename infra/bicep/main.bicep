targetScope = 'subscription'

@description('Deployment location.')
param location string

@description('Short environment name, for example nonprod or prod.')
param environmentName string

@description('Application prefix used for resource names.')
param appName string = 'pumpsync'

@description('Apple Services ID or bundle identifier expected in Sign in with Apple tokens.')
param appleClientId string

@description('Azure SQL administrator login. This is used for provisioning; prefer managed identity for app runtime when DB users are configured.')
param sqlAdministratorLogin string = 'pumpsyncadmin'

@secure()
@description('Azure SQL administrator password.')
param sqlAdministratorPassword string

@secure()
@description('Service token signing key. Store this as a deployment secret.')
param serviceTokenSigningKey string

@description('CIDR ranges allowed to reach SQL. Leave empty to rely on private networking added later.')
param allowedSqlCidrs array = []

var suffix = uniqueString(subscription().id, environmentName, appName)
var resourceGroupName = 'rg-${appName}-${environmentName}'
var functionAppName = 'func-${appName}-${environmentName}-${suffix}'
var appServicePlanName = 'asp-${appName}-${environmentName}-${suffix}'
var storageName = take(replace('st${appName}${environmentName}${suffix}', '-', ''), 24)
var sqlServerName = 'sql-${appName}-${environmentName}-${suffix}'
var sqlDatabaseName = 'sqldb-${appName}-${environmentName}'
var appInsightsName = 'appi-${appName}-${environmentName}-${suffix}'
var logWorkspaceName = 'log-${appName}-${environmentName}-${suffix}'
var keyVaultName = take('kv-${appName}-${environmentName}-${suffix}', 24)

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module resources 'resources.bicep' = {
  name: 'pumpsync-${environmentName}-resources'
  scope: rg
  params: {
    location: location
    environmentName: environmentName
    functionAppName: functionAppName
    appServicePlanName: appServicePlanName
    storageName: storageName
    sqlServerName: sqlServerName
    sqlDatabaseName: sqlDatabaseName
    appInsightsName: appInsightsName
    logWorkspaceName: logWorkspaceName
    keyVaultName: keyVaultName
    appleClientId: appleClientId
    sqlAdministratorLogin: sqlAdministratorLogin
    sqlAdministratorPassword: sqlAdministratorPassword
    serviceTokenSigningKey: serviceTokenSigningKey
    allowedSqlCidrs: allowedSqlCidrs
  }
}

output resourceGroupName string = rg.name
output functionAppName string = resources.outputs.functionAppName
output sqlServerName string = resources.outputs.sqlServerName
output sqlDatabaseName string = resources.outputs.sqlDatabaseName
output keyVaultName string = resources.outputs.keyVaultName
