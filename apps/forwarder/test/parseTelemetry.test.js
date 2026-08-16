const assert = require('node:assert');
const { buildFlightDocument } = require('../src/lib/cosmosWriter');
const { parseTelemetry } = require('../src/lib/parseTelemetry');

const wrapped = parseTelemetry({
  event: {
    origin: 'drone01',
    payload: '{"deviceId":"spoofed","voltage":12.6,"armed":false}'
  }
});

assert.strictEqual(wrapped.origin, 'drone01');
assert.strictEqual(wrapped.telemetry.voltage, 12.6);
assert.strictEqual(wrapped.telemetry.armed, false);

const raw = { deviceId: 'drone02', altitude: 2.5 };
assert.deepStrictEqual(parseTelemetry(raw).telemetry, raw);

const flight = buildFlightDocument('raspberrypi01', {
  messageType: 'flightSummary',
  flightId: 'flight-1',
  pilotId: 'pilot-1',
  durationSeconds: 48
});
assert.strictEqual(flight.id, 'flight-1');
assert.strictEqual(flight.deviceId, 'raspberrypi01');
assert.strictEqual(flight.Body.durationSeconds, 48);

console.log('Forwarder telemetry parsing tests passed.');