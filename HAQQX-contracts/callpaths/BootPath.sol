// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import '../libraries/ProtocolCmd.sol';
import '../mixins/StorageLayout.sol';
import '../HaqqEvents.sol';

contract BootPath is StorageLayout {
    using ProtocolCmd for bytes;

    function protocolCmd (bytes calldata cmd) virtual public {
        require(sudoMode_, "Sudo");
        
        uint8 cmdCode = uint8(cmd[31]);
        if (cmdCode == ProtocolCmd.UPGRADE_DEX_CODE) {
            upgradeProxy(cmd);
        } else {
            revert("Invalid command");
        }
    }
    
    function userCmd (bytes calldata) virtual public payable { 
        revert("Invalid command");
    }
    
    function upgradeProxy (bytes calldata cmd) private {
        (, address proxy, uint16 proxyIdx) =
            abi.decode(cmd, (uint8, address, uint16));

        require(proxyIdx != HaqqSlots.BOOT_PROXY_IDX, "Cannot overwrite boot path");
        require(proxy == address(0) || proxy.code.length > 0, "Proxy address is not a contract");

        emit HaqqEvents.UpgradeProxy(proxy, proxyIdx);
        proxyPaths_[proxyIdx] = proxy;        

        if (proxy != address(0)) {
            bool doesAccept = BootPath(proxy).acceptHaqqProxyRole(address(this), proxyIdx);
            require(doesAccept, "Proxy does not accept role");
        }
    }

    function acceptHaqqProxyRole (address, uint16) public pure virtual returns (bool) {
        return false;
    }
}

