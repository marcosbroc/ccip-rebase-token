// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Vault} from "../src/Vault.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToTheVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
        console.log("Rewards added: ", success);
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e4, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        // 1. Deposit
        vault.deposit{value: amount}();
        // 2. Check initial balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("Start balance: ", startBalance);
        assertEq(startBalance, amount);
        // 3. Warp and check balance increase period 1
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);
        // 4. Wait and Check balance increase period 2
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);
        // 5. Assert period 1 increase is equal to period 2 increase
        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
    }

    function testRedeemStraightaway(uint256 amount) public {
        // 1. Deposit
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);
        // 2. Redeem
        vault.redeem(amount);
        assertEq(rebaseToken.balanceOf(user), 0);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        // 1. Deposit
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        // 2. Warp the time
        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);

        // 2b. Add rewards
        vm.prank(owner);
        vm.deal(owner, balanceAfterSomeTime - depositAmount);
        addRewardsToTheVault(balanceAfterSomeTime - depositAmount);

        // 3. Redeem
        vm.prank(user);
        vault.redeem(type(uint256).max);

        // 4. Checks
        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        // 1. Deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");

        uint256 userBalanceBeforeTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceBeforeTransfer = rebaseToken.balanceOf(user2);
        console.log("USER 1 BEFORE: ", userBalanceBeforeTransfer);
        console.log("USER 2 BEFORE: ", user2BalanceBeforeTransfer);
        assertEq(userBalanceBeforeTransfer, amount);
        assertEq(user2BalanceBeforeTransfer, 0);

        // 2. Owner reduces interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // 3. Transfer
        vm.prank(user);
        bool success = rebaseToken.transfer(user2, amountToSend);
        if (!success) return;
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        console.log("USER 1 AFTER:  ", userBalanceBeforeTransfer);
        console.log("USER 2 AFTER: ", user2BalanceBeforeTransfer);
        assertEq(userBalanceAfterTransfer, userBalanceBeforeTransfer - amountToSend);
        assertEq(user2BalanceAfterTransfer, amountToSend);

        // 4. Check users interest rate has been inherited
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        uint256 user2InterestRate = rebaseToken.getUserInterestRate(user2);
        console.log("***** USER 1 INTEREST RATE %18e ", userInterestRate);
        console.log("***** USER 2 INTEREST RATE %18e ", user2InterestRate);
        assertEq(userInterestRate, user2InterestRate);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }

    /*
        function testCannotMintAndBurn(uint256 amount) public {
            amount = uint256(373000000);
            vm.prank(user);
            console.log("Testing amount:", amount);
            console.log("Sender:", user);
            console.log("Vault:", address(vault));
            vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
            rebaseToken.mint(user, amount, rebaseToken.getInterestRate());
            //vm.prank(user);
            //vm.expectRevert();
            //vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
            //rebaseToken.burn(user, amount);
        }
    */
    function testGetPrincipalBalance(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(user, amount);
        vm.prank(user);
        // Deposit
        vault.deposit{value: amount}();
        // Check principal
        assertEq(rebaseToken.principalBalanceOf(user), amount);
        // Three hours later it should still be the same
        vm.warp(block.timestamp + 3 hours);
        assertEq(rebaseToken.principalBalanceOf(user), amount);
    }

    function testGetRebaseTokenAddress() public view {
        address rebaseTokenAddress = vault.getRebaseTokenAddress();
        assertEq(rebaseTokenAddress, address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}
