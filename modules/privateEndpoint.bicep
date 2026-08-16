// Reusable private endpoint + private DNS zone group.
param name string
param location string
param tags object
param peSubnetId string
param serviceId string
param groupIds array
param dnsZoneId string = ''
param dnsZoneIds array = []

var effectiveDnsZoneIds = !empty(dnsZoneIds) ? dnsZoneIds : (!empty(dnsZoneId) ? [dnsZoneId] : [])

resource pe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc'
        properties: {
          privateLinkServiceId: serviceId
          groupIds: groupIds
        }
      }
    ]
  }
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (!empty(effectiveDnsZoneIds)) {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneId, index) in effectiveDnsZoneIds: {
      name: 'config-${index}'
      properties: {
        privateDnsZoneId: zoneId
      }
    }]
  }
}

output id string = pe.id
