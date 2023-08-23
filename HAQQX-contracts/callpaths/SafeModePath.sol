// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import './ColdPath.sol';

contract SafeModePath is ColdPath {

    function protocolCmd (bytes calldata cmd) override public {
        sudoCmd(cmd);
    }

    function userCmd (bytes calldata) override public payable {
        revert("Emergency Safe Mode");
    }

    function acceptHaqqProxyRole (address, uint16 slot) public pure override returns (bool) {
        return slot == HaqqSlots.SAFE_MODE_PROXY_PATH;
    }
}