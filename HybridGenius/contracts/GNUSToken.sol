pragma solidity ^0.5.0;

import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";        // set specific function for owner only



/**
 * @title GNUSToken
 * @dev Very simple ERC777 Token example, where all tokens are pre-assigned to the creator.
 * Note they can later distribute these tokens as they wish using `transfer` and other
 * `ERC20` or `ERC777` functions.
 * Based on https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/examples/SimpleToken.sol
 */
contract GNUSToken is ERC777, Ownable {

    /**
     * @dev Constructor that gives msg.sender all of existing tokens.
     */
    constructor () public ERC777("Genius Token", "GNUS", new address[](0)) {
        _mint(msg.sender, msg.sender, 250000000 * 10 ** 18, "", "");
    }
    function Mint(uint amount) external onlyOwner returns(bool){
        _mint(msg.sender, msg.sender, amount, "", "");
    }
}