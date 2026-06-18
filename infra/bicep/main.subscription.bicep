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

@secure()
@description('Service token signing key. Store this only in deployment secrets or Key Vault.')
param serviceTokenSigningKey string

@description('Bundle identifier expected in App Store subscription transactions.')
param appStoreBundleId string = 'dev.ericslutz.PumpSync'

@description('App Store transaction environment expected by this backend.')
@allowed([
  'Sandbox'
  'Production'
])
param appStoreEnvironment string = environmentName == 'prod' ? 'Production' : 'Sandbox'

@description('Auto-renewable subscription product id used for PumpSync Hosted.')
param appStoreSubscriptionProductId string = 'dev.ericslutz.PumpSync.hosted.monthly'

@description('App Store Server API issuer id.')
param appStoreIssuerId string = ''

@description('App Store Server API key id.')
param appStoreKeyId string = ''

@secure()
@description('App Store Server API private key.')
param appStorePrivateKey string = ''

@description('PEM-encoded Apple root certificate used to pin App Store signed payload verification.')
param appStoreRootCertificatePem string = ''

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
    serviceTokenSigningKey: serviceTokenSigningKey
    appStoreBundleId: appStoreBundleId
    appStoreEnvironment: appStoreEnvironment
    appStoreSubscriptionProductId: appStoreSubscriptionProductId
    appStoreIssuerId: appStoreIssuerId
    appStoreKeyId: appStoreKeyId
    appStorePrivateKey: appStorePrivateKey
    appStoreRootCertificatePem: appStoreRootCertificatePem
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
output subscriptionEntitlementsTableName string = backend.outputs.subscriptionEntitlementsTableName
output installationsTableName string = backend.outputs.installationsTableName
output syncAttemptsTableName string = backend.outputs.syncAttemptsTableName
