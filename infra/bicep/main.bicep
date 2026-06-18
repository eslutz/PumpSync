targetScope = 'resourceGroup'

@description('Short environment name used in resource names.')
@allowed([
  'nonprod'
  'prod'
])
param environmentName string = 'nonprod'

@description('Azure region for resources in this resource group.')
param location string = resourceGroup().location

@description('Application prefix used for resource names and tags.')
@minLength(1)
@maxLength(12)
param appName string = 'pumpsync'

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

var nameSeed = toLower(uniqueString(subscription().subscriptionId, resourceGroup().id, environmentName, appName))
var prefix = '${appName}-${environmentName}-${take(nameSeed, 8)}'
var storageAccountName = take('st${appName}${environmentName}${nameSeed}', 24)
var logWorkspaceName = 'log-${prefix}'
var appInsightsName = 'appi-${prefix}'
var keyVaultName = take('kv-${appName}-${environmentName}-${nameSeed}', 24)
var backendFunctionAppName = take('func-${appName}-${environmentName}-flex-api', 60)
var logDrainFunctionAppName = take('func-${appName}-${environmentName}-flex-log', 60)
var modelCostUpdaterFunctionAppName = take('func-${appName}-${environmentName}-flex-cost', 60)
var backendIdentityName = '${prefix}-backend-id'
var logDrainIdentityName = '${prefix}-log-drain-id'
var modelCostUpdaterIdentityName = '${prefix}-cost-updater-id'
var subscriptionEntitlementsTableName = 'SubscriptionEntitlements'
var installationsTableName = 'Installations'
var installationLookupTableName = 'InstallationLookup'
var syncAttemptsTableName = 'SyncAttempts'
var rateLimitBucketsTableName = 'RateLimitBuckets'
var appStoreNotificationIdempotencyTableName = 'AppleNotificationIdempotency'
var auditEventsTableName = 'AuditEvents'
var backendPackageContainerName = 'function-packages-backend'
var logDrainPackageContainerName = 'function-packages-log-drain'
var modelCostUpdaterPackageContainerName = 'function-packages-model-cost'

var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageQueueDataContributorRoleId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: environmentName == 'prod' ? 90 : 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logWorkspace.id
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource backendPackageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: backendPackageContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource logDrainPackageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: logDrainPackageContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource modelCostUpdaterPackageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: modelCostUpdaterPackageContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource subscriptionEntitlementsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: subscriptionEntitlementsTableName
}

resource installationsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: installationsTableName
}

resource installationLookupTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: installationLookupTableName
}

resource syncAttemptsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: syncAttemptsTableName
}

resource rateLimitBucketsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: rateLimitBucketsTableName
}

resource appStoreNotificationIdempotencyTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: appStoreNotificationIdempotencyTableName
}

resource auditEventsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: auditEventsTableName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: []
    ...(environmentName == 'prod' ? {
      enablePurgeProtection: true
    } : {})
  }
}

resource backendIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: backendIdentityName
  location: location
  tags: tags
}

resource logDrainIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: logDrainIdentityName
  location: location
  tags: tags
}

resource modelCostUpdaterIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: modelCostUpdaterIdentityName
  location: location
  tags: tags
}

resource serviceTokenSigningKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'PumpSync--ServiceTokenSigningKey'
  properties: {
    value: serviceTokenSigningKey
  }
}

resource appStorePrivateKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'AppStore--PrivateKey'
  properties: {
    value: appStorePrivateKey
  }
}

resource logDrainSharedSecretSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'LogDrain--SharedSecret'
  properties: {
    value: logDrainSharedSecret
  }
}

var backendStorageSettings = [
  {
    name: 'AzureWebJobsStorage__accountName'
    value: storage.name
  }
  {
    name: 'AzureWebJobsStorage__blobServiceUri'
    value: storage.properties.primaryEndpoints.blob
  }
  {
    name: 'AzureWebJobsStorage__queueServiceUri'
    value: storage.properties.primaryEndpoints.queue
  }
  {
    name: 'AzureWebJobsStorage__tableServiceUri'
    value: storage.properties.primaryEndpoints.table
  }
  {
    name: 'AzureWebJobsStorage__credential'
    value: 'managedidentity'
  }
  {
    name: 'AzureWebJobsStorage__clientId'
    value: backendIdentity.properties.clientId
  }
  {
    name: 'AZURE_CLIENT_ID'
    value: backendIdentity.properties.clientId
  }
]

