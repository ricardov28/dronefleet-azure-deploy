// Secure storage account with shared-key auth off. Client access uses private or
// service endpoints; IoT Hub routing uses the trusted-services public exception.
// Reused for the function storage and (with isHnsEnabled) the ADLS analytics store.
param name string
param location string
param tags object
param peSubnetId string
param dnsZoneIds object // { blob, queue, table, file, dfs }
param identityPrincipalId string
param privateGroups array = [
  'blob'
  'queue'
  'table'
]
param isHnsEnabled bool = false
param networkIsolation string = 'privateEndpoint'
param allowedSubnetIds array = []
param blobContainers array = []
param iotHubPrincipalId string = ''
param additionalBlobContributorPrincipalIds array = []

var usePrivateEndpoints = networkIsolation == 'privateEndpoint'

// Built-in data-plane roles for identity-based storage access.
var roleDefs = {
  blob: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Owner
  queue: '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor
  table: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor
}

resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: isHnsEnabled
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: [for subnetId in (usePrivateEndpoints ? [] : allowedSubnetIds): {
        id: subnetId
        action: 'Allow'
      }]
    }
  }
}

module pe 'privateEndpoint.bicep' = [for g in privateGroups: if (usePrivateEndpoints) {
  name: 'pe-${name}-${g}'
  params: {
    name: 'pe-${name}-${g}'
    location: location
    tags: tags
    peSubnetId: peSubnetId
    serviceId: sa.id
    groupIds: [
      g
    ]
    dnsZoneId: dnsZoneIds[g]
  }
}]

resource roles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for r in [
  'blob'
  'queue'
  'table'
]: {
  name: guid(sa.id, identityPrincipalId, r)
  scope: sa
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefs[r])
    principalType: 'ServicePrincipal'
  }
}]

resource iotHubBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(iotHubPrincipalId)) {
  name: guid(sa.id, iotHubPrincipalId, 'iot-hub-blob-contributor')
  scope: sa
  properties: {
    principalId: iotHubPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalType: 'ServicePrincipal'
  }
}

resource additionalBlobRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principalId in additionalBlobContributorPrincipalIds: {
  name: guid(sa.id, principalId, 'additional-blob-contributor')
  scope: sa
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalType: 'ServicePrincipal'
  }
}]

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for containerName in blobContainers: {
  name: '${sa.name}/default/${containerName}'
  properties: {
    publicAccess: 'None'
  }
}]

output id string = sa.id
output name string = sa.name
output blobEndpoint string = sa.properties.primaryEndpoints.blob
output dfsEndpoint string = sa.properties.primaryEndpoints.dfs
