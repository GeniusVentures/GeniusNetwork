const ICOContract = artifacts.require('ICOContract');

module.exports = async function (deployer, network, accounts) {
    let _gnusTokenAddress = "0x75D9E8790128eb333A2632f8cd7C631d3c03564a";
    let _initLimits = [12500, 12500, 12500, 12500];
    let _initRates = [1000, 800, 640, 512];
    await deployer.deploy(ICOContract, _gnusTokenAddress, _initLimits, _initRates);
};