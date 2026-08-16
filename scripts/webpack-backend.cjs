const path = require('path');

module.exports = {
  mode: 'production',
  target: 'node',
  entry: process.env.DRONEFLEET_BACKEND_ENTRY,
  output: {
    path: path.resolve(process.env.DRONEFLEET_BACKEND_OUTPUT),
    filename: 'server.js',
  },
};
