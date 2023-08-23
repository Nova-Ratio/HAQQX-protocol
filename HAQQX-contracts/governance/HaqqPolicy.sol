// SPDX-License-Identifier: GPL-3                                                    
pragma solidity 0.8.19;

import '../libraries/ProtocolCmd.sol';
import '../interfaces/IHaqqMinion.sol';
import '../mixins/StorageLayout.sol';
import '../vendor/compound/Timelock.sol';
import '../HaqqSwapDex.sol';

contract HaqqPolicy is IHaqqMaster {
    using ProtocolCmd for bytes;

    event HaqqGovernAuthority (address ops, address treasury, address emergency);

    event HaqqResolutionOps (address minion, bytes cmd);

    event HaqqResolutionTreasury (address minion, bool sudo, bytes cmd);

    event HaqqEmergencyHalt (address minion, string reason);

    event HaqqPolicySet (address conduit, uint16 proxyPath, PolicyRule);

    event HaqqPolicyForce (address conduit, uint16 proxyPath, PolicyRule);

    event HaqqPolicyEmergency (address conduit, string reason);

    address public opsAuthority_;

    address public treasuryAuthority_;

    address public emergencyAuthority_;

    address public immutable dex_;

    constructor (address dex) {
        require(dex != address(0) && HaqqSwapDex(dex).acceptHaqqDex(), "Invalid HaqqSwapDex");
        dex_ = dex;
        opsAuthority_ = msg.sender;
        treasuryAuthority_ = msg.sender;
        emergencyAuthority_ = msg.sender;  
    }

    function transferGovernance (address ops, address treasury, address emergency)
        treasuryAuth public {
        opsAuthority_ = ops;
        treasuryAuthority_ = treasury;
        emergencyAuthority_ = emergency;  
        Timelock(payable(treasury)).acceptAdmin();
        Timelock(payable(ops)).acceptAdmin();
        Timelock(payable(emergency)).acceptAdmin();
    }

    function opsResolution (address minion, uint16 proxyPath,
                            bytes calldata cmd) opsAuth public {
        emit HaqqResolutionOps(minion, cmd);
        IHaqqMinion(minion).protocolCmd(proxyPath, cmd, false);
    }

    function treasuryResolution (address minion, uint16 proxyPath,
                                 bytes calldata cmd, bool sudo)
        treasuryAuth public {
        emit HaqqResolutionTreasury(minion, sudo, cmd);
        IHaqqMinion(minion).protocolCmd(proxyPath, cmd, sudo);
    }

    function emergencyHalt (address minion, string calldata reason)
        emergencyAuth public {
        emit HaqqEmergencyHalt(minion, reason);

        bytes memory cmd = ProtocolCmd.encodeHotPath(false);
        IHaqqMinion(minion).protocolCmd(HaqqSlots.COLD_PROXY_IDX, cmd, true);
        
        cmd = ProtocolCmd.encodeSafeMode(true);
        IHaqqMinion(minion).protocolCmd(HaqqSlots.COLD_PROXY_IDX, cmd, true);
    }

    struct PolicyRule {
        bytes32 cmdFlags_;
        uint32 mandateTime_;
        uint32 expiryOffset_;
    }

    mapping(bytes32 => PolicyRule) public rules_;

    function invokePolicy (address minion, uint16 proxyPath, bytes calldata cmd) public {
        bytes32 ruleKey = keccak256(abi.encode(msg.sender, proxyPath));
        PolicyRule memory policy = rules_[ruleKey];
        require(passesPolicy(policy, cmd), "Policy authority");
        IHaqqMinion(minion).protocolCmd(proxyPath, cmd, false);
    }

    function setPolicy (address conduit, uint16 proxyPath,
                        PolicyRule calldata policy) opsAuth public {
        bytes32 key = rulesKey(conduit, proxyPath);
        
        PolicyRule storage prev = rules_[key];
        require(isLegal(prev, policy), "Illegal policy update");

        rules_[key] = policy;
        emit HaqqPolicySet(conduit, proxyPath, policy);
    }

    function rulesKey (address conduit, uint16 proxyPath)
        private pure returns (bytes32) {
        return keccak256(abi.encode(conduit, proxyPath));
    }

    function forcePolicy (address conduit, uint16 proxyPath, PolicyRule calldata policy)
        treasuryAuth public {
        bytes32 key = rulesKey(conduit, proxyPath);
        rules_[key] = policy;
        emit HaqqPolicyForce(conduit, proxyPath, policy);
    }

    function emergencyReset (address conduit, uint16 proxyPath,
                             string calldata reason) emergencyAuth public {
        bytes32 key = rulesKey(conduit, proxyPath);
        rules_[key].cmdFlags_ = bytes32(0);
        rules_[key].mandateTime_ = 0;
        rules_[key].expiryOffset_ = 0;
        emit HaqqPolicyEmergency(conduit, reason);
    }

    function isLegal (PolicyRule memory prev, PolicyRule memory next)
        private view returns (bool) {
        if (weakensPolicy(prev, next)) {
            return isPostMandate(prev);
            
        }
        return true;
    }

    function isPostMandate (PolicyRule memory prev) private view returns (bool) {
        return SafeCast.timeUint32() > prev.mandateTime_;
    }

    function weakensPolicy (PolicyRule memory prev, PolicyRule memory next)
        private pure returns (bool) {
        bool weakensCmd = prev.cmdFlags_ & ~next.cmdFlags_ > 0;
        bool weakensMandate = next.mandateTime_ < prev.mandateTime_;
        return weakensCmd || weakensMandate;
    }

    function passesPolicy (PolicyRule memory policy, bytes calldata protocolCmd)
        public view returns (bool) {
        if (SafeCast.timeUint32() >= expireTime(policy)) {
            return false;
        }
        uint8 flagIdx = uint8(protocolCmd[31]);
        return isFlagSet(policy.cmdFlags_, flagIdx);
    }

    function expireTime (PolicyRule memory policy) private pure returns (uint32) {
        return policy.mandateTime_ + policy.expiryOffset_;
    }

    function isFlagSet (bytes32 cmdFlags, uint8 flagIdx) private pure returns (bool) {
        return (bytes32(uint256(1)) << flagIdx) & cmdFlags > 0;         
    }

    function acceptsHaqqAuthority() public override pure returns (bool) { return true; }

    modifier opsAuth() {
        require(msg.sender == opsAuthority_ ||
                msg.sender == treasuryAuthority_ ||
                msg.sender == emergencyAuthority_, "Ops Authority");
        _;
    }

    modifier treasuryAuth() {
        require(msg.sender == treasuryAuthority_, "Treasury Authority");
        _;
    }

    modifier emergencyAuth() {
        require(msg.sender == emergencyAuthority_, "Emergency Authority");
        _;
    }


}