// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import "../interfaces/IHaqqXCondOracle.sol";

contract MockProxySidecar {

    uint16 public proxySlot_;
    address public proxyDex_;

    function setRole (uint16 slot, address proxyDex) public {
        proxySlot_ = slot;
        proxyDex_ = proxyDex;
    }

    /* @notice Used at upgrade time to verify that the contract is a valid HaqqX sidecar proxy and used
     *         in the correct slot. */
    function acceptHaqqXProxyRole (address dex, uint16 slot) public payable returns (bool) {
        return (proxyDex_ == address(0)) ||
            (proxySlot_ == slot && proxyDex_ == dex);
    }
}

