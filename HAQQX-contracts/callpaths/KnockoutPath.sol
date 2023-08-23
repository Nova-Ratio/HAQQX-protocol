// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import '../libraries/Directives.sol';
import '../libraries/Encoding.sol';
import '../libraries/TokenFlow.sol';
import '../libraries/PriceGrid.sol';
import '../libraries/ProtocolCmd.sol';
import '../mixins/SettleLayer.sol';
import '../mixins/PoolRegistry.sol';
import '../mixins/TradeMatcher.sol';

contract KnockoutFlagPath is KnockoutCounter {

    function crossCurveFlag (bytes32 pool, int24 tick, bool isBuy, uint64 feeGlobal)
        public payable returns (int128) {
        bool bidCross = !isBuy;
        crossKnockout(pool, bidCross, tick, feeGlobal);
        return 0;
    }

    function acceptHaqqProxyRole (address, uint16 slot) public pure returns (bool) {
        return slot == HaqqSlots.FLAG_CROSS_PROXY_IDX;
    }

}

contract KnockoutLiqPath is TradeMatcher, SettleLayer {
    using SafeCast for uint128;
    using TickMath for uint128;
    using TokenFlow for TokenFlow.PairSeq;
    using CurveMath for CurveMath.CurveState;
    using Chaining for Chaining.PairFlow;
    using KnockoutLiq for KnockoutLiq.KnockoutPosLoc;

    function userCmd (bytes calldata cmd) public payable returns
        (int128 baseFlow, int128 quoteFlow) {
        
        (uint8 code, address base, address quote, uint256 poolIdx,
         int24 bidTick, int24 askTick, bool isBid, uint8 reserveFlags,
         bytes memory args) = abi.decode
            (cmd, (uint8, address, address, uint256, int24, int24, bool, uint8, bytes));

        PoolSpecs.PoolCursor memory pool = queryPool(base, quote, poolIdx);
        CurveMath.CurveState memory curve = snapCurve(pool.hash_);

        KnockoutLiq.KnockoutPosLoc memory loc;
        loc.isBid_ = isBid;
        loc.lowerTick_ = bidTick;
        loc.upperTick_ = askTick;

        return overCurve(code, base, quote, pool, curve, loc, reserveFlags, args);
    }

    function overCurve (uint8 code, address base, address quote,
                        PoolSpecs.PoolCursor memory pool,
                        CurveMath.CurveState memory curve,
                        KnockoutLiq.KnockoutPosLoc memory loc,
                        uint8 reserveFlags, bytes memory args)
        private returns (int128 baseFlow, int128 quoteFlow) {        
        if (code == UserCmd.MINT_KNOCKOUT) {
            (baseFlow, quoteFlow) = mintCmd(base, quote, pool, curve, loc, args);
        } else if (code == UserCmd.BURN_KNOCKOUT) {
            (baseFlow, quoteFlow) = burnCmd(base, quote, pool, curve, loc, args);
        } else if (code == UserCmd.CLAIM_KNOCKOUT) {
            (baseFlow, quoteFlow) = claimCmd(pool.hash_, curve, loc, args);
        } else if (code == UserCmd.RECOVER_KNOCKOUT) {
            (baseFlow, quoteFlow) = recoverCmd(pool.hash_, loc, args);
        } else {
            revert("Invalid command");
        }

        settleFlows(base, quote, baseFlow, quoteFlow, reserveFlags);
    }

    function mintCmd (address base, address quote, PoolSpecs.PoolCursor memory pool,
                      CurveMath.CurveState memory curve,
                      KnockoutLiq.KnockoutPosLoc memory loc,
                      bytes memory args) private returns
        (int128 baseFlow, int128 quoteFlow) {
        (uint128 qty, bool insideMid) = abi.decode(args, (uint128,bool));
        
        int24 priceTick = curve.priceRoot_.getTickAtSqrtRatio();
        require(loc.spreadOkay(priceTick, insideMid), "KL");

        uint128 liq = Chaining.sizeConcLiq(qty, true, curve.priceRoot_,
                                           loc.lowerTick_, loc.upperTick_, loc.isBid_);
        verifyPermitMint(pool, base, quote, loc.lowerTick_, loc.upperTick_, liq);

        (baseFlow, quoteFlow) = mintKnockout(curve, priceTick, loc, liq, pool.hash_,
                                             pool.head_.knockoutBits_);
        commitCurve(pool.hash_, curve);
        (baseFlow, quoteFlow) = Chaining.pinFlow(baseFlow, quoteFlow, qty, loc.isBid_);
    }

    function burnCmd (address base, address quote, PoolSpecs.PoolCursor memory pool,
                      CurveMath.CurveState memory curve,
                      KnockoutLiq.KnockoutPosLoc memory loc,
                      bytes memory args) private returns
        (int128 baseFlow, int128 quoteFlow) {
        (uint128 qty, bool inLiqQty, bool insideMid) =
            abi.decode(args, (uint128,bool,bool));

        int24 priceTick = curve.priceRoot_.getTickAtSqrtRatio();
        require(loc.spreadOkay(priceTick, insideMid), "KL");

        uint128 liq = inLiqQty ? qty :
            Chaining.sizeConcLiq(qty, false, curve.priceRoot_,
                                 loc.lowerTick_, loc.upperTick_, loc.isBid_);        
        verifyPermitBurn(pool, base, quote, loc.lowerTick_, loc.upperTick_, liq);

        (baseFlow, quoteFlow) = burnKnockout(curve, priceTick, loc, liq, pool.hash_);
        commitCurve(pool.hash_, curve);
    }

    function claimCmd (bytes32 pool, CurveMath.CurveState memory curve,
                       KnockoutLiq.KnockoutPosLoc memory loc,
                       bytes memory args) private returns
        (int128 baseFlow, int128 quoteFlow) {
        (uint160 root, uint256[] memory proof) = abi.decode(args, (uint160,uint256[]));

        (baseFlow, quoteFlow) = claimKnockout(curve, loc, root, proof, pool);
        commitCurve(pool, curve);
    }
    
    function recoverCmd (bytes32 pool, KnockoutLiq.KnockoutPosLoc memory loc,
                         bytes memory args) private returns
        (int128 baseFlow, int128 quoteFlow) {
        (uint32 pivotTime) = abi.decode(args, (uint32));
        

        (baseFlow, quoteFlow) = recoverKnockout(loc, pivotTime, pool);
    }

    function acceptHaqqProxyRole (address, uint16 slot) public pure returns (bool) {
        return slot == HaqqSlots.KNOCKOUT_LP_PROXY_IDX;
    }
}
