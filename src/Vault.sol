// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    // We need to pass the token address to the constructor
    // Create a deposit function that mints tokens to the user equal to the amount of ETH deposited
    // Create a burn function that burns tokens to the user and sends the user ETH
    // Create a way to add rewards to the vault

    event Deposit(address indexed sender, uint256 value);
    event Redeem(address indexed sender, uint256 value);

    error Vault__RedeemFailed();

    IRebaseToken private immutable i_rebaseToken;

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @notice Allows users to deposit and mint rebase tokens in return.
     */
    function deposit() external payable {
        // 1. We need to use the amount of ETH the user has sent to mint tokens to the user.
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Allows users to redeem their rebase tokens for ETH
     * @param _amount The amount of rebase tokens to redeem
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // 1. Burn tokens from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // 2. Send the user ETH
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @notice Get the address of the rebase token
     * @return The address of the rebase token
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
