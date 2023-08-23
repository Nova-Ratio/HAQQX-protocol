// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import "../governance/HaqqXPolicy.sol";
import "hardhat/console.sol";

contract MockTimelock {

    address public policy_;

    constructor (address policy) {
        policy_ = policy;
    }

    function acceptAdmin() public payable { 
        require(msg.sender == policy_);
    }

    function treasuryResolution (address minion, uint16 proxyPath,
                                 bytes calldata cmd, bool sudo) public {
        return HaqqXPolicy(policy_).treasuryResolution(minion, proxyPath, cmd, sudo);
    }

    function opsResolution (address minion, uint16 proxyPath,
                            bytes calldata cmd) public {
        return HaqqXPolicy(policy_).opsResolution(minion, proxyPath, cmd);
    }

    function transferGovernance (address treasury, address ops, address emergency) public {
        return HaqqXPolicy(policy_).transferGovernance(treasury, ops, emergency);
    }

    function emergencyHalt (address minion, string calldata reason) public {
        return HaqqXPolicy(policy_).emergencyHalt(minion, reason);
    }

    function emergencyReset (address conduit, uint16 proxyPath, string calldata reason) public {
        return HaqqXPolicy(policy_).emergencyReset(conduit, proxyPath, reason);
    }

    function forcePolicy (address conduit, uint16 proxyPath, HaqqXPolicy.PolicyRule calldata policy) public {
        return HaqqXPolicy(policy_).forcePolicy(conduit, proxyPath, policy);
    }

    function setPolicy (address conduit, uint16 proxyPath, HaqqXPolicy.PolicyRule calldata policy) public {
        return HaqqXPolicy(policy_).setPolicy(conduit, proxyPath, policy);
    }

}
