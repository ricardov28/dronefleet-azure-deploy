const { WebPubSubServiceClient } = require('@azure/web-pubsub');
const WebSocket = require('ws');

const connectionString = process.env.WEB_PUBSUB_CONNECTION_STRING;
const hub = process.env.WEB_PUBSUB_HUB || 'dronefleet';
const group = process.env.WEB_PUBSUB_GROUP;
const marker = process.env.WEB_PUBSUB_EXPECTED_MARKER;

if (!connectionString || !group || !marker) {
  throw new Error('WEB_PUBSUB_CONNECTION_STRING, WEB_PUBSUB_GROUP, and WEB_PUBSUB_EXPECTED_MARKER are required.');
}

async function main() {
  const service = new WebPubSubServiceClient(connectionString, hub);
  const token = await service.getClientAccessToken({
    groups: [group],
    expirationTimeInMinutes: 10,
  });
  const socket = new WebSocket(token.url, 'json.webpubsub.azure.v1');
  const timeout = setTimeout(() => {
    console.error(`TIMEOUT marker=${marker}`);
    socket.close();
    process.exitCode = 2;
  }, 240000);

  socket.on('open', () => console.log(`READY group=${group} marker=${marker}`));
  socket.on('message', (data) => {
    const text = data.toString();
    if (text.includes(marker)) {
      clearTimeout(timeout);
      console.log(`RECEIVED group=${group} marker=${marker}`);
      socket.close();
    }
  });
  socket.on('error', (error) => {
    clearTimeout(timeout);
    console.error(`ERROR ${error.message}`);
    process.exitCode = 1;
  });
}

main().catch((error) => {
  console.error(`ERROR ${error.message}`);
  process.exitCode = 1;
});
