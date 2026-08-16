param primaryVnetName string
param computeVnetName string

resource primary 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: primaryVnetName
}

resource compute 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: computeVnetName
}

resource primaryToCompute 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: primary
  name: 'to-${computeVnetName}'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: compute.id
    }
  }
}

resource computeToPrimary 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: compute
  name: 'to-${primaryVnetName}'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: primary.id
    }
  }
}
