// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author maheshbsl
 * @dev  This is a contract meant to be governed by DSCEngine. This contract is just the ERC20 token
 * @dev  that will be minted when the user deposits collateral. The contract will be governed by the DSCEngine.
 *
 * @dev  Collateral is deposited in the DSCEngine contract. The DSCEngine contract will mint the stablecoin
 * @dev  and send it to the user. The DSCEngine contract will also keep track of the collateral and the stablecoin
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    // errors
    error DecentralizedStableCoin__MustBeGreaterThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        require(amount > 0, DecentralizedStableCoin__MustBeGreaterThanZero());
        require(amount <= balance, DecentralizedStableCoin__BurnAmountExceedsBalance());
        super.burn(amount);
    }

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        require(amount > 0, DecentralizedStableCoin__MustBeGreaterThanZero());
        require(to != address(0), DecentralizedStableCoin__NotZeroAddress());
        _mint(to, amount);
        return true;
    }
}
