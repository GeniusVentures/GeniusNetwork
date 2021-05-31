pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT
/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GNUSToken is Ownable, ERC20 {
    // modify token name
    string public constant NAME = "Genius Tokens";
    // modify token symbol
    string public constant SYMBOL = "GNUS";
    // modify token decimal
    uint8 public constant DECIMALS = 18;
    // modify initial token supply
    uint256 public constant INIT_SUPPLY = 5000000 * (10**uint256(DECIMALS)); // 5 million tokens
    uint256 public constant MAX_SUPPLY = 50000000 * (10**uint256(DECIMALS)); // 50 million tokens
    
    mapping (address => bool) _minters;
    mapping (address => bool) _burners;

    function isMinter(address account) public view returns(bool) {
        return _minters[account];
    }

    function addMinter(address account) public onlyOwner {
        _minters[account] = true;
    }

    function removeMinter(address account) public onlyOwner {
        _minters[account] = false;
    }

    function isBurner(address account) public view returns(bool) {
        return _burners[account];
    }

    function addBurner(address account) public onlyOwner {
        _burners[account] = true;
    }

    function removeBurner(address account) public onlyOwner {
        _burners[account] = false;
    }

    constructor() ERC20(NAME, SYMBOL) {
        _mint(msg.sender, INIT_SUPPLY);
    }

    function mint(uint256 amount) public {
        require(isMinter(msg.sender), "You are not registered as a minter");
        uint256 current_supply = IERC20(address(this)).balanceOf(address(this));
        require(ERC20.totalSupply() + amount <= current_supply, "ERC20Capped: cap exceeded");
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) public {
        require(isBurner(msg.sender), "You are not registered as a burner");
        _burn(msg.sender, amount);
    }
}