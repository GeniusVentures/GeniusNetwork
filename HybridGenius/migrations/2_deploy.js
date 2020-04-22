const GNUSToken = artifacts.require('GNUSToken');
const GNUSRecipient = artifacts.require('GNUSRecipient');

require('@openzeppelin/test-helpers/configure')({ provider: web3.currentProvider, environment: 'truffle' });

const { singletons } = require('@openzeppelin/test-helpers');

module.exports = async function (deployer, network, accounts) {
  if (network === 'development') {
    // In a test environment an ERC777 token requires deploying an ERC1820 registry
    await singletons.ERC1820Registry(accounts[0]);
  }
  if (network === 'ganache') {
    // In a test environment an ERC777 token requires deploying an ERC1820 registry
    await singletons.ERC1820Registry(accounts[0]);
  }
  await deployer.deploy(GNUSToken);
  const token = await GNUSToken.deployed();

  await deployer.deploy(GNUSRecipient, token.address);
};