var logDrainStorageSettings = [
  {
    name: 'AzureWebJobsStorage__accountName'
    value: storage.name
  }
  {
    name: 'AzureWebJobsStorage__blobServiceUri'
    value: storage.properties.primaryEndpoints.blob
  }
  {
    name: 'AzureWebJobsStorage__queueServiceUri'
    value: storage.properties.primaryEndpoints.queue
  }
  {
    name: 'AzureWebJobsStorage__tableServiceUri'
    value: storage.properties.primaryEndpoints.table
  }
  {
    name: 'AzureWebJobsStorage__credential'
    value: 'managedidentity'
  }
  {
    name: 'AzureWebJobsStorage__clientId'
    value: logDrainIdentity.properties.clientId
  }
  {
    name: 'AZURE_CLIENT_ID'
    value: logDrainIdentity.properties.clientId
  }
]

var modelCostUpdaterStorageSettings = [
  {
    name: 'AzureWebJobsStorage__accountName'
    value: storage.name
  }
  {
    name: 'AzureWebJobsStorage__blobServiceUri'
    value: storage.properties.primaryEndpoints.blob
  }
  {
    name: 'AzureWebJobsStorage__queueServiceUri'
    value: storage.properties.primaryEndpoints.queue
  }
  {
    name: 'AzureWebJobsStorage__tableServiceUri'
    value: storage.properties.primaryEndpoints.table
  }
  {
    name: 'AzureWebJobsStorage__credential'
    value: 'managedidentity'
  }
  {
    name: 'AzureWebJobsStorage__clientId'
    value: modelCostUpdaterIdentity.properties.clientId
  }
  {
    name: 'AZURE_CLIENT_ID'
    value: modelCostUpdaterIdentity.properties.clientId
  }
]

resource backendFunctionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: backendFunctionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${backendIdentity.id}': {}
    }
  }
  properties: {
    keyVaultReferenceIdentity: backendIdentity.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: 'https://${storage.name}.blob.${environment().suffixes.storage}/${backendPackageContainer.name}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: backendIdentity.id
          }
        }
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '10.0'
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: 100
      }
    }
    siteConfig: {
      appSettings: concat(backendStorageSettings, [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'PumpSync__BackendMode'
          value: 'Hosted'
        }
        {
          name: 'PumpSync__ServiceTokenIssuer'
          value: 'pumpsync'
        }
        {
          name: 'PumpSync__ServiceTokenAudience'
          value: 'pumpsync-ios'
        }
        {
          name: 'PumpSync__ServiceTokenSigningKey'
          value: '@Microsoft.KeyVault(SecretUri=${serviceTokenSigningKeySecret.properties.secretUri})'
        }
        {
          name: 'AppStore__BundleId'
          value: appStoreBundleId
        }
        {
          name: 'AppStore__Environment'
          value: appStoreEnvironment
        }
        {
          name: 'AppStore__SubscriptionProductId'
          value: appStoreSubscriptionProductId
        }
        {
          name: 'AppStore__IssuerId'
          value: appStoreIssuerId
        }
        {
          name: 'AppStore__KeyId'
          value: appStoreKeyId
        }
        {
          name: 'AppStore__PrivateKey'
          value: '@Microsoft.KeyVault(SecretUri=${appStorePrivateKeySecret.properties.secretUri})'
        }
        {
          name: 'AppStore__RootCertificatePem'
          value: appStoreRootCertificatePem
        }
        {
          name: 'AzureStorage__AccountName'
          value: storage.name
        }
        {
          name: 'AzureStorage__SubscriptionEntitlementsTableName'
          value: subscriptionEntitlementsTable.name
        }
        {
          name: 'AzureStorage__InstallationsTableName'
          value: installationsTable.name
        }
        {
          name: 'AzureStorage__InstallationLookupTableName'
          value: installationLookupTable.name
        }
        {
          name: 'AzureStorage__SyncAttemptsTableName'
          value: syncAttemptsTable.name
        }
        {
          name: 'AzureStorage__RateLimitBucketsTableName'
          value: rateLimitBucketsTable.name
        }
        {
          name: 'AzureStorage__AppStoreNotificationIdempotencyTableName'
          value: appStoreNotificationIdempotencyTable.name
        }
        {
          name: 'AzureStorage__AuditEventsTableName'
          value: auditEventsTable.name
        }
        {
          name: 'TandemSource__EventTimeZoneId'
          value: 'UTC'
        }
      ])
    }
  }
}

