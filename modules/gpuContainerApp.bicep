param name string
param environmentName string
param location string
param tags object
param infrastructureSubnetId string
param identityId string
param registryServer string
param image string
param aiSharedKeySecretUrl string
param webPubSubConnectionSecretUrl string
param webPubSubHub string
param detectionsGroup string = 'detections'
param deployApp bool = false

var workloadProfileName = 'gpu-t4'

// Azure accepts the environment definition before GPU application quota is
// consumed. The subscription must have Managed Environment Consumption T4 GPUs
// quota before a revision can be provisioned on this workload profile.
resource environment 'Microsoft.App/managedEnvironments@2026-01-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    publicNetworkAccess: 'Enabled'
    vnetConfiguration: {
      infrastructureSubnetId: infrastructureSubnetId
      internal: false
    }
    workloadProfiles: [
      {
        name: workloadProfileName
        workloadProfileType: 'Consumption-GPU-NC8as-T4'
      }
    ]
    zoneRedundant: false
  }
}

resource app 'Microsoft.App/containerApps@2026-01-01' = if (deployApp) {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    environmentId: environment.id
    workloadProfileName: workloadProfileName
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        allowInsecure: false
        targetPort: 8081
        transport: 'auto'
      }
      registries: [
        {
          server: registryServer
          identity: identityId
        }
      ]
      secrets: [
        {
          name: 'ai-shared-key'
          keyVaultUrl: aiSharedKeySecretUrl
          identity: identityId
        }
        {
          name: 'web-pubsub-connection-string'
          keyVaultUrl: webPubSubConnectionSecretUrl
          identity: identityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'ai-detection'
          image: image
          env: [
            {
              name: 'AI_SHARED_KEY'
              secretRef: 'ai-shared-key'
            }
            {
              name: 'WEBPUBSUB_CONNECTION_STRING'
              secretRef: 'web-pubsub-connection-string'
            }
            {
              name: 'WEBPUBSUB_HUB'
              value: webPubSubHub
            }
            {
              name: 'DETECTIONS_GROUP'
              value: detectionsGroup
            }
            {
              name: 'DETECT_FPS'
              value: '6'
            }
          ]
          resources: {
            cpu: 8
            memory: '56Gi'
          }
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
        rules: [
          {
            name: 'http'
            http: {
              metadata: {
                concurrentRequests: '1'
              }
            }
          }
        ]
      }
    }
  }
}

output environmentId string = environment.id
output appName string = deployApp ? app!.name : ''
output baseUrl string = deployApp ? 'https://${app!.properties.configuration.ingress.fqdn}' : ''
