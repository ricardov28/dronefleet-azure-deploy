const { app } = require('@azure/functions');
const { persistFlightSummary } = require('../lib/cosmosWriter');
const { parseTelemetry } = require('../lib/parseTelemetry');
const { sendToGroup } = require('../lib/webPubSubSender');

app.eventHub('forwardIotHubToWebPubSub', {
  connection: 'IotHubEventHubConnection',
  consumerGroup: '%IotHubConsumerGroup%',
  eventHubName: process.env.IotHubEventHubName,
  cardinality: 'many',
  handler: async (events, context) => {
    const baseGroup = process.env.WebPubSubGroup || 'attitude';
    const source = process.env.IotHubSourceName || 'iothub';
    const systemProperties = context.triggerMetadata?.systemPropertiesArray || [];

    for (let index = 0; index < events.length; index++) {
      const parsed = parseTelemetry(events[index]);
      const telemetry = parsed?.telemetry;
      const deviceId =
        systemProperties[index]?.['iothub-connection-device-id'] ||
        (telemetry && typeof telemetry === 'object' && telemetry.deviceId) ||
        parsed.origin ||
        'unknown';

      if (telemetry && typeof telemetry === 'object') telemetry.deviceId = deviceId;

      if (telemetry?.messageType === 'flightSummary') {
        await persistFlightSummary(deviceId, telemetry);
      }

      await sendToGroup(`${baseGroup}-${deviceId}`, {
        receivedAt: new Date().toISOString(),
        source,
        deviceId,
        ...parsed
      });
    }

    context.log(`Forwarded ${events.length} event(s) to '${baseGroup}-<deviceId>'.`);
  }
});