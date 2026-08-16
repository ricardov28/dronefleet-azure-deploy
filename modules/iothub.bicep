// IoT Hub — PUBLIC endpoint (drones connect over 5G / the internet). Secured by
// per-device identity (X.509 via the cert-handler layer), not network isolation.
// Consumer groups let multiple readers (forwarder function, analytics) each hold
// independent partition leases.
param name string
param location string
param tags object
param skuName string = 'S1'
param capacity int = 1
param identityPrincipalId string
param keyVaultName string
param consumerGroups array = [
  'listener01'
  'analytics'
]

resource hub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: skuName
    capacity: capacity
  }
  properties: {
    minTlsVersion: '1.2'
  }
}

resource cg 'Microsoft.Devices/IotHubs/eventHubEndpoints/ConsumerGroups@2023-06-30' = [for g in consumerGroups: {
  name: '${name}/events/${g}'
  properties: {
    name: g
  }
  dependsOn: [
    hub
  ]
}]

// IoT Hub Data Reader for the platform MI — lets the forwarder read the built-in
// Event Hub-compatible endpoint over managed identity (no shared-access key).
resource role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(hub.id, identityPrincipalId, 'iot-data-reader')
  scope: hub
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b447c946-2db7-41ec-983d-d8bf3b1c77e3') // IoT Hub Data Reader
    principalType: 'ServicePrincipal'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

var ownerPolicy = first(filter(hub.listKeys().value, policy => policy.keyName == 'iothubowner'))

resource serviceConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'iothub-service-connection-string'
  properties: {
    value: 'HostName=${hub.properties.hostName};SharedAccessKeyName=${ownerPolicy.keyName};SharedAccessKey=${ownerPolicy.primaryKey}'
  }
}

output id string = hub.id
output name string = hub.name
output hostName string = hub.properties.hostName
// Built-in Event Hub-compatible endpoint (for the identity-based trigger).
output builtInEndpoint string = hub.properties.eventHubEndpoints.events.endpoint
output builtInPath string = hub.properties.eventHubEndpoints.events.path
output principalId string = hub.identity.principalId
