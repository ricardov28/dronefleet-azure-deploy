// Reusable Linux web app on a shared plan: platform user-assigned MI, App Insights,
// optional regional VNet integration, and parameterized app settings.
param name string
param location string
param tags object
param planId string
param identityId string
param identityClientId string
param appInsightsConnectionString string
@description('Set to a subnet id to VNet-integrate; empty to skip.')
param appsSubnetId string = ''
param linuxFxVersion string = 'NODE|20-lts'
param extraAppSettings array = []

var vnetIntegrate = !empty(appsSubnetId)

resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    serverFarmId: planId
    httpsOnly: true
    clientAffinityEnabled: false
    keyVaultReferenceIdentity: identityId
    virtualNetworkSubnetId: vnetIntegrate ? appsSubnetId : null
    vnetRouteAllEnabled: vnetIntegrate
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      appSettings: concat([
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          // Lets the DefaultAzureCredential in app code pick the platform MI.
          name: 'AZURE_CLIENT_ID'
          value: identityClientId
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'false'
        }
      ], extraAppSettings)
    }
  }
}

output id string = app.id
output name string = app.name
output defaultHostName string = app.properties.defaultHostName
