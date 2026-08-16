// Web PubSub — PUBLIC endpoint (the drone's control channel and the browser viewer
// are internet clients). Standard tier for managed-identity + hub support. The
// platform MI gets Web PubSub Service Owner so the backend sends to groups with no
// connection string.
param name string
param location string
param tags object
param identityPrincipalId string
param keyVaultName string
param hubName string = 'dronefleet'

resource wps 'Microsoft.SignalRService/webPubSub@2023-08-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard_S1'
    tier: 'Standard'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

resource hub 'Microsoft.SignalRService/webPubSub/hubs@2023-08-01-preview' = {
  parent: wps
  name: hubName
  properties: {
    anonymousConnectPolicy: 'deny'
  }
}

// Web PubSub Service Owner for the platform MI (send to groups, manage clients).
resource role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(wps.id, identityPrincipalId, 'wps-owner')
  scope: wps
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '12cf5a90-567b-43ae-8102-96cf46c7d9b4') // Web PubSub Service Owner
    principalType: 'ServicePrincipal'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource serviceConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'web-pubsub-connection-string'
  properties: {
    value: wps.listKeys().primaryConnectionString
  }
}

output id string = wps.id
output name string = wps.name
output hostName string = wps.properties.hostName
output endpoint string = 'https://${wps.properties.hostName}'
output hubName string = hub.name
