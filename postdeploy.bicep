targetScope = 'resourceGroup'

@description('Name of the Azure Communication Services resource created by main.bicep.')
param acsName string

@secure()
@description('Complete HTTPS /filestatus webhook URL. Event Grid treats webhook endpoints as sensitive.')
param webhookEndpoint string

resource acs 'Microsoft.Communication/communicationServices@2023-04-01' existing = {
  name: acsName
}

// Event Grid validates this webhook during creation, so deploy-code.ps1 applies
// this template only after the Express backend and /filestatus endpoint are live.
resource recordingStatusSubscription 'Microsoft.EventGrid/eventSubscriptions@2025-02-15' = {
  name: 'acs-recording-file-status'
  scope: acs
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: webhookEndpoint
        minimumTlsVersionAllowed: '1.2'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    eventDeliverySchema: 'EventGridSchema'
    filter: {
      includedEventTypes: [
        'Microsoft.Communication.RecordingFileStatusUpdated'
      ]
      isSubjectCaseSensitive: false
    }
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
  }
}

output eventSubscriptionName string = recordingStatusSubscription.name
