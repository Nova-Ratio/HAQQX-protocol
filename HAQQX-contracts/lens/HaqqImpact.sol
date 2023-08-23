// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;
import "../HaqqSwapDex.sol";

contract HaqqImpact {
    using CurveMath for CurveMath.CurveState;
    using CurveRoll for CurveMath.CurveState;
    using SwapCurve for CurveMath.CurveState;
    using SafeCast for uint144;
    using TickMath for uint128;
    using LiquidityMath for uint128;
    using Chaining for Chaining.PairFlow;
    using Bitmaps for uint256;
    using Bitmaps for int24;
    
    address immutable public dex_;
    
    constructor (address dex) {
        require(dex != address(0) && HaqqSwapDex(dex).acceptHaqqDex(), "Invalid HaqqSwapDex");
        dex_ = dex;
    }

    function calcImpact (address base, address quote,
                         uint256 poolIdx, bool isBuy, bool inBaseQty, uint128 qty,
                        uint16 poolTip, uint128 limitPrice) public view  
        returns (int128 baseFlow, int128 quoteFlow, uint128 finalPrice) {

        PoolSpecs.PoolCursor memory pool = queryPoolCntx
            (base, quote, poolIdx, poolTip);
        CurveMath.CurveState memory curve = queryCurve(base, quote, poolIdx);

        Directives.SwapDirective memory dir;
        dir.isBuy_ = isBuy;
        dir.inBaseQty_ = inBaseQty;
        dir.qty_ = qty;
        dir.limitPrice_ = limitPrice;

        (baseFlow, quoteFlow) = sweepSwap(pool, curve, dir);
        finalPrice = curve.priceRoot_;
    }

    function queryPoolCntx (address base, address quote,
                            uint256 poolIdx, uint16 poolTip) private view 
        returns (PoolSpecs.PoolCursor memory cursor) {
        uint256 POOL_SLOT = 65545;

        bytes32 poolHash = PoolSpecs.encodeKey(base, quote, poolIdx);
        bytes32 slot = keccak256(abi.encodePacked(poolHash, POOL_SLOT));
        uint256 val = HaqqSwapDex(dex_).readSlot(uint256(slot));

        cursor.hash_ = poolHash;
        cursor.head_.feeRate_ = uint16((val & uint256(0xFFFF00)) >> 8);
        cursor.head_.protocolTake_ = uint8((val & uint256(0xFF000000)) >> 24);
        
        if (poolTip > cursor.head_.feeRate_) {
            cursor.head_.feeRate_ = poolTip;
        }
    }

    function queryCurve (address base, address quote, uint256 poolIdx) private view 
        returns (CurveMath.CurveState memory curve) {
        bytes32 key = PoolSpecs.encodeKey(base, quote, poolIdx);
        bytes32 slot = keccak256(abi.encode(key, HaqqSlots.CURVE_MAP_SLOT));
        uint256 valOne = HaqqSwapDex(dex_).readSlot(uint256(slot));
        uint256 valTwo = HaqqSwapDex(dex_).readSlot(uint256(slot)+1);
        
        curve.priceRoot_ = uint128((valOne << 128) >> 128);
        curve.haqqxSeeds_ = uint128(valOne >> 128);
        curve.concLiq_ = uint128((valTwo << 128) >> 128);
        curve.seedDeflator_ = uint64((valTwo << 64) >> 192);
        curve.concGrowth_ = uint64(valTwo >> 192);
    }

    function queryLevel (bytes32 poolHash, int24 tick) private view 
        returns (uint96 bidLots, uint96 askLots) {   
        bytes32 key = keccak256(abi.encodePacked(poolHash, tick));
        bytes32 slot = keccak256(abi.encode(key, HaqqSlots.LVL_MAP_SLOT));
        uint256 val = HaqqSwapDex(dex_).readSlot(uint256(slot));

        askLots = uint96((val << 64) >> 160);
        bidLots = uint96((val << 160) >> 160);
    }

    function queryTerminus (bytes32 key) private view returns (uint256) {
        uint256 TERMINUS_SLOT = 65543;
        bytes32 slot = keccak256(abi.encode(key, TERMINUS_SLOT));
        return HaqqSwapDex(dex_).readSlot(uint256(slot));
    }

    function queryMezz (bytes32 key) private view returns (uint256) {
        uint256 MEZZ_SLOT = 65542;
        bytes32 slot = keccak256(abi.encode(key, MEZZ_SLOT));
        return HaqqSwapDex(dex_).readSlot(uint256(slot));
        
    }

    function sweepSwap (PoolSpecs.PoolCursor memory pool, 
                        CurveMath.CurveState memory curve,
                        Directives.SwapDirective memory swap) private view 
        returns (int128 baseFlow, int128 quoteFlow) {

        if (swap.isBuy_ == (curve.priceRoot_ >= swap.limitPrice_)) {
            return (0, 0);
        }

        Chaining.PairFlow memory accum;
        int24 midTick = curve.priceRoot_.getTickAtSqrtRatio();
        
        bool doMore = true;
        while (doMore) {
            (int24 bumpTick, bool spillsOver) = pinBitmap
                (pool.hash_, swap.isBuy_, midTick);
            curve.swapToLimit(accum, swap, pool.head_, bumpTick);
            
            doMore = hasSwapLeft(curve, swap);
            if (doMore) {

                if (spillsOver) {
                    int24 liqTick = seekMezzSpill(pool.hash_, bumpTick, swap.isBuy_);
                    bool tightSpill = (bumpTick == liqTick);
                    bumpTick = liqTick;
                    
                    if (!tightSpill) {
                        curve.swapToLimit(accum, swap, pool.head_, bumpTick);
                        doMore = hasSwapLeft(curve, swap);
                    }
                }
                
                if (doMore) {
                    midTick = adjTickLiq(accum, bumpTick, curve, swap, pool.hash_);
                }
            }
            
        }
        return (accum.baseFlow_, accum.quoteFlow_);
    }

    function adjTickLiq (Chaining.PairFlow memory accum, int24 bumpTick,
                         CurveMath.CurveState memory curve,
                         Directives.SwapDirective memory swap,
                         bytes32 poolHash) private view returns (int24) {
        unchecked {
        if (!Bitmaps.isTickFinite(bumpTick)) { return bumpTick; }

        (uint96 bidLots, uint96 askLots) = queryLevel(poolHash, bumpTick);
        int128 crossDelta = LiquidityMath.netLotsOnLiquidity(bidLots, askLots);
        int128 liqDelta = swap.isBuy_ ? crossDelta : -crossDelta;
        curve.concLiq_ = curve.concLiq_.addDelta(liqDelta);

        (int128 paidBase, int128 paidQuote, uint128 burnSwap) =
            curve.shaveAtBump(swap.inBaseQty_, swap.isBuy_, swap.qty_);
        accum.accumFlow(paidBase, paidQuote);
        swap.qty_ -= burnSwap;

        return swap.isBuy_ ?
            bumpTick :
            bumpTick - 1; 
        }
    }

    function pinBitmap (bytes32 poolHash, bool isUpper, int24 startTick) 
        private view returns (int24 boundTick, bool isSpill) {
        uint256 termBitmap = queryTerminus(encodeTerm(poolHash, startTick));
        uint16 shiftTerm = startTick.termBump(isUpper);
        int16 tickMezz = startTick.mezzKey();
        (boundTick, isSpill) = pinTermMezz
            (isUpper, shiftTerm, tickMezz, termBitmap);
    }

    function pinTermMezz (bool isUpper, uint16 shiftTerm, int16 tickMezz,
                          uint256 termBitmap)
        private pure returns (int24 nextTick, bool spillBit) {
        (uint8 nextTerm, bool spillTrunc) =
            termBitmap.bitAfterTrunc(shiftTerm, isUpper);
        spillBit = doesSpillBit(isUpper, spillTrunc, termBitmap);
        nextTick = spillBit ?
            spillOverPin(isUpper, tickMezz) :
            Bitmaps.weldMezzTerm(tickMezz, nextTerm);
    }

    function spillOverPin (bool isUpper, int16 tickMezz) private pure returns (int24) {
        if (isUpper) {
            return tickMezz == Bitmaps.zeroMezz(isUpper) ?
                Bitmaps.zeroTick(isUpper) :
                Bitmaps.weldMezzTerm(tickMezz + 1, Bitmaps.zeroTerm(!isUpper));
        } else {
            return Bitmaps.weldMezzTerm(tickMezz, 0);
        }
    }

    function doesSpillBit (bool isUpper, bool spillTrunc, uint256 termBitmap)
        private pure returns (bool spillBit) {
        if (isUpper) {
            spillBit = spillTrunc;
        } else {
            bool bumpAtFloor = termBitmap.isBitSet(0);
            spillBit = bumpAtFloor ? false :
                spillTrunc;
        }
    }

    function seekMezzSpill (bytes32 poolIdx, int24 borderTick, bool isUpper)
        internal view returns (int24) {
        (uint8 lobbyBorder, uint8 mezzBorder) = rootsForBorder(borderTick, isUpper);

        (int24 pin, bool spills) =
            seekAtTerm(poolIdx, lobbyBorder, mezzBorder, isUpper);
        if (!spills) { return pin; }                                      

        (pin, spills) =
            seekAtMezz(poolIdx, lobbyBorder, mezzBorder, isUpper);
        if (!spills) { return pin; }

        return seekOverLobby(poolIdx, lobbyBorder, isUpper);
    }

    function seekAtTerm (bytes32 poolIdx, uint8 lobbyBit, uint8 mezzBit, bool isUpper)
        private view returns (int24, bool) {
        uint256 neighborBitmap = queryTerminus(encodeTermWord(poolIdx, lobbyBit, mezzBit));
        (uint8 termBit, bool spills) = neighborBitmap.bitAfterTrunc(0, isUpper);
        if (spills) { return (0, true); }
        return (Bitmaps.weldLobbyPosMezzTerm(lobbyBit, mezzBit, termBit), false);
    }

    function seekAtMezz (bytes32 poolIdx, uint8 lobbyBit,
                         uint8 mezzBorder, bool isUpper)
        private view returns (int24, bool) {
        uint256 neighborMezz = queryMezz(encodeMezzWord(poolIdx, lobbyBit));
        uint8 mezzShift = Bitmaps.bitRelate(mezzBorder, isUpper);
        (uint8 mezzBit, bool spills) = neighborMezz.bitAfterTrunc(mezzShift, isUpper);
        if (spills) { return (0, true); }
        return seekAtTerm(poolIdx, lobbyBit, mezzBit, isUpper);
    }

    function seekOverLobby (bytes32 poolIdx, uint8 lobbyBit, bool isUpper)
        private view returns (int24) {
        return isUpper ?
            seekLobbyUp(poolIdx, lobbyBit) :
            seekLobbyDown(poolIdx, lobbyBit);
    }

    function seekLobbyUp (bytes32 poolIdx, uint8 lobbyBit)
        private view returns (int24) {
        uint8 MAX_MEZZ = 0;
        unchecked {
            for (uint8 i = lobbyBit + 1; i > 0; ++i) {
                (int24 tick, bool spills) = seekAtMezz(poolIdx, i, MAX_MEZZ, true);
                if (!spills) { return tick; }
            }
        }
        return Bitmaps.zeroTick(true);
    }

    function seekLobbyDown (bytes32 poolIdx, uint8 lobbyBit)
        private view returns (int24) {
        uint8 MIN_MEZZ = 255;
        unchecked {
            for (uint8 i = lobbyBit - 1; i < 255; --i) {
                (int24 tick, bool spills) = seekAtMezz(poolIdx, i, MIN_MEZZ, false);
                if (!spills) { return tick; }
            }
        }
        return Bitmaps.zeroTick(false);
    }

    function rootsForBorder (int24 borderTick, bool isUpper) private pure
        returns (uint8 lobbyBit, uint8 mezzBit) {
        int24 pinTick = isUpper ? borderTick : (borderTick - 1);
        lobbyBit = pinTick.lobbyBit();
        mezzBit = pinTick.mezzBit();
    }

    function encodeMezz (bytes32 poolIdx, int24 tick) private pure returns (bytes32) {
        int8 wordPos = tick.lobbyKey();
        return keccak256(abi.encodePacked(poolIdx, wordPos)); 
    }

    function encodeTerm (bytes32 poolIdx, int24 tick) private pure returns (bytes32) {
        int16 wordPos = tick.mezzKey();
        return keccak256(abi.encodePacked(poolIdx, wordPos)); 
    }

    function encodeMezzWord (bytes32 poolIdx, int8 lobbyPos)
        private pure returns (bytes32) {
        return keccak256(abi.encodePacked(poolIdx, lobbyPos));  
    }

    function encodeMezzWord (bytes32 poolIdx, uint8 lobbyPos)
        private pure returns (bytes32) {
        return encodeMezzWord(poolIdx, Bitmaps.uncastBitmapIndex(lobbyPos));
    }

    function encodeTermWord (bytes32 poolIdx, uint8 lobbyPos, uint8 mezzPos)
        private pure returns (bytes32) {
        int16 mezzIdx = Bitmaps.weldLobbyMezz
            (Bitmaps.uncastBitmapIndex(lobbyPos), mezzPos);
        return keccak256(abi.encodePacked(poolIdx, mezzIdx)); 
    }

    function hasSwapLeft (CurveMath.CurveState memory curve,
                          Directives.SwapDirective memory swap)
        private pure returns (bool) {
        bool inLimit = swap.isBuy_ ?
            curve.priceRoot_ < swap.limitPrice_ :
            curve.priceRoot_ > swap.limitPrice_;
        return inLimit && (swap.qty_ > 0);
    }
}