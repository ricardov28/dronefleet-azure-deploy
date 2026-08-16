// =====================================================================================
// Dronefleet platform — resource-group-scope orchestrator.
// Wires the layer modules in dependency order. Bicep computes the actual ordering
// from resource references, so declaration order here is just for readability.
//
// NOTE: built in validated stages. This file grows as each layer module is added.
// Stage 1 (current): foundation — monitoring, identity, network.
// =====================================================================================

targetScope = 'resourceGroup'

param namePrefix string
param location string
param computeLocation string = ''
param cosmosLocation string = ''
param tags object
param uniqueSeed string = ''
param networkIsolation string = 'privateEndpoint'
param deployAiVision bool
param foundryLocation string = 'eastus2'
param foundryChatDeploymentName string = 'vision-chat'
param foundryChatModelName string = 'gpt-5.1'
param foundryChatModelVersion string = '2025-11-13'
param foundryChatVersionUpgradeOption string = 'OnceCurrentVersionExpired'
param foundryRealtimeModelVersion string = '2025-08-28'
param foundryModelCapacity int = 10
param entraApiClientId string = ''
param entraPublicClientId string = ''
param entraRequiredScope string = 'Drone.Provision'
@description('One or more comma-separated tenantId:userObjectId Dronefleet administrators. Does not create pilot assignment documents.')
param adminIdentities string
param primaryDeviceId string = 'drone01RPI'
param aiGpuBaseUrl string = ''
@description('Creates the GPU registry and serverless T4 environment. Requires approved Managed Environment Consumption T4 GPUs quota.')
param deployGpuInfrastructure bool = false
@description('Creates the scale-to-zero detector app after its image is published. Requires deployGpuInfrastructure and an AI shared key.')
param deployGpuApp bool = false
@description('Region with Container Apps serverless T4 support and approved subscription quota.')
param gpuLocation string = ''
param gpuImageRepository string = 'ai-detection'
param gpuImageTag string = 't4-v8'

@secure()
param recordingDestinationContainerUrl string = ''

@secure()
param aiSharedKey string = ''

// 6-char deterministic suffix for globally-unique names. Stable per subscription+RG+prefix
// (so re-deploys are idempotent), regenerated only if uniqueSeed changes.
var suffix = take(uniqueString(resourceGroup().id, namePrefix, uniqueSeed), 6)
var effectiveComputeLocation = empty(computeLocation) ? location : computeLocation
var effectiveCosmosLocation = empty(cosmosLocation) ? location : cosmosLocation
var effectiveGpuLocation = empty(gpuLocation) ? location : gpuLocation

var names = {
  logAnalytics: '${namePrefix}-law-${suffix}'
  appInsights: '${namePrefix}-appi-${suffix}'
  identity: '${namePrefix}-mi-${suffix}'
  keyVault: '${namePrefix}-kv-${suffix}'
  vnet: '${namePrefix}-vnet'
  computeVnet: '${namePrefix}-compute-vnet'
  iotHub: '${namePrefix}-iothub-${suffix}'
  eventHub: '${namePrefix}-eh-${suffix}'
  webPubSub: '${namePrefix}-wps-${suffix}'
  funcStorage: take(toLower(replace('${namePrefix}stfn${suffix}', '-', '')), 24)
  forwarderFunc: '${namePrefix}-fwd-${suffix}'
  cosmos: '${namePrefix}-cosmos-${suffix}'
  adls: take(toLower(replace('${namePrefix}adls${suffix}', '-', '')), 24)
  appPlan: '${namePrefix}-appplan-${suffix}'
  backend: '${namePrefix}-backend-${suffix}'
  acs: '${namePrefix}-acs-${suffix}'
  maps: '${namePrefix}-maps-${suffix}'
  foundry: '${namePrefix}-foundry-${suffix}'
  foundryProject: '${namePrefix}-project'
  gpuRegistry: take(toLower(replace('${namePrefix}acr${suffix}', '-', '')), 50)
  gpuEnvironment: '${namePrefix}-gpu-env-${suffix}'
  gpuApp: '${namePrefix}-gpu-${suffix}'
}
var backendUrl = 'https://${names.backend}.azurewebsites.net'

// Web PubSub group the browser subscribes to (per-device suffix added by the function).
var webPubSubGroup = 'attitude'

// ---------------------------------------------------------------- Foundation
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    logAnalyticsName: names.logAnalytics
    appInsightsName: names.appInsights
    location: location
    tags: tags
  }
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: {
    name: names.identity
    location: location
    tags: tags
  }
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    vnetName: names.vnet
    location: location
    tags: tags
    networkIsolation: networkIsolation
    additionalVnetId: computeNetwork.outputs.vnetId
  }
}

module computeNetwork 'modules/computeNetwork.bicep' = {
  name: 'computeNetwork'
  params: {
    vnetName: names.computeVnet
    location: effectiveComputeLocation
    tags: tags
  }
}

module vnetPeering 'modules/vnetPeering.bicep' = {
  name: 'vnetPeering'
  params: {
    primaryVnetName: network.outputs.vnetName
    computeVnetName: computeNetwork.outputs.vnetName
  }
}

module keyVault 'modules/keyVault.bicep' = {
  name: 'keyVault'
  params: {
    name: names.keyVault
    location: location
    tags: tags
    identityPrincipalId: identity.outputs.principalId
    peSubnetId: network.outputs.peSubnetId
    vaultDnsZoneId: networkIsolation == 'privateEndpoint' ? network.outputs.dnsZoneIds.vault : ''
    networkIsolation: networkIsolation
    allowedSubnetIds: backendSubnetIds
    recordingDestinationContainerUrl: recordingDestinationContainerUrl
    aiSharedKey: aiSharedKey
  }
}

// In serviceEndpoint mode, these subnets are allowed through the data-service firewalls.
var backendSubnetIds = [
  network.outputs.funcSubnetId
  network.outputs.appsSubnetId
]

// ---------------------------------------------------------------- Messaging (A) + backend storage
module webpubsub 'modules/webpubsub.bicep' = {
  name: 'webpubsub'
  params: {
    name: names.webPubSub
    location: location
    tags: tags
    identityPrincipalId: identity.outputs.principalId
    keyVaultName: keyVault.outputs.name
  }
}

// Create the hub first so its system-assigned identity can receive destination
// roles before the final routing configuration is applied.
module iothub 'modules/iothub.bicep' = {
  name: 'iothub'
  params: {
    name: names.iotHub
    location: location
    tags: tags
    identityPrincipalId: identity.outputs.principalId
    keyVaultName: keyVault.outputs.name
  }
}

module eventhub 'modules/eventhub.bicep' = {
  name: 'eventhub'
  params: {
    name: names.eventHub
    location: location
    tags: tags
    networkIsolation: networkIsolation
    allowedSubnetIds: networkIsolation == 'privateEndpoint' ? [
      network.outputs.appsSubnetId
    ] : backendSubnetIds
    peSubnetId: network.outputs.peSubnetId
    servicebusDnsZoneId: networkIsolation == 'privateEndpoint' ? network.outputs.dnsZoneIds.servicebus : ''
    identityPrincipalId: identity.outputs.principalId
    iotHubPrincipalId: iothub.outputs.principalId
  }
}

module funcStorage 'modules/storage.bicep' = {
  name: 'funcStorage'
  params: {
    name: names.funcStorage
    location: location
    tags: tags
    networkIsolation: networkIsolation
    allowedSubnetIds: backendSubnetIds
    peSubnetId: network.outputs.peSubnetId
    dnsZoneIds: network.outputs.dnsZoneIds
    identityPrincipalId: identity.outputs.principalId
  }
}

