// Linux Function App on the shared Premium v3 App Service plan. This avoids a
// separate Flex worker quota while retaining VNet integration and managed identity.
param name string
param location string
param tags object
param planId string

@description('Storage account (already created) used for AzureWebJobsStorage + the deployment package. Public access off; MI has data roles.')
param storageAccountName string
param storageBlobEndpoint string

@description('Platform user-assigned managed identity.')
param identityId string
param identityClientId string

param appInsightsConnectionString string
param appsSubnetId string

@description('Extra app settings specific to this function [{ name, value }].')
param extraAppSettings array = []

var deploymentContainerName = 'app-package-${name}'

// Deployment package container (control-plane create, works with shared-key off).
resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storageAccountName}/default/${deploymentContainerName}'
}

resource func 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    serverFarmId: planId
    virtualNetworkSubnetId: appsSubnetId
    vnetRouteAllEnabled: true
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Node|22'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      appSettings: concat([
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'true'
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: identityClientId
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: identityClientId
        }
        {
          name: 'FUNCTIONS_PACKAGE_CONTAINER'
          value: '${storageBlobEndpoint}${deploymentContainerName}'
        }
      ], extraAppSettings)
    }
  }
  dependsOn: [
    container
  ]
}

output id string = func.id
output name string = func.name
output defaultHostName string = func.properties.defaultHostName