resource logDrainFunctionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: logDrainFunctionAppName
  location: location
  tags: union(tags, {
    service: 'log-drain'
  })
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${logDrainIdentity.id}': {}
    }
  }
  properties: {
    keyVaultReferenceIdentity: logDrainIdentity.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: 'https://${storage.name}.blob.${environment().suffixes.storage}/${logDrainPackageContainer.name}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: logDrainIdentity.id
          }
        }
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '10.0'
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: 100
      }
    }
    siteConfig: {
      appSettings: concat(logDrainStorageSettings, [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'LogDrain__SharedSecret'
          value: '@Microsoft.KeyVault(SecretUri=${logDrainSharedSecretSecret.properties.secretUri})'
        }
      ])
    }
  }
}

resource modelCostUpdaterFunctionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: modelCostUpdaterFunctionAppName
  location: location
  tags: union(tags, {
    service: 'model-cost-updater'
  })
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${modelCostUpdaterIdentity.id}': {}
    }
  }
  properties: {
    keyVaultReferenceIdentity: modelCostUpdaterIdentity.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: 'https://${storage.name}.blob.${environment().suffixes.storage}/${modelCostUpdaterPackageContainer.name}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: modelCostUpdaterIdentity.id
          }
        }
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '10.0'
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: 100
      }
    }
    siteConfig: {
      appSettings: concat(modelCostUpdaterStorageSettings, [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'ModelCostUpdater__Schedule'
          value: modelCostUpdaterSchedule
        }
        {
          name: 'ModelCostUpdater__CatalogUrl'
          value: modelCostUpdaterCatalogUrl
        }
      ])
    }
  }
}

resource backendKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, backendIdentity.id, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: backendIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logDrainKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, logDrainIdentity.id, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: logDrainIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource backendBlobRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, backendIdentity.id, storageBlobDataOwnerRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: backendIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource backendQueueRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, backendIdentity.id, storageQueueDataContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: backendIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource backendTableRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, backendIdentity.id, storageTableDataContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: backendIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logDrainBlobRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, logDrainIdentity.id, storageBlobDataOwnerRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: logDrainIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logDrainQueueRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, logDrainIdentity.id, storageQueueDataContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: logDrainIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logDrainTableRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, logDrainIdentity.id, storageTableDataContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: logDrainIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource modelCostUpdaterBlobRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, modelCostUpdaterIdentity.id, storageBlobDataOwnerRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: modelCostUpdaterIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource modelCostUpdaterQueueRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, modelCostUpdaterIdentity.id, storageQueueDataContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: modelCostUpdaterIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource modelCostUpdaterTableRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, modelCostUpdaterIdentity.id, storageTableDataContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: modelCostUpdaterIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output backendFunctionAppName string = backendFunctionApp.name
output logDrainFunctionAppName string = logDrainFunctionApp.name
output modelCostUpdaterFunctionAppName string = modelCostUpdaterFunctionApp.name
output backendManagedIdentityName string = backendIdentity.name
output backendManagedIdentityClientId string = backendIdentity.properties.clientId
output backendManagedIdentityPrincipalId string = backendIdentity.properties.principalId
output storageAccountName string = storage.name
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output applicationInsightsName string = appInsights.name
output logWorkspaceName string = logWorkspace.name
output subscriptionEntitlementsTableName string = subscriptionEntitlementsTable.name
output installationsTableName string = installationsTable.name
output syncAttemptsTableName string = syncAttemptsTable.name