// ---------------------------------------------------------------- Forwarder Function (A)
// IoT Hub built-in endpoint -> Web PubSub, fully identity-based (no keys).
module forwarder 'modules/functionApp.bicep' = {
  name: 'forwarder'
  params: {
    name: names.forwarderFunc
    location: effectiveComputeLocation
    tags: tags
    planId: appPlan.outputs.id
    storageAccountName: funcStorage.outputs.name
    storageBlobEndpoint: funcStorage.outputs.blobEndpoint
    identityId: identity.outputs.id
    identityClientId: identity.outputs.clientId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    appsSubnetId: computeNetwork.outputs.appsSubnetId
    extraAppSettings: [
      // IoT Hub routes telemetry to this custom Event Hub with its system
      // identity; the Function consumes it with the platform identity.
      {
        name: 'IotHubEventHubConnection__fullyQualifiedNamespace'
        value: replace(replace(eventhub.outputs.endpoint, 'sb://', ''), '/', '')
      }
      {
        name: 'IotHubEventHubConnection__credential'
        value: 'managedidentity'
      }
      {
        name: 'IotHubEventHubConnection__clientId'
        value: identity.outputs.clientId
      }
      {
        name: 'IotHubEventHubName'
        value: eventhub.outputs.hubName
      }
      {
        name: 'IotHubConsumerGroup'
        value: 'analytics'
      }
      {
        name: 'IotHubSourceName'
        value: iothub.outputs.name
      }
      {
        name: 'CosmosEndpoint'
        value: cosmos.outputs.endpoint
      }
      {
        name: 'CosmosDatabase'
        value: cosmos.outputs.databaseName
      }
      {
        name: 'CosmosFlightsContainer'
        value: 'flights'
      }
      // Identity-based Web PubSub output.
      {
        name: 'WebPubSubEndpoint'
        value: webpubsub.outputs.endpoint
      }
      {
        name: 'WebPubSubHub'
        value: webpubsub.outputs.hubName
      }
      {
        name: 'WebPubSubGroup'
        value: webPubSubGroup
      }
    ]
  }
  dependsOn: [
    iothubRouting
  ]
}

// ---------------------------------------------------------------- Data stores (B)
module cosmos 'modules/cosmos.bicep' = {
  name: 'cosmos'
  params: {
    name: names.cosmos
    location: effectiveCosmosLocation
    privateEndpointLocation: location
    tags: tags
    networkIsolation: networkIsolation
    allowedSubnetIds: backendSubnetIds
    peSubnetId: network.outputs.peSubnetId
    documentsDnsZoneId: networkIsolation == 'privateEndpoint' ? network.outputs.dnsZoneIds.documents : ''
    identityPrincipalId: identity.outputs.principalId
  }
}

// ADLS Gen2 analytics store — hierarchical namespace, private blob + dfs endpoints.
module adls 'modules/storage.bicep' = {
  name: 'adls'
  params: {
    name: names.adls
    location: location
    tags: tags
    networkIsolation: networkIsolation
    allowedSubnetIds: backendSubnetIds
    peSubnetId: network.outputs.peSubnetId
    dnsZoneIds: network.outputs.dnsZoneIds
    identityPrincipalId: identity.outputs.principalId
    iotHubPrincipalId: iothub.outputs.principalId
    additionalBlobContributorPrincipalIds: [
      acs.outputs.principalId
    ]
    isHnsEnabled: true
    privateGroups: [
      'blob'
      'dfs'
    ]
    blobContainers: [
      'drone-analytics'
      'drone-snapshots'
      'recordings'
      'iothub-dronelogs'
    ]
  }
}

module iothubRouting 'modules/iothubRouting.bicep' = {
  name: 'iothubRouting'
  params: {
    name: names.iotHub
    location: location
    tags: tags
    archiveStorageBlobEndpoint: adls.outputs.blobEndpoint
    eventHubEndpointUri: eventhub.outputs.endpoint
  }
}

// ---------------------------------------------------------------- App hosting + PaaS (C/D/E/F)
module appPlan 'modules/appServicePlan.bicep' = {
  name: 'appPlan'
  params: {
    name: names.appPlan
    location: effectiveComputeLocation
    tags: tags
  }
}

module maps 'modules/maps.bicep' = {
  name: 'maps'
  params: {
    name: names.maps
    tags: tags
    keyVaultName: keyVault.outputs.name
  }
}

module acs 'modules/acs.bicep' = {
  name: 'acs'
  params: {
    name: names.acs
    tags: tags
    keyVaultName: keyVault.outputs.name
  }
}

