// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import '../libraries/Directives.sol';
import '../libraries/Encoding.sol';
import '../libraries/TokenFlow.sol';
import '../libraries/PriceGrid.sol';
import '../libraries/ProtocolCmd.sol';
import '../mixins/MarketSequencer.sol';
import '../mixins/SettleLayer.sol';
import '../mixins/PoolRegistry.sol';
import '../mixins/MarketSequencer.sol';
import '../mixins/ProtocolAccount.sol';

contract WarmPath is MarketSequencer, SettleLayer, ProtocolAccount {

    using SafeCast for uint128;
    using TokenFlow for TokenFlow.PairSeq;
    using CurveMath for CurveMath.CurveState;
    using Chaining for Chaining.PairFlow;

    function userCmd (bytes calldata input) public payable returns
        (int128 baseFlow, int128 quoteFlow) {
        
        (uint8 code, address base, address quote, uint256 poolIdx,
         int24 bidTick, int24 askTick, uint128 liq,
         uint128 limitLower, uint128 limitHigher,
         uint8 reserveFlags, address lpConduit) =
            abi.decode(input, (uint8,address,address,uint256,int24,int24,
                               uint128,uint128,uint128,uint8,address));

        if (lpConduit == address(0)) { lpConduit = lockHolder_; }
        
        (baseFlow, quoteFlow) =
            commitLP(code, base, quote, poolIdx, bidTick, askTick,
                     liq, limitLower, limitHigher, lpConduit);
        settleFlows(base, quote, baseFlow, quoteFlow, reserveFlags);
    }

    
    function commitLP (uint8 code, address base, address quote, uint256 poolIdx,
                       int24 bidTick, int24 askTick, uint128 liq,
                       uint128 limitLower, uint128 limitHigher,
                       address lpConduit)
        private returns (int128, int128) {
        if (code == UserCmd.MINT_RANGE_LIQ_LP) {
            return mintConcentratedLiq(base, quote, poolIdx, bidTick, askTick, liq, lpConduit,
                        limitLower, limitHigher);
        } else if (code == UserCmd.MINT_RANGE_BASE_LP) {
            return mintConcentratedQty(base, quote, poolIdx, bidTick, askTick, true, liq, lpConduit,
                           limitLower, limitHigher);
        } else if (code == UserCmd.MINT_RANGE_QUOTE_LP) {
            return mintConcentratedQty(base, quote, poolIdx, bidTick, askTick, false, liq, lpConduit,
                           limitLower, limitHigher);
            
        } else if (code == UserCmd.BURN_RANGE_LIQ_LP) {
            return burnConcentratedLiq(base, quote, poolIdx, bidTick, askTick, liq, lpConduit,
                        limitLower, limitHigher);
        } else if (code == UserCmd.BURN_RANGE_BASE_LP) {
            return burnConcentratedQty(base, quote, poolIdx, bidTick, askTick, true, liq, lpConduit,
                           limitLower, limitHigher);
        } else if (code == UserCmd.BURN_RANGE_QUOTE_LP) {
            return burnConcentratedQty(base, quote, poolIdx, bidTick, askTick, false, liq, lpConduit,
                           limitLower, limitHigher);            
        } else if (code == UserCmd.MINT_HAQQX_LIQ_LP) {
            return mintHaqqXLiq(base, quote, poolIdx, liq, lpConduit, limitLower, limitHigher);
        } else if (code == UserCmd.MINT_HAQQX_BASE_LP) {
            return mintHaqqXQty(base, quote, poolIdx, true, liq, lpConduit,
                           limitLower, limitHigher);
        } else if (code == UserCmd.MINT_HAQQX_QUOTE_LP) {
            return mintHaqqXQty(base, quote, poolIdx, false, liq, lpConduit,
                           limitLower, limitHigher);            
        } else if (code == UserCmd.BURN_HAQQX_LIQ_LP) {
            return burnHaqqXLiq(base, quote, poolIdx, liq, lpConduit, limitLower, limitHigher);
        } else if (code == UserCmd.BURN_HAQQX_BASE_LP) {
            return burnHaqqXQty(base, quote, poolIdx, true, liq, lpConduit,
                           limitLower, limitHigher);
        } else if (code == UserCmd.BURN_HAQQX_QUOTE_LP) {
            return burnHaqqXQty(base, quote, poolIdx, false, liq, lpConduit,
                           limitLower, limitHigher);            
        } else if (code == UserCmd.HARVEST_LP) {
            return harvest(base, quote, poolIdx, bidTick, askTick, lpConduit,
                           limitLower, limitHigher);
        } else {
            revert("Invalid command");
        }
    }
 
    function mintConcentratedLiq (address base, address quote, uint256 poolIdx,
                   int24 bidTick, int24 askTick, uint128 liq, address lpConduit, 
                   uint128 limitLower, uint128 limitHigher) internal returns
        (int128, int128) {
        PoolSpecs.PoolCursor memory pool = queryPool(base, quote, poolIdx);
        verifyPermitMint(pool, base, quote, bidTick, askTick, liq);

        return mintOverPool(bidTick, askTick, liq, pool, limitLower, limitHigher,
                            lpConduit);
    }
    
    function burnConcentratedLiq (address base, address quote, uint256 poolIdx,
                   int24 bidTick, int24 askTick, uint128 liq, address lpConduit, 
                   uint128 limitLower, uint128 limitHigher)
        internal returns (int128, int128) {
        PoolSpecs.PoolCursor memory pool = queryPool(base, quote, poolIdx);
        verifyPermitBurn(pool, base, quote, bidTick, askTick, liq);
        
        return burnOverPool(bidTick, askTick, liq, pool, limitLower, limitHigher,
                            lpConduit);
    }

    function harvest (address base, address quote, uint256 poolIdx,
                      int24 bidTick, int24 askTick, address lpConduit,
                      uint128 limitLower, uint128 limitHigher)
        internal returns (int128, int128) {
        PoolSpecs.PoolCursor memory pool = queryPool(base, quote, poolIdx);
        
        verifyPermitBurn(pool, base, quote, bidTick, askTick, 0);
        
        return harvestOverPool(bidTick, askTick, pool, limitLower, limitHigher,
                               lpConduit);
    }

    function mintHaqqXLiq (address base, address quote, uint256 poolIdx, uint128 liq,
                   address lpConduit, uint128 limitLower, uint128 limitHigher) internal
        returns (int128, int128) {
        PoolSpecs.PoolCursor memory pool = queryPool(base, quote, poolIdx);
        verifyPermitMint(pool, base, quote, 0, 0, liq);
        return mintOverPool(liq, pool, limitLower, limitHigher, lpConduit);
    }

    function mintHaqqXQty (address base, address quote, uint256 poolIdx, bool inBase,
                      uint128 qty, address lpConduit, uint128 limitLower,
                      uint128 limitHigher) internal
        returns (int128, int128) {
        bytes32 poolKey = PoolSpecs.encodeKey(base, quote, poolIdx);
        CurveMath.CurveState memory curve = snapCurve(poolKey);
        uint128 liq = Chaining.sizeHaqqXLiq(qty, true, curve.priceRoot_, inBase);
        
        (int128 baseFlow, int128 quoteFlow) =
            mintHaqqXLiq(base, quote, poolIdx, liq, lpConduit, limitLower, limitHigher);
        return Chaining.pinFlow(baseFlow, quoteFlow, qty, inBase);
    }

    function mintConcentratedQty (address base, address quote, uint256 poolIdx,
                      int24 bidTick, int24 askTick, bool inBase,
                      uint128 qty, address lpConduit, uint128 limitLower,
                      uint128 limitHigher) internal
        returns (int128, int128) {
        uint128 liq = sizeAddLiq(base, quote, poolIdx, qty, bidTick, askTick, inBase);
        (int128 baseFlow, int128 quoteFlow) =
            mintConcentratedLiq(base, quote, poolIdx, bidTick, askTick, liq, lpConduit,
                 limitLower, limitHigher);
        return Chaining.pinFlow(baseFlow, quoteFlow, qty, inBase);
            
    }

    function sizeAddLiq (address base, address quote, uint256 poolIdx, uint128 qty,
                         int24 bidTick, int24 askTick, bool inBase)
        internal view returns (uint128) {
        bytes32 poolKey = PoolSpecs.encodeKey(base, quote, poolIdx);
        CurveMath.CurveState memory curve = snapCurve(poolKey);
        return Chaining.sizeConcLiq(qty, true, curve.priceRoot_,
                                    bidTick, askTick, inBase);
    }

    function burnHaqqXLiq (address base, address quote, uint256 poolIdx, uint128 liq,
                   address lpConduit, uint128 limitLower, uint128 limitHigher) internal
        returns (int128, int128) {
        PoolSpecs.PoolCursor memory pool = queryPool(base, quote, poolIdx);
        verifyPermitBurn(pool, base, quote, 0, 0, liq);
        return burnOverPool(liq, pool, limitLower, limitHigher, lpConduit);
    }

    function burnHaqqXQty (address base, address quote, uint256 poolIdx, bool inBase,
                      uint128 qty, address lpConduit,
                      uint128 limitLower, uint128 limitHigher) internal
        returns (int128, int128) {
        bytes32 poolKey = PoolSpecs.encodeKey(base, quote, poolIdx);
        CurveMath.CurveState memory curve = snapCurve(poolKey);
        uint128 liq = Chaining.sizeHaqqXLiq(qty, false, curve.priceRoot_, inBase);
        return burnHaqqXLiq(base, quote, poolIdx, liq, lpConduit,
                    limitLower, limitHigher);
    }

    function burnConcentratedQty (address base, address quote, uint256 poolIdx,
                      int24 bidTick, int24 askTick, bool inBase,
                      uint128 qty, address lpConduit,
                      uint128 limitLower, uint128 limitHigher)
        internal returns (int128, int128) {
        bytes32 poolKey = PoolSpecs.encodeKey(base, quote, poolIdx);
        CurveMath.CurveState memory curve = snapCurve(poolKey);
        uint128 liq = Chaining.sizeConcLiq(qty, false, curve.priceRoot_,
                                           bidTick, askTick, inBase);
        return burnConcentratedLiq(base, quote, poolIdx, bidTick, askTick,
                    liq, lpConduit, limitLower, limitHigher);
    }
    
    function acceptHaqqProxyRole (address, uint16 slot) public pure returns (bool) {
        return slot == HaqqSlots.LP_PROXY_IDX;
    }
}