// Custom Event Hub namespace. Client access uses private/service endpoints while
// IoT Hub routing uses the trusted Microsoft services public exception.
param name string
param location string
param tags object
param peSubnetId string
param servicebusDnsZoneId string = ''
param identityPrincipalId string
param iotHubPrincipalId string
param networkIsolation string = 'privateEndpoint'
param allowedSubnetIds array = []
param hubName string = 'telemetry'
param consumerGroups array = [
  'analytics'
]

var usePrivateEndpoints = networkIsolation == 'privateEndpoint'

resource ns 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

resource hub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: ns
  name: hubName
  properties: {
    partitionCount: 4
    messageRetentionInDays: 1
  }
}

resource cg 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = [for g in consumerGroups: {
  parent: hub
  name: g
}]

// Azure Event Hubs Data Receiver for the platform MI.
resource role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(ns.id, identityPrincipalId, 'eh-receiver')
  scope: ns
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde') // Azure Event Hubs Data Receiver
    principalType: 'ServicePrincipal'
  }
}

resource senderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(ns.id, identityPrincipalId, 'eh-sender')
  scope: ns
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2b629674-e913-4c01-ae53-ef4638d8f975')
    principalType: 'ServicePrincipal'
  }
}

resource iotHubSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(ns.id, iotHubPrincipalId, 'iot-hub-event-hubs-sender')
  scope: ns
  properties: {
    principalId: iotHubPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2b629674-e913-4c01-ae53-ef4638d8f975')
    principalType: 'ServicePrincipal'
  }
}

resource networkRules 'Microsoft.EventHub/namespaces/networkRuleSets@2024-01-01' = {
  parent: ns
  name: 'default'
  properties: {
    defaultAction: 'Deny'
    publicNetworkAccess: 'Enabled'
    trustedServiceAccessEnabled: true
    ipRules: []
    virtualNetworkRules: [for subnetId in allowedSubnetIds: {
      subnet: {
        id: subnetId
      }
      ignoreMissingVnetServiceEndpoint: false
    }]
  }
}

module pe 'privateEndpoint.bicep' = if (usePrivateEndpoints) {
  name: 'pe-${name}'
  params: {
    name: 'pe-${name}'
    location: location
    tags: tags
    peSubnetId: peSubnetId
    serviceId: ns.id
    groupIds: [
      'namespace'
    ]
    dnsZoneId: servicebusDnsZoneId
  }
}

output id string = ns.id
output name string = ns.name
output hubName string = hub.name
output endpoint string = 'sb://${ns.name}.servicebus.windows.net'
