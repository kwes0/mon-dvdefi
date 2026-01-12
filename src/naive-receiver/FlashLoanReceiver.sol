// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {WETH, NaiveReceiverPool} from "./NaiveReceiverPool.sol";

/**
 * FlashLoanReceiver is deployed to make the call to the NaiveReceiver to get the loan. 
 * This is the contract that has been created by the user with 10 WETH!!!
 * onFlashLoan argument address hasn't defined who is making the call to NaiveReceiver therefore anyone can call it.
 *  This means anyone can call this and end up paying the fee to the feeReceiver. 
 *  We will use this to drain the balance as fee... request a loan 10 times to drain the user. 
 * 
 */

contract FlashLoanReceiver is IERC3156FlashBorrower {
    address private pool;

    constructor(address _pool) {
        pool = _pool;
    }
    //This address has to be the initiatiator - the one who called for the loan.
    function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        assembly {
            // gas savings
            if iszero(eq(sload(pool.slot), caller())) {
                mstore(0x00, 0x48f5c3ed)
                revert(0x1c, 0x04)
            }
        }

        if (token != address(NaiveReceiverPool(pool).weth())) revert NaiveReceiverPool.UnsupportedCurrency();

        uint256 amountToBeRepaid;
        unchecked {
            amountToBeRepaid = amount + fee;
        }

        _executeActionDuringFlashLoan();// n If there was an arbitrage to be carried out in here. 

        // Return funds to pool
        WETH(payable(token)).approve(pool, amountToBeRepaid);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    // Internal function where the funds received would be used
    function _executeActionDuringFlashLoan() internal {}
}
