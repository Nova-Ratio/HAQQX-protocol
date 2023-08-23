// SPDX-License-Identifier: GPL-3 

pragma solidity 0.8.19;

/* @title Haqq conditional oracle interface
 * @notice Defines a generalized interface for checking an arbitrary condition. Used in
 *         an off-chain relayer context. User can gate specific order on a runtime 
 *         condition by calling to the oracle. */
interface IHaqqNonceOracle {

    function checkHaqqNonceSet (address user, bytes32 nonceSalt, uint32 nonce,
                                bytes calldata args) external returns (bool);
}

interface IHaqqCondOracle {
    function checkHaqqCond (address user, bytes calldata args) external returns (bool);
}
