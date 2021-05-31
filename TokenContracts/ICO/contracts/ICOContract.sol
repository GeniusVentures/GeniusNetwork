// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Math.sol";
import "./SafeMath.sol";

contract ICOContract is Ownable {

    IERC20 private gnusToken;
    address public gnusAddress;
    uint256 public gnusSoldAmount;

    uint256[] public limits;
    uint256[] public rates;

    constructor (address _gnusTokenAddress, uint256[] memory _initLimits, uint256[] memory _initRates) {
        // import GNUS token contract and define the balance
        gnusAddress = _gnusTokenAddress;
        gnusToken = IERC20(_gnusTokenAddress);
        gnusSoldAmount = 0;

        // init convTable
        limits = _initLimits;  // amount of eth
        rates = _initRates;  // amount of gnus token for 1 eth
    }

    function gnusBalance() public view returns(uint256) {
        return gnusToken.balanceOf(address(this));
    }

    function ethBalance() public view returns(uint256) {
        return address(this).balance;
    }

    function defineStep() public view returns(uint256) {
        uint256 step = 0;
        for (uint256 i = 0; i < limits.length - 1; i++) {
            if (limits[i] * rates[i] > gnusSoldAmount) {
                step = i;
                break;
            }
        }
        return step;
    }

    /**
    e.g. [[12500, 1000], [12500, 800], [12500, 640], [12500, 512]]
    limits = [12500, 12500, 12500, 12500]
    rates = [1000, 800, 640, 512]
    */ 
    function dynamicConvTable(uint256[][] memory convTable) external onlyOwner {
        require(convTable.length > 0, "Invalid data");
        for (uint256 i = 0; i < convTable.length; i++) {
            require(convTable[i].length == 2 && convTable[i][0] > 0 && convTable[i][1] > 0, "Invalid data item");
        }
        for (uint256 j = 0; j < convTable.length; j++) {
            limits[j] = convTable[j][0];
            rates[j] = convTable[j][1];
        }
    }

    // owner can withdraw eth to any address
    function withdrawETH(address _address, uint _amount) external onlyOwner {
        require(_amount * 10 ** 18 < ethBalance(), "Not enough eth balance");
        address payable to = payable(_address);
        to.transfer(_amount * 10 ** 18);
    }

    // Detect receiving eth
    receive () external payable {
        // Check gnus token before receive eth
        require(msg.value > 0, "You have sent 0 ether!");
        uint256 step = defineStep();
        uint256 tokenAmount = msg.value * rates[step];
        require(gnusBalance() >= tokenAmount, "You have sent too much eth amount");
        gnusToken.transfer(address(msg.sender), tokenAmount);
    }

    // Withdraw GNUS tokens
    function withdrawGNUS(address to, uint amount) external onlyOwner {
        require(to == address(to),"Invalid address");
        uint256 tokenAmount = amount * 10 ** 18;
        require(gnusBalance() >= tokenAmount, "You have sent too much eth amount");
        gnusToken.transfer(address(to), tokenAmount);
    }
}
