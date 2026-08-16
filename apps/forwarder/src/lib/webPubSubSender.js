const { DefaultAzureCredential } = require('@azure/identity');
const { WebPubSubServiceClient } = require('@azure/web-pubsub');

let cachedClient = null;

function getClient() {
  if (cachedClient) return cachedClient;

  const hub = process.env.WebPubSubHub;
  if (!hub) throw new Error('Missing WebPubSubHub.');

  const endpoint = process.env.WebPubSubEndpoint;
  if (endpoint) {
    cachedClient = new WebPubSubServiceClient(endpoint, new DefaultAzureCredential(), hub);
    return cachedClient;
  }

  const connectionString = process.env.WebPubSubConnectionString;
  if (!connectionString) {
    throw new Error('Set WebPubSubEndpoint for managed identity or WebPubSubConnectionString for local development.');
  }

  cachedClient = new WebPubSubServiceClient(connectionString, hub);
  return cachedClient;
}

async function sendToGroup(group, payload) {
  if (!group) throw new Error('Group is required.');
  await getClient().group(group).sendToAll(payload, { contentType: 'application/json' });
}

module.exports = { sendToGroup };