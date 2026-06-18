targetScope = 'subscription'

@description('PumpSync environment to deploy.')
@allowed([
  'nonprod'
  'prod'
])
param environmentName string = 'nonprod'

@description('Azure region for the resource group and contained resources.')
param location string = 'eastus2'

@description('Application prefix used for resource names and tags.')
@minLength(1)
@maxLength(12)
param appName string = 'pumpsync'

@description('Resource group that will contain the PumpSync backend resources.')
param resourceGroupName string = 'rg-${appName}-${environmentName}'

@description('Apple Services ID or bundle identifier expected in Sign in with Apple tokens.')
param appleClientId string

@description('Existing Azure SQL server FQDN used for PumpSync user, auth, billing, idempotency, and sync state tables.')
param sqlServer string

@description('Existing Azure SQL database name used for PumpSync user, auth, billing, idempotency, and sync state tables.')
param sqlDatabase string

@secure()
@description('Service token signing key. Store this only in deployment secrets or Key Vault.')
param serviceTokenSigningKey string

@secure()
@description('Shared secret accepted by the standalone log-drain Function App.')
param logDrainSharedSecret string = ''

@description('NCRONTAB schedule for the model cost updater Azure Function.')
param modelCostUpdaterSchedule string = '0 0 4 * * *'

@description('Optional model cost catalog URL. The updater is inert when unset.')
param modelCostUpdaterCatalogUrl string = ''

@description('Tags applied to all resources.')
param tags object = {
  app: appName
  environment: environmentName
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module backend './main.bicep' = {
  name: '${appName}-${environmentName}-backend'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    location: location
    appName: appName
    appleClientId: appleClientId
    sqlServer: sqlServer
    sqlDatabase: sqlDatabase
    serviceTokenSigningKey: serviceTokenSigningKey
    logDrainSharedSecret: logDrainSharedSecret
    modelCostUpdaterSchedule: modelCostUpdaterSchedule
    modelCostUpdaterCatalogUrl: modelCostUpdaterCatalogUrl
    tags: tags
  }
}

output resourceGroupName string = resourceGroup.name
output backendFunctionAppName string = backend.outputs.backendFunctionAppName
output logDrainFunctionAppName string = backend.outputs.logDrainFunctionAppName
output modelCostUpdaterFunctionAppName string = backend.outputs.modelCostUpdaterFunctionAppName
output backendManagedIdentityName string = backend.outputs.backendManagedIdentityName
output backendManagedIdentityClientId string = backend.outputs.backendManagedIdentityClientId
output backendManagedIdentityPrincipalId string = backend.outputs.backendManagedIdentityPrincipalId
output storageAccountName string = backend.outputs.storageAccountName
output keyVaultName string = backend.outputs.keyVaultName
output keyVaultUri string = backend.outputs.keyVaultUri
output applicationInsightsName string = backend.outputs.applicationInsightsName
output logWorkspaceName string = backend.outputs.logWorkspaceName
output sqlServer string = backend.outputs.sqlServer
output sqlDatabase string = backend.outputs.sqlDatabase
output tandemSyncOperationsTableName string = backend.outputs.tandemSyncOperationsTableName
