using '../bicep/main.subscription.bicep'

param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')
param environmentName = 'nonprod'
param appName = 'pumpsync'
param resourceGroupName = readEnvironmentVariable('AZURE_RESOURCE_GROUP', 'rg-pumpsync-nonprod')
param serviceTokenSigningKey = readEnvironmentVariable('PUMPSYNC_SERVICE_TOKEN_SIGNING_KEY', '')
param appStoreBundleId = readEnvironmentVariable('APPSTORE_BUNDLE_ID', 'dev.ericslutz.PumpSync')
param appStoreEnvironment = readEnvironmentVariable('APPSTORE_ENVIRONMENT', 'Sandbox')
param appStoreSubscriptionProductId = readEnvironmentVariable('APPSTORE_SUBSCRIPTION_PRODUCT_ID', 'dev.ericslutz.PumpSync.hosted.monthly')
param appStoreIssuerId = readEnvironmentVariable('APPSTORE_ISSUER_ID', '')
param appStoreKeyId = readEnvironmentVariable('APPSTORE_KEY_ID', '')
param appStorePrivateKey = readEnvironmentVariable('APPSTORE_PRIVATE_KEY', '')
param appStoreRootCertificatePem = readEnvironmentVariable('APPSTORE_ROOT_CERTIFICATE_PEM', '')
param logDrainSharedSecret = readEnvironmentVariable('PUMPSYNC_LOG_DRAIN_SHARED_SECRET', '')
param modelCostUpdaterSchedule = readEnvironmentVariable('PUMPSYNC_MODEL_COST_UPDATER_SCHEDULE', '0 0 4 * * *')
param modelCostUpdaterCatalogUrl = readEnvironmentVariable('PUMPSYNC_MODEL_COST_CATALOG_URL', '')
