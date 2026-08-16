let cachedContainer = null;

function buildFlightDocument(deviceId, telemetry) {
  if (!deviceId) throw new Error('deviceId is required for a flight summary.');
  if (!telemetry || telemetry.messageType !== 'flightSummary') {
    throw new Error('A flightSummary telemetry object is required.');
  }

  const id = String(telemetry.flightId || `${deviceId}-${telemetry.endedAt || Date.now()}`);
  return {
    id,
    deviceId,
    Body: {
      ...telemetry,
      deviceId,
      flightId: id
    },
    persistedAt: new Date().toISOString()
  };
}

function getContainer() {
  if (cachedContainer) return cachedContainer;

  const endpoint = process.env.CosmosEndpoint;
  if (!endpoint) throw new Error('Missing CosmosEndpoint for flight summary persistence.');

  const { CosmosClient } = require('@azure/cosmos');
  const { DefaultAzureCredential } = require('@azure/identity');
  const database = process.env.CosmosDatabase || 'droneOps';
  const container = process.env.CosmosFlightsContainer || 'flights';
  const client = new CosmosClient({ endpoint, aadCredentials: new DefaultAzureCredential() });
  cachedContainer = client.database(database).container(container);
  return cachedContainer;
}

async function persistFlightSummary(deviceId, telemetry) {
  const document = buildFlightDocument(deviceId, telemetry);
  await getContainer().items.upsert(document);
  return document;
}

module.exports = { buildFlightDocument, persistFlightSummary };
