require('dotenv').config();

const HDWalletProvider = require('truffle-hdwallet-provider');
const privateKey = process.env.privateKey;
const infuraKey = process.env.infuraKey
module.exports = {
  api_keys: {
    etherscan: process.env.etherKey
  },
  networks: {
    ganache: {
      host: '127.0.0.1', // Localhost (default: none)
      port: 7545, // Standard Ethereum port (default: none)
      network_id: '*', // eslint-disable-line camelcase
    },

    rinkeby: {
      provider: function () {
        let privateKeys = [privateKey];
        return new HDWalletProvider(privateKeys, "https://rinkeby.infura.io/v3/" + infuraKey)
      },
      network_id: 4, // eslint-disable-line camelcase
      gas: 5500000, // Ropsten has a lower block limit than mainnet
      confirmations: 2, // # of confs to wait between deployments. (default: 0)
      timeoutBlocks: 200, // # of blocks before a deployment times out  (minimum/default: 50)
      skipDryRun: true, // Skip dry run before migrations? (default: false for public nets )
    }
  },
  compilers: {
    solc: {
      version: "0.8.0",
      settings: {
        optimizer: {
          enabled: true, // Default: false
          runs: 1000     // Default: 200
        },
        evmVersion: "istanbul"
      }
    }
  },
  plugins: [
    'truffle-plugin-verify'
  ]
};
