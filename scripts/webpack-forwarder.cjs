const path = require('path');

module.exports = {
  mode: 'production',
  target: 'node',
  entry: process.env.DRONEFLEET_FORWARDER_ENTRY,
  output: {
    path: path.resolve(process.env.DRONEFLEET_FORWARDER_OUTPUT),
    filename: 'index.js',
  },
  externals: {
    '@azure/functions': 'commonjs @azure/functions',
    '@azure/functions-core': 'commonjs @azure/functions-core',
  },
  resolve: {
    modules: process.env.DRONEFLEET_FORWARDER_MODULES.split(path.delimiter),
  },
};