module foundry 'modules/foundry.bicep' = if (deployAiVision) {
  name: 'foundry'
  params: {
    name: names.foundry
    projectName: names.foundryProject
    location: foundryLocation
    privateEndpointLocation: location
    tags: tags
    identityId: identity.outputs.id
    identityPrincipalId: identity.outputs.principalId
    peSubnetId: network.outputs.peSubnetId
    dnsZoneIds: networkIsolation == 'privateEndpoint' ? network.outputs.dnsZoneIds.cognitiveServices : []
    networkIsolation: networkIsolation
    chatDeploymentName: foundryChatDeploymentName
    chatModelName: foundryChatModelName
    chatModelVersion: foundryChatModelVersion
    chatCapacity: foundryModelCapacity
    chatVersionUpgradeOption: foundryChatVersionUpgradeOption
    realtimeModelVersion: foundryRealtimeModelVersion
    realtimeCapacity: foundryModelCapacity
  }
}

module gpuRegistry 'modules/containerRegistry.bicep' = if (deployGpuInfrastructure) {
  name: 'gpuRegistry'
  params: {
    name: names.gpuRegistry
    location: effectiveGpuLocation
    tags: union(tags, {
      component: 'gpu-registry'
    })
    pullIdentityPrincipalId: identity.outputs.principalId
  }
}

module gpu 'modules/gpuContainerApp.bicep' = if (deployGpuInfrastructure) {
  name: 'gpuInference'
  params: {
    name: names.gpuApp
    environmentName: names.gpuEnvironment
    location: effectiveGpuLocation
    tags: union(tags, {
      component: 'gpu-inference'
    })
    infrastructureSubnetId: network.outputs.funcSubnetId
    identityId: identity.outputs.id
    registryServer: gpuRegistry!.outputs.loginServer
    image: '${gpuRegistry!.outputs.loginServer}/${gpuImageRepository}:${gpuImageTag}'
    aiSharedKeySecretUrl: '${keyVault.outputs.uri}secrets/ai-shared-key'
    webPubSubConnectionSecretUrl: '${keyVault.outputs.uri}secrets/web-pubsub-connection-string'
    webPubSubHub: webpubsub.outputs.hubName
    detectionsGroup: 'detections'
    deployApp: deployGpuApp
  }
}

// Settings every web app gets — all reference always-created services (safe under toggles).
var keyVaultSecretPrefix = '@Microsoft.KeyVault(SecretUri=${keyVault.outputs.uri}secrets/'
var effectiveAiGpuBaseUrl = deployGpuApp ? gpu!.outputs.baseUrl : aiGpuBaseUrl

var backendAppSettings = concat([
  {
    name: 'PUBLIC_API_BASE_URL'
    value: backendUrl
  }
  {
    name: 'CALLBACK_URI'
    value: '${backendUrl}/filestatus'
  }
  {
    name: 'WEB_PUBSUB_CONNECTION_STRING'
    value: '${keyVaultSecretPrefix}web-pubsub-connection-string/)'
  }
  {
    name: 'HUB_NAME'
    value: webpubsub.outputs.hubName
  }
  {
    name: 'IOTHUB_SERVICE_CONNECTION_STRING'
    value: '${keyVaultSecretPrefix}iothub-service-connection-string/)'
  }
  {
    name: 'IOTHUB_DEVICE_ID'
    value: primaryDeviceId
  }
  {
    name: 'COSMOS_ENDPOINT'
    value: cosmos.outputs.endpoint
  }
  {
    name: 'COSMOS_DATABASE'
    value: cosmos.outputs.databaseName
  }
  {
    name: 'COSMOS_AUTH'
    value: 'aad'
  }
  {
    name: 'ENABLE_AZURE_STORAGE'
    value: 'true'
  }
  {
    name: 'AZURE_STORAGE_ACCOUNT_NAME'
    value: adls.outputs.name
  }
  {
    name: 'AZURE_STORAGE_DATALAKE_ENDPOINT'
    value: adls.outputs.dfsEndpoint
  }
  {
    name: 'AZURE_COMMUNICATION_SERVICES_CONNECTION_STRING'
    value: '${keyVaultSecretPrefix}acs-connection-string/)'
  }
  {
    name: 'ACS_RESOURCE_NAME'
    value: names.acs
  }
  {
    name: 'AZURE_MAPS_CLIENT_ID'
    value: maps.outputs.clientId
  }
  {
    name: 'AZURE_MAPS_SUBSCRIPTION_KEY'
    value: '${keyVaultSecretPrefix}azure-maps-subscription-key/)'
  }
  {
    name: 'ENTRA_API_CLIENT_ID'
    value: entraApiClientId
  }
  {
    name: 'ENTRA_PUBLIC_CLIENT_ID'
    value: entraPublicClientId
  }
  {
    name: 'ENTRA_REQUIRED_SCOPE'
    value: entraRequiredScope
  }
  {
    name: 'PILOT_AUTH_ENFORCE'
    value: 'true'
  }
  {
    name: 'ALLOW_DEV_PILOT_HEADER'
    value: 'false'
  }
  {
    name: 'BOOTSTRAP_ADMIN_IDENTITIES'
    value: adminIdentities
  }
  {
    name: 'ACA_GPU_BASE_URL'
    value: effectiveAiGpuBaseUrl
  }
  {
    name: 'RECORDING_DESTINATION_CONTAINER_URL'
    value: !empty(recordingDestinationContainerUrl)
      ? '${keyVaultSecretPrefix}recording-destination-container-url/)'
      : '${adls.outputs.blobEndpoint}recordings'
  }
], !empty(aiSharedKey) ? [
  {
    name: 'AI_SHARED_KEY'
    value: '${keyVaultSecretPrefix}ai-shared-key/)'
  }
] : [], deployAiVision ? [
  {
    name: 'FOUNDRY_ENDPOINT'
    value: foundry!.outputs.foundryEndpoint
  }
  {
    name: 'FOUNDRY_DEPLOYMENT'
    value: foundry!.outputs.chatDeploymentName
  }
  {
    name: 'FOUNDRY_API_VERSION'
    value: '2024-10-21'
  }
  {
    name: 'VOICELIVE_ENDPOINT'
    value: foundry!.outputs.voiceLiveEndpoint
  }
  {
    name: 'VOICELIVE_REGION'
    value: foundryLocation
  }
  {
    name: 'VOICELIVE_MODEL'
    value: foundry!.outputs.realtimeDeploymentName
  }
  {
    name: 'VOICELIVE_API_VERSION'
    value: '2026-04-10'
  }
] : [])

module backendApp 'modules/webApp.bicep' = {
  name: 'backendApp'
  params: {
    name: names.backend
    location: effectiveComputeLocation
    tags: union(tags, {
      component: 'backend'
    })
    planId: appPlan.outputs.id
    identityId: identity.outputs.id
    identityClientId: identity.outputs.clientId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    appsSubnetId: computeNetwork.outputs.appsSubnetId
    linuxFxVersion: 'NODE|22-lts'
    extraAppSettings: backendAppSettings
  }
}

// Foundation outputs (consumed by later stages / for verification).
output identityClientId string = identity.outputs.clientId
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
output funcSubnetId string = network.outputs.funcSubnetId
output peSubnetId string = network.outputs.peSubnetId
output iotHubName string = iothub.outputs.name
output webPubSubName string = webpubsub.outputs.name
output webPubSubEndpoint string = webpubsub.outputs.endpoint
output eventHubNamespaceName string = eventhub.outputs.name
output forwarderFunctionName string = forwarder.outputs.name
output forwarderDefaultHostName string = forwarder.outputs.defaultHostName
output cosmosName string = cosmos.outputs.name
output adlsName string = adls.outputs.name
output keyVaultName string = keyVault.outputs.name
output backendAppName string = backendApp.outputs.name
output backendUrl string = backendUrl
output acsName string = acs.outputs.name
output foundryName string = deployAiVision ? foundry!.outputs.name : ''
output foundryProjectId string = deployAiVision ? foundry!.outputs.projectId : ''
output gpuRegistryName string = deployGpuInfrastructure ? gpuRegistry!.outputs.name : ''
output gpuEnvironmentId string = deployGpuInfrastructure ? gpu!.outputs.environmentId : ''
output gpuAppName string = deployGpuApp ? gpu!.outputs.appName : ''
output gpuBaseUrl string = deployGpuApp ? gpu!.outputs.baseUrl : ''
output mapsName string = maps.outputs.name
