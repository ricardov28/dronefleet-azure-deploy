function tryParseJson(text) {
  if (typeof text !== 'string') return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function parseTelemetry(input) {
  const wrapper = input && typeof input === 'object' ? input : null;
  const event = wrapper?.event && typeof wrapper.event === 'object' ? wrapper.event : null;

  if (event && Object.prototype.hasOwnProperty.call(event, 'payload')) {
    return {
      origin: event.origin,
      event,
      telemetry: tryParseJson(event.payload) ?? event.payload
    };
  }

  return {
    origin: wrapper?.origin,
    event: wrapper,
    telemetry: wrapper
  };
}

module.exports = { parseTelemetry };