// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import '../libraries/Directives.sol';
import '../libraries/Encoding.sol';
import '../libraries/TokenFlow.sol';
import '../libraries/PriceGrid.sol';
import '../libraries/ProtocolCmd.sol';
import '../mixins/SettleLayer.sol';
import '../mixins/PoolRegistry.sol';
import '../mixins/MarketSequencer.sol';
import '../mixins/StorageLayout.sol';
import '../mixins/ProtocolAccount.sol';
import '../mixins/DepositDesk.sol';
import '../interfaces/IHaqqMinion.sol';
import '../HaqqEvents.sol';

contract ColdPath is MarketSequencer, DepositDesk, ProtocolAccount {
    using SafeCast for uint128;
    using TokenFlow for TokenFlow.PairSeq;
    using CurveMath for CurveMath.CurveState;
    using Chaining for Chaining.PairFlow;
    using ProtocolCmd for bytes;

    function acceptHaqqProxyRole (address, uint16 slot) public virtual returns (bool) {
        return slot == HaqqSlots.COLD_PROXY_IDX;
    }

    function userCmd (bytes calldata cmd) virtual public payable {
        uint8 cmdCode = uint8(cmd[31]);
        
        if (cmdCode == UserCmd.INIT_POOL_CODE) {
            initPool(cmd);
        } else if (cmdCode == UserCmd.APPROVE_ROUTER_CODE) {
            approveRouter(cmd);
        } else if (cmdCode == UserCmd.DEPOSIT_SURPLUS_CODE) {
            depositSurplus(cmd);
        } else if (cmdCode == UserCmd.DEPOSIT_PERMIT_CODE) {
            depositPermit(cmd);
        } else if (cmdCode == UserCmd.DISBURSE_SURPLUS_CODE) {
            disburseSurplus(cmd);
        } else if (cmdCode == UserCmd.TRANSFER_SURPLUS_CODE) {
            transferSurplus(cmd);
        } else if (cmdCode == UserCmd.SIDE_POCKET_CODE) {
            sidePocketSurplus(cmd);
        } else if (cmdCode == UserCmd.RESET_NONCE) {
            resetNonce(cmd);
        } else if (cmdCode == UserCmd.RESET_NONCE_COND) {
            resetNonceCond(cmd);
        } else if (cmdCode == UserCmd.GATE_ORACLE_COND) {
            checkGateOracle(cmd);
        } else {
            revert("Invalid command");
        }

    }
    
    function sudoCmd (bytes calldata cmd) internal {
        require(sudoMode_, "Sudo");
        uint8 cmdCode = uint8(cmd[31]);
        
        if (cmdCode == ProtocolCmd.COLLECT_TREASURY_CODE) {
            collectProtocol(cmd);
        } else if (cmdCode == ProtocolCmd.SET_TREASURY_CODE) {
            setTreasury(cmd);
        } else if (cmdCode == ProtocolCmd.AUTHORITY_TRANSFER_CODE) {
            transferAuthority(cmd);
        } else if (cmdCode == ProtocolCmd.HOT_OPEN_CODE) {
            setHotPathOpen(cmd);
        } else if (cmdCode == ProtocolCmd.SAFE_MODE_CODE) {
            setSafeMode(cmd);
        } else {
            revert("Invalid command");
        }
    }

    function protocolCmd (bytes calldata cmd) virtual public {
        uint8 code = uint8(cmd[31]);

        if (code == ProtocolCmd.DISABLE_TEMPLATE_CODE) {
            disableTemplate(cmd);
        } else if (code == ProtocolCmd.POOL_TEMPLATE_CODE) {
            setTemplate(cmd);
        } else if (code == ProtocolCmd.POOL_REVISE_CODE) {
            revisePool(cmd);
        } else if (code == ProtocolCmd.SET_TAKE_CODE) {
            setTakeRate(cmd);
        } else if (code == ProtocolCmd.RELAYER_TAKE_CODE) {
            setRelayerTakeRate(cmd);
        } else if (code == ProtocolCmd.RESYNC_TAKE_CODE) {
            resyncTakeRate(cmd);
        } else if (code == ProtocolCmd.INIT_POOL_LIQ_CODE) {
            setNewPoolLiq(cmd);
        } else if (code == ProtocolCmd.OFF_GRID_CODE) {
            pegPriceImprove(cmd);
        } else {
            sudoCmd(cmd);
        }
    }
    
    function initPool (bytes calldata cmd) private {
        (, address base, address quote, uint256 poolIdx, uint128 price) =
            abi.decode(cmd, (uint8, address,address,uint256,uint128));

        (PoolSpecs.PoolCursor memory pool, uint128 initLiq) =
            registerPool(base, quote, poolIdx);
                                                   
        verifyPermitInit(pool, base, quote, poolIdx);
        
        (int128 baseFlow, int128 quoteFlow) = initCurve(pool, price, initLiq);
        settleInitFlow(lockHolder_, base, baseFlow, quote, quoteFlow);
    }

    function disableTemplate (bytes calldata input) private {
        (, uint256 poolIdx) = abi.decode(input, (uint8, uint256));
        emit HaqqEvents.DisablePoolTemplate(poolIdx);
        disablePoolTemplate(poolIdx);
    }
    
    function setTemplate (bytes calldata input) private {
        (, uint256 poolIdx, uint16 feeRate, uint16 tickSize, uint8 jitThresh,
         uint8 knockout, uint8 oracleFlags) =
            abi.decode(input, (uint8, uint256, uint16, uint16, uint8, uint8, uint8));
        
        emit HaqqEvents.SetPoolTemplate(poolIdx, feeRate, tickSize, jitThresh, knockout,
                                        oracleFlags);
        setPoolTemplate(poolIdx, feeRate, tickSize, jitThresh, knockout, oracleFlags);
    }

    function setTakeRate (bytes calldata input) private {
        (, uint8 takeRate) = 
            abi.decode(input, (uint8, uint8));
        
        emit HaqqEvents.SetTakeRate(takeRate);
        setProtocolTakeRate(takeRate);
    }

    function setRelayerTakeRate (bytes calldata input) private {
        (, uint8 takeRate) = 
            abi.decode(input, (uint8, uint8));

        emit HaqqEvents.SetRelayerTakeRate(takeRate);
        setRelayerTakeRate(takeRate);
    }

    function setNewPoolLiq (bytes calldata input) private {
        (, uint128 liq) = 
            abi.decode(input, (uint8, uint128));
        
        emit HaqqEvents.SetNewPoolLiq(liq);
        setNewPoolLiq(liq);
    }

    function resyncTakeRate (bytes calldata input) private {
        (, address base, address quote, uint256 poolIdx) = 
            abi.decode(input, (uint8, address, address, uint256));
        
        emit HaqqEvents.ResyncTakeRate(base, quote, poolIdx, protocolTakeRate_);
        resyncProtocolTake(base, quote, poolIdx);
    }

    function revisePool (bytes calldata cmd) private {
        (, address base, address quote, uint256 poolIdx,
         uint16 feeRate, uint16 tickSize, uint8 jitThresh, uint8 knockout) =
            abi.decode(cmd, (uint8,address,address,uint256,uint16,uint16,uint8,uint8));
        setPoolSpecs(base, quote, poolIdx, feeRate, tickSize, jitThresh, knockout);
    }

    function pegPriceImprove (bytes calldata cmd) private {
        (, address token, uint128 unitTickCollateral, uint16 awayTickTol) =
            abi.decode(cmd, (uint8, address, uint128, uint16));
        emit HaqqEvents.PriceImproveThresh(token, unitTickCollateral, awayTickTol);
        setPriceImprove(token, unitTickCollateral, awayTickTol);
    }

    function setHotPathOpen (bytes calldata cmd) private {
        (, bool open) = abi.decode(cmd, (uint8, bool));
        emit HaqqEvents.HotPathOpen(open);
        hotPathOpen_ = open;        
    }

    function setSafeMode (bytes calldata cmd) private {
        (, bool inSafeMode) = abi.decode(cmd, (uint8, bool));
        emit HaqqEvents.SafeMode(inSafeMode);
        inSafeMode_ = inSafeMode;        
    }

    function collectProtocol (bytes calldata cmd) private {
        (, address token) = abi.decode(cmd, (uint8, address));

        require(block.timestamp >= treasuryStartTime_, "Treasury start");
        emit HaqqEvents.ProtocolDividend(token, treasury_);
        disburseProtocolFees(treasury_, token);
    }

    function setTreasury (bytes calldata cmd) private {
        (, address treasury) = abi.decode(cmd, (uint8, address));

        require(treasury != address(0) && treasury.code.length != 0, "Treasury invalid");
        treasury_ = treasury;
        treasuryStartTime_ = uint64(block.timestamp + 7 days);
        emit HaqqEvents.TreasurySet(treasury_, treasuryStartTime_);
    }

    function transferAuthority (bytes calldata cmd) private {
        (, address auth) =
            abi.decode(cmd, (uint8, address));

        require(auth != address(0) && auth.code.length > 0 && 
            IHaqqMaster(auth).acceptsHaqqAuthority(), "Invalid Authority");
        
        emit HaqqEvents.AuthorityTransfer(authority_);
        authority_ = auth;
    }

    function depositSurplus (bytes calldata cmd) private {
        (, address recv, uint128 value, address token) =
            abi.decode(cmd, (uint8, address, uint128, address));
        depositSurplus(recv, value, token);
    }

    function depositPermit (bytes calldata cmd) private {
        (, address recv, uint128 value, address token, uint256 deadline,
         uint8 v, bytes32 r, bytes32 s) =
            abi.decode(cmd, (uint8, address, uint128, address, uint256,
                             uint8, bytes32, bytes32));
        depositSurplusPermit(recv, value, token, deadline, v, r, s);
    }

    function disburseSurplus (bytes calldata cmd) private {
        (, address recv, int128 value, address token) =
            abi.decode(cmd, (uint8, address, int128, address));
        disburseSurplus(recv, value, token);
    }

    function transferSurplus (bytes calldata cmd) private {
        (, address recv, int128 size, address token) =
            abi.decode(cmd, (uint8, address, int128, address));
        transferSurplus(recv, size, token);
    }

    function sidePocketSurplus (bytes calldata cmd) private {
        (, uint256 fromSalt, uint256 toSalt, int128 value, address token) =
            abi.decode(cmd, (uint8, uint256, uint256, int128, address));
        sidePocketSurplus(fromSalt, toSalt, value, token);
    }

    function resetNonce (bytes calldata cmd) private {
        (, bytes32 salt, uint32 nonce) = 
            abi.decode(cmd, (uint8, bytes32, uint32));
        resetNonce(salt, nonce);
    }
    
    function resetNonceCond (bytes calldata cmd) private {
        (, bytes32 salt, uint32 nonce, address oracle, bytes memory args) = 
            abi.decode(cmd, (uint8,bytes32,uint32,address,bytes));
        resetNonceCond(salt, nonce, oracle, args);
    }

    function checkGateOracle (bytes calldata cmd) private {
        (, address oracle, bytes memory args) = 
            abi.decode(cmd, (uint8,address,bytes));
        checkGateOracle(oracle, args);
    }

    function approveRouter (bytes calldata cmd) private {
        (, address router, uint32 nCalls, uint16[] memory callpaths) =
            abi.decode(cmd, (uint8, address, uint32, uint16[]));

        for (uint i = 0; i < callpaths.length; ++i) {
            require(callpaths[i] != HaqqSlots.COLD_PROXY_IDX, "Invalid Router Approve");
            approveAgent(router, nCalls, callpaths[i]);
        }
    }

}

