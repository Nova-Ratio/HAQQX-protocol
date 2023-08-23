// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import '../libraries/Directives.sol';
import '../libraries/Encoding.sol';
import '../libraries/TokenFlow.sol';
import '../libraries/PriceGrid.sol';
import '../mixins/MarketSequencer.sol';
import '../mixins/SettleLayer.sol';
import '../mixins/PoolRegistry.sol';
import '../mixins/MarketSequencer.sol';
import '../mixins/ProtocolAccount.sol';

contract HotPath is MarketSequencer, SettleLayer, ProtocolAccount {
    using SafeCast for uint128;
    using TokenFlow for TokenFlow.PairSeq;
    using CurveMath for CurveMath.CurveState;
    using Chaining for Chaining.PairFlow;

    function swapDir (PoolSpecs.PoolCursor memory pool, bool isBuy,
                      bool inBaseQty, uint128 qty, uint128 limitPrice) private
        returns (Chaining.PairFlow memory) {
        Directives.SwapDirective memory dir;
        dir.isBuy_ = isBuy;
        dir.inBaseQty_ = inBaseQty;
        dir.qty_ = qty;
        dir.limitPrice_ = limitPrice;
        dir.rollType_ = 0;
        return swapOverPool(dir, pool);
        
    }

    function swapExecute (address base, address quote,
                          uint256 poolIdx, bool isBuy, bool inBaseQty, uint128 qty,
                          uint16 poolTip, uint128 limitPrice, uint128 minOutput,
                          uint8 reserveFlags) internal
        returns (int128 baseFlow, int128 quoteFlow) {
        
        PoolSpecs.PoolCursor memory pool = preparePoolCntx
            (base, quote, poolIdx, poolTip, isBuy, inBaseQty, qty);

        Chaining.PairFlow memory flow = swapDir(pool, isBuy, inBaseQty, qty, limitPrice);
        (baseFlow, quoteFlow) = (flow.baseFlow_, flow.quoteFlow_);

        pivotOutFlow(flow, minOutput, isBuy, inBaseQty);        
        settleFlows(base, quote, flow.baseFlow_, flow.quoteFlow_, reserveFlags);
        accumProtocolFees(flow, base, quote);
    }

    function pivotOutFlow (Chaining.PairFlow memory flow, uint128 minOutput,
                           bool isBuy, bool inBaseQty) private pure
        returns (int128 outFlow) {
        outFlow = inBaseQty ? flow.quoteFlow_ : flow.baseFlow_;
        bool isOutPaid = (isBuy == inBaseQty);
        int128 thresh = isOutPaid ? -int128(minOutput) : int128(minOutput);
        require(outFlow <= thresh || minOutput == 0, "SL");
    }

    function preparePoolCntx (address base, address quote,
                              uint256 poolIdx, uint16 poolTip,
                              bool isBuy, bool inBaseQty, uint128 qty) private
        returns (PoolSpecs.PoolCursor memory) {
        PoolSpecs.PoolCursor memory pool = queryPool(base, quote, poolIdx);
        if (poolTip > pool.head_.feeRate_) {
            pool.head_.feeRate_ = poolTip;
        }
        verifyPermitSwap(pool, base, quote, isBuy, inBaseQty, qty);
        return pool;
    }

    function swapEncoded (bytes calldata input) internal returns
        (int128 baseFlow, int128 quoteFlow) {
        (address base, address quote,
         uint256 poolIdx, bool isBuy, bool inBaseQty, uint128 qty, uint16 poolTip,
         uint128 limitPrice, uint128 minOutput, uint8 reserveFlags) =
            abi.decode(input, (address, address, uint256, bool, bool,
                               uint128, uint16, uint128, uint128, uint8));
        
        return swapExecute(base, quote, poolIdx, isBuy, inBaseQty, qty, poolTip,
                           limitPrice, minOutput, reserveFlags);
    }
}

contract HotProxy is HotPath {

    function userCmd (bytes calldata input) public payable
        returns (int128, int128) {
        require(!hotPathOpen_, "Hot path enabled");
        return swapEncoded(input);
    }

    function acceptHaqqProxyRole (address, uint16 slot) public pure returns (bool) {
        return slot == HaqqSlots.SWAP_PROXY_IDX;
    }

}


