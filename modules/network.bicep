// VNet + subnets + all private DNS zones the platform's data services need.
// - snet-func-integration : delegated Microsoft.App/environments (Flex Consumption VNet integration)
// - snet-private-endpoints: hosts every private endpoint
// - snet-apps             : delegated Microsoft.Web/serverFarms (App Service regional VNet integration)
param vnetName string
param location string
param tags object
param vnetAddressPrefix string = '10.40.0.0/16'
param funcSubnetPrefix string = '10.40.1.0/24'
param peSubnetPrefix string = '10.40.2.0/24'
param appsSubnetPrefix string = '10.40.3.0/24'
param networkIsolation string = 'privateEndpoint'
@description('Optional peered compute VNet that also needs private DNS resolution.')
param additionalVnetId string = ''

// Service endpoints are enabled on the compute subnets only in serviceEndpoint mode,
// so the data-service firewalls can allow those subnets (free alternative to PEs).
var subnetServiceEndpoints = networkIsolation == 'serviceEndpoint' ? [
  {
    service: 'Microsoft.Storage'
  }
  {
    service: 'Microsoft.EventHub'
  }
  {
    service: 'Microsoft.AzureCosmosDB'
  }
  {
    service: 'Microsoft.KeyVault'
  }
] : []

// Event Hubs requires at least one explicit firewall rule when public access is
// enabled for IoT Hub's trusted-service route. This otherwise-unused regional
// subnet supplies that narrow rule while application traffic still uses the PE.
var appsSubnetServiceEndpoints = networkIsolation == 'privateEndpoint' ? [
  {
    service: 'Microsoft.EventHub'
  }
] : subnetServiceEndpoints

var usePrivateEndpoints = networkIsolation == 'privateEndpoint'

// Private DNS zones for every service that gets a private endpoint.
var zoneNames = [
  'privatelink.blob.${environment().suffixes.storage}'
  'privatelink.queue.${environment().suffixes.storage}'
  'privatelink.table.${environment().suffixes.storage}'
  'privatelink.file.${environment().suffixes.storage}'
  'privatelink.dfs.${environment().suffixes.storage}'
  'privatelink.documents.azure.com'
  'privatelink.webpubsub.azure.com'
  'privatelink.servicebus.windows.net'
  'privatelink.vaultcore.azure.net'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
]

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-func-integration'
        properties: {
          addressPrefix: funcSubnetPrefix
          serviceEndpoints: subnetServiceEndpoints
          delegations: [
            {
              name: 'flexConsumption'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: peSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-apps'
        properties: {
          addressPrefix: appsSubnetPrefix
          serviceEndpoints: appsSubnetServiceEndpoints
          delegations: [
            {
              name: 'appServicePlan'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }
}

resource zones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for z in zoneNames: if (usePrivateEndpoints) {
  name: z
  location: 'global'
  tags: tags
}]

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (z, i) in zoneNames: if (usePrivateEndpoints) {
  parent: zones[i]
  name: 'link-to-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}]

resource additionalLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (z, i) in zoneNames: if (usePrivateEndpoints && !empty(additionalVnetId)) {
  parent: zones[i]
  name: 'link-to-compute-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: additionalVnetId
    }
  }
}]

output vnetId string = vnet.id
output vnetName string = vnet.name
output funcSubnetId string = '${vnet.id}/subnets/snet-func-integration'
output peSubnetId string = '${vnet.id}/subnets/snet-private-endpoints'
output appsSubnetId string = '${vnet.id}/subnets/snet-apps'
output dnsZoneIds object = usePrivateEndpoints ? {
  blob: zones[0].id
  queue: zones[1].id
  table: zones[2].id
  file: zones[3].id
  dfs: zones[4].id
  documents: zones[5].id
  webpubsub: zones[6].id
  servicebus: zones[7].id
  vault: zones[8].id
  cognitiveServices: [
    zones[9].id
    zones[10].id
    zones[11].id
  ]
} : {}
