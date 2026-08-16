function validateStartupConfig() {
  const connectionString = process.env.IotHubEventHubConnection;
  const namespace = process.env.IotHubEventHubConnection__fullyQualifiedNamespace;

  if (!connectionString && !namespace) {
    throw new Error(
      'Missing IoT Hub Event Hub trigger configuration. Set either ' +
        'IotHubEventHubConnection or IotHubEventHubConnection__fullyQualifiedNamespace.'
    );
  }

  if (connectionString && (/^HostName=/i.test(connectionString) || /\bDeviceId=/i.test(connectionString))) {
    throw new Error(
      'IotHubEventHubConnection is an IoT Hub device/service connection string. ' +
        'Use the Event Hub-compatible endpoint or the identity-based namespace settings.'
    );
  }

  if (!process.env.IotHubEventHubName) {
    throw new Error('Missing IotHubEventHubName. Set it to the IoT Hub built-in Event Hub-compatible path.');
  }
}

validateStartupConfig();
require('./functions/forwardIotHubToWebPubSub');