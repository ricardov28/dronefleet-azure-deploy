param name string
param location string
param tags object
param archiveStorageBlobEndpoint string
param archiveStorageContainerName string = 'iothub-dronelogs'
param eventHubEndpointUri string
param eventHubName string = 'telemetry'
param skuName string = 'S1'
param capacity int = 1

// IoT Hub egress routing uses the hub's system-assigned identity. Azure requires
// these destinations to expose a firewall-restricted public endpoint with the
// trusted Microsoft services exception; IoT Hub does not route through their PEs.
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
    routing: {
      endpoints: {
        cosmosDBSqlContainers: []
        storageContainers: [
          {
            name: 'telemetryArchive'
            subscriptionId: subscription().subscriptionId
            resourceGroup: resourceGroup().name
            authenticationType: 'identityBased'
            endpointUri: archiveStorageBlobEndpoint
            containerName: archiveStorageContainerName
            batchFrequencyInSeconds: 100
            maxChunkSizeInBytes: 104857600
            fileNameFormat: '{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}.json'
            encoding: 'JSON'
          }
        ]
        eventHubs: [
          {
            name: 'eventhubTelemetry'
            subscriptionId: subscription().subscriptionId
            resourceGroup: resourceGroup().name
            authenticationType: 'identityBased'
            endpointUri: eventHubEndpointUri
            entityPath: eventHubName
          }
        ]
        serviceBusQueues: []
        serviceBusTopics: []
      }
      routes: [
        {
          name: 'builtin'
          source: 'DeviceMessages'
          condition: 'true'
          endpointNames: [
            'events'
          ]
          isEnabled: true
        }
        {
          name: 'archiveTelemetry'
          source: 'DeviceMessages'
          condition: 'NOT IS_DEFINED(messageType)'
          endpointNames: [
            'telemetryArchive'
          ]
          isEnabled: true
        }
        {
          name: 'eventhubTelemetry'
          source: 'DeviceMessages'
          condition: 'true'
          endpointNames: [
            'eventhubTelemetry'
          ]
          isEnabled: true
        }
      ]
      fallbackRoute: {
        name: '$fallback'
        source: 'DeviceMessages'
        condition: 'true'
        endpointNames: [
          'events'
        ]
        isEnabled: true
      }
    }
  }
}

output id string = hub.id
