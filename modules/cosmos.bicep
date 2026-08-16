// Cosmos DB (serverless, SQL API) with private/service endpoint access only.
// The VNet-integrated telemetry Function persists flight summaries via managed identity.
param name string
param location string
param privateEndpointLocation string
param tags object
param peSubnetId string
param documentsDnsZoneId string = ''
param identityPrincipalId string
param networkIsolation string = 'privateEndpoint'
param allowedSubnetIds array = []
param databaseName string = 'droneOps'
param containerDefinitions array = [
  {
    name: 'telemetry'
    partitionKey: '/deviceId'
  }
  {
    name: 'identities'
    partitionKey: '/appUserId'
  }
  {
    name: 'rooms'
    partitionKey: '/roomId'
  }
  {
    name: 'devices'
    partitionKey: '/deviceId'
  }
  {
    name: 'pilotAssignments'
    partitionKey: '/pilotId'
  }
  {
    name: 'installations'
    partitionKey: '/deviceId'
    defaultTtl: -1
  }
  {
    name: 'enrollmentBundles'
    partitionKey: '/deviceId'
    defaultTtl: -1
  }
  {
    name: 'controlClaims'
    partitionKey: '/deviceId'
    defaultTtl: -1
  }
  {
    name: 'flights'
    partitionKey: '/deviceId'
  }
]

var usePrivateEndpoints = networkIsolation == 'privateEndpoint'

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: name
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    publicNetworkAccess: usePrivateEndpoints ? 'Disabled' : 'Enabled'
    isVirtualNetworkFilterEnabled: !usePrivateEndpoints
    virtualNetworkRules: [for subnetId in (usePrivateEndpoints ? [] : allowedSubnetIds): {
      id: subnetId
      ignoreMissingVNetServiceEndpoint: false
    }]
    disableLocalAuth: true
    minimalTlsVersion: 'Tls12'
  }
}

resource db 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmos
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource containers 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = [for definition in containerDefinitions: {
  parent: db
  name: definition.name
  properties: {
    resource: union({
      id: definition.name
      partitionKey: {
        paths: [
          definition.partitionKey
        ]
        kind: 'Hash'
      }
    }, contains(definition, 'defaultTtl') ? {
      defaultTtl: definition.defaultTtl
    } : {})
  }
}]

// Cosmos DB Built-in Data Contributor (data-plane) for the platform MI.
resource sqlRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmos
  name: guid(cosmos.id, identityPrincipalId, 'cosmos-data-contributor')
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: cosmos.id
  }
}

module pe 'privateEndpoint.bicep' = if (usePrivateEndpoints) {
  name: 'pe-${name}'
  params: {
    name: 'pe-${name}'
    location: privateEndpointLocation
    tags: tags
    peSubnetId: peSubnetId
    serviceId: cosmos.id
    groupIds: [
      'Sql'
    ]
    dnsZoneId: documentsDnsZoneId
  }
}

output id string = cosmos.id
output name string = cosmos.name
output endpoint string = cosmos.properties.documentEndpoint
output databaseName string = db.name
