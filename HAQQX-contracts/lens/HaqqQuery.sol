// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;
import "../HaqqSwapDex.sol";

contract HaqqQuery {
    using CurveMath for CurveMath.CurveState;
    using SafeCast for uint144;
    
    address immutable public dex_;
  
    constructor (address dex) {
        require(dex != address(0) && HaqqSwapDex(dex).acceptHaqqDex(), "Invalid HaqqSwapDex");
        dex_ = dex;
    }
    
    function queryCurve (address base, address quote, uint256 poolIdx)
        public view returns (CurveMath.CurveState memory curve) {
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

    function queryPoolParams (address base, address quote, uint256 poolIdx)
        public view returns (PoolSpecs.Pool memory pool) {
        bytes32 key = PoolSpecs.encodeKey(base, quote, poolIdx);
        bytes32 slot = keccak256(abi.encode(key, HaqqSlots.POOL_PARAM_SLOT));
        uint256 valOne = HaqqSwapDex(dex_).readSlot(uint256(slot));

        pool.schema_ = uint8(valOne);
        pool.feeRate_ = uint16(valOne >> 8);
        pool.protocolTake_ = uint8(valOne >> 24);
        pool.tickSize_ = uint16(valOne >> 32);
        pool.jitThresh_ = uint8(valOne >> 48);
        pool.knockoutBits_ = uint8(valOne >> 56);
        pool.oracleFlags_ = uint8(valOne >> 64);
    }

    function queryPoolTemplate (uint256 poolIdx)
        public view returns (PoolSpecs.Pool memory pool) {
        bytes32 slot = keccak256(abi.encode(poolIdx, HaqqSlots.POOL_TEMPL_SLOT));
        uint256 valOne = HaqqSwapDex(dex_).readSlot(uint256(slot));

        pool.schema_ = uint8(valOne);
        pool.feeRate_ = uint16(valOne >> 8);
        pool.protocolTake_ = uint8(valOne >> 24);
        pool.tickSize_ = uint16(valOne >> 32);
        pool.jitThresh_ = uint8(valOne >> 48);
        pool.knockoutBits_ = uint8(valOne >> 56);
        pool.oracleFlags_ = uint8(valOne >> 64);
    }

    function queryCurveTick (address base, address quote, uint256 poolIdx) 
        public view returns (int24) {
        bytes32 key = PoolSpecs.encodeKey(base, quote, poolIdx);
        bytes32 slot = keccak256(abi.encode(key, HaqqSlots.CURVE_MAP_SLOT));
        uint256 valOne = HaqqSwapDex(dex_).readSlot(uint256(slot));
        
        uint128 curvePrice = uint128((valOne << 128) >> 128);
        return TickMath.getTickAtSqrtRatio(curvePrice);
    }

    function queryLiquidity (address base, address quote, uint256 poolIdx)
        public view returns (uint128) {        
        return queryCurve(base, quote, poolIdx).activeLiquidity();
    }

    function queryPrice (address base, address quote, uint256 poolIdx)
        public view returns (uint128) {
        return queryCurve(base, quote, poolIdx).priceRoot_;
    }

    function querySurplus (address owner, address token)
        public view returns (uint128 surplus) {
        bytes32 key = keccak256(abi.encode(owner, token));
        bytes32 slot = keccak256(abi.encode(key, HaqqSlots.BAL_MAP_SLOT));
        uint256 val = HaqqSwapDex(dex_).readSlot(uint256(slot));
        surplus = uint128((val << 128) >> 128);
    }

    function queryVirtual (address owner, address tracker, uint256 salt)
        public view returns (uint128 surplus) {
        address token = PoolSpecs.virtualizeAddress(tracker, salt);
        surplus = querySurplus(owner, token);
    }

    function queryProtocolAccum (address token) public view returns (uint128) {
        bytes32 key = bytes32(uint256(uint160(token)));
        bytes32 slot = keccak256(abi.encode(key, HaqqSlots.FEE_MAP_SLOT));
        uint256 val = HaqqSwapDex(dex_).readSlot(uint256(slot));
        return uint128(val);
    }

    function queryLevel (address base, address quote, uint256 poolIdx, int24 tick)
        public view returns (uint96 bidLots, uint96 askLots, uint64 odometer) {
        bytes32 poolHash = PoolSpecs.encodeKey(base, quote, poolIdx);
        bytes32 key = keccak256(abi.encodePacked(poolHash, tick));
        bytes32 slot = keccak256(abi.encode(key, HaqqSlots.LVL_MAP_SLOT));
        uint256 val = HaqqSwapDex(dex_).readSlot(uint256(slot));

        odometer = uint64(val >> 192);
        askLots = uint96((val << 64) >> 160);
        bidLots = uint96((val << 160) >> 160);
    }

    function queryKnockoutPivot (address base, address quote, uint256 poolIdx,
                                 bool isBid, int24 tick)
        public view returns (uint96 lots, uint32 pivot, uint16 range) {
        bytes32 poolHash = PoolSpecs.encodeKey(base, quote, poolIdx);
        bytes32 key = KnockoutLiq.encodePivotKey(poolHash, isBid, tick);
        bytes32 slot = keccak256(abi.encodePacked(key, HaqqSlots.KO_PIVOT_SLOT));
        uint256 val = HaqqSwapDex(dex_).readSlot(uint256(slot));

        lots = uint96((val << 160) >> 160);
        pivot = uint32((val << 128) >> 224);
        range = uint16(val >> 128);
    }

    function queryKnockoutMerkle (address base, address quote, uint256 poolIdx,
                                  bool isBid, int24 tick)
        public view returns (uint160 root, uint32 pivot, uint64 fee) {
        bytes32 poolHash = PoolSpecs.encodeKey(base, quote, poolIdx);
        bytes32 key = KnockoutLiq.encodePivotKey(poolHash, isBid, tick);
        bytes32 slot = keccak256(abi.encodePacked(key, HaqqSlots.KO_MERKLE_SLOT));
        uint256 val = HaqqSwapDex(dex_).readSlot(uint256(slot));

        root = uint160((val << 96) >> 96);
        pivot = uint32((val << 64) >> 224);
        fee = uint64(val >> 192);
    }

    function queryKnockoutPos (address owner, address base, address quote,
                               uint256 poolIdx, uint32 pivot, bool isBid,
                               int24 lowerTick, int24 upperTick) public view
        returns (uint96 lots, uint64 mileage, uint32 timestamp) {
        bytes32 poolHash = PoolSpecs.encodeKey(base, quote, poolIdx);
        KnockoutLiq.KnockoutPosLoc memory loc;
        loc.isBid_ = isBid;
        loc.lowerTick_ = lowerTick;
        loc.upperTick_ = upperTick;

        return queryKnockoutPos(loc, poolHash, owner, pivot);
    }

    function queryKnockoutPos (KnockoutLiq.KnockoutPosLoc memory loc,
                               bytes32 poolHash, address owner, uint32 pivot)
        private view returns (uint96 lots, uint64 mileage, uint32 timestamp) {
        bytes32 key = KnockoutLiq.encodePosKey(loc, poolHash, owner, pivot);
        bytes32 slot = keccak256(abi.encodePacked(key, HaqqSlots.KO_POS_SLOT));
        uint256 val = HaqqSwapDex(dex_).readSlot(uint256(slot));

        lots = uint96((val << 160) >> 160);
        mileage = uint64((val << 96) >> 224);
        timestamp = uint32(val >> 224);
    }

    function queryRangePosition (address owner, address base, address quote,
                                 uint256 poolIdx, int24 lowerTick, int24 upperTick)
        public view returns (uint128 liq, uint64 fee,
                             uint32 timestamp, bool atomic) {
        bytes32 poolHash = PoolSpecs.encodeKey(base, quote, poolIdx);
        bytes32 posKey = keccak256(abi.encodePacked(owner, poolHash, lowerTick, upperTick));
        bytes32 slot = keccak256(abi.encodePacked(posKey, HaqqSlots.POS_MAP_SLOT));
        uint256 val = HaqqSwapDex(dex_).readSlot(uint256(slot));

        liq = uint128((val << 128) >> 128);
        fee = uint64((val >> 128) << (128 + 64) >> (128 + 64));
        timestamp = uint32((val >> (128 + 64)) << (128 + 64 + 32) >> (128 + 64 + 32));
        atomic = bool((val >> (128 + 64 + 32)) > 0);
    }

    function queryHaqqXPosition (address owner, address base, address quote,
                                   uint256 poolIdx)
        public view returns (uint128 seeds, uint32 timestamp) {
        bytes32 poolHash = PoolSpecs.encodeKey(base, quote, poolIdx);
        bytes32 posKey = keccak256(abi.encodePacked(owner, poolHash));
        bytes32 slot = keccak256(abi.encodePacked(posKey, HaqqSlots.AMB_MAP_SLOT));
        uint256 val = HaqqSwapDex(dex_).readSlot(uint256(slot));

        seeds = uint128((val << 128) >> 128);
        timestamp = uint32((val >> (128)) << (128 + 32) >> (128 + 32));
    }    

    function queryConcRewards (address owner, address base, address quote, uint256 poolIdx,
                               int24 lowerTick, int24 upperTick) 
                               public view returns (uint128 liqRewards, 
                                                    uint128 baseRewards, uint128 quoteRewards) {
        (uint128 liq, uint64 feeStart, ,) = queryRangePosition(owner, base, quote, poolIdx,
                                                               lowerTick, upperTick);
        (, , uint64 bidFee) = queryLevel(base, quote, poolIdx, lowerTick);
        (, , uint64 askFee) = queryLevel(base, quote, poolIdx, upperTick);
        CurveMath.CurveState memory curve = queryCurve(base, quote, poolIdx);
        uint64 curveFee = queryCurve(base, quote, poolIdx).concGrowth_;

        int24 curveTick = TickMath.getTickAtSqrtRatio(curve.priceRoot_);
        uint64 feeLower = lowerTick <= curveTick ? bidFee : curveFee - bidFee;
        uint64 feeUpper = upperTick <= curveTick ? askFee : curveFee - askFee;
            
        unchecked {
            uint64 odometer = feeUpper - feeLower;

            if (odometer < feeStart) {
                return (0, 0, 0);
            }

            uint64 accumFees = odometer - feeStart;
            uint128 seeds = FixedPoint.mulQ48(liq, accumFees).toUint128By144();
            return convertSeedsToLiq(curve, seeds);
        }
    }

    function queryHaqqXTokens (address owner, address base, address quote,
                                 uint256 poolIdx)
        public view returns (uint128 liq, uint128 baseQty, uint128 quoteQty) {
        (uint128 seeds, ) = queryHaqqXPosition(owner, base, quote, poolIdx);
        CurveMath.CurveState memory curve = queryCurve(base, quote, poolIdx);
        return convertSeedsToLiq(curve, seeds);
    }

    function queryRangeTokens (address owner, address base, address quote,
                               uint256 poolIdx, int24 lowerTick, int24 upperTick)
        public view returns (uint128 liq, uint128 baseQty, uint128 quoteQty) {
        (liq, , ,) = queryRangePosition(owner, base, quote, poolIdx, lowerTick, upperTick);
        CurveMath.CurveState memory curve = queryCurve(base, quote, poolIdx);
        (baseQty, quoteQty) = concLiqToTokens(curve, lowerTick, upperTick, liq);
    }

    function queryKnockoutTokens (address owner, address base, address quote,
                                  uint256 poolIdx, uint32 pivot, bool isBid,
                                  int24 lowerTick, int24 upperTick)
        public view returns (uint128 liq, uint128 baseQty, uint128 quoteQty, bool knockedOut) {

        int24 knockoutTick = isBid ? lowerTick : upperTick;
        (uint96 lots, , ) = queryKnockoutPos(owner, base, quote, poolIdx, pivot, isBid, lowerTick, upperTick);
        (, uint32 pivotActive, ) = queryKnockoutPivot(base, quote, poolIdx, isBid, knockoutTick);

        liq = LiquidityMath.lotsToLiquidity(lots);
        knockedOut = pivotActive != pivot;

        if (knockedOut) {
            uint128 knockoutPrice = TickMath.getSqrtRatioAtTick(knockoutTick);
            (baseQty, quoteQty) = concLiqToTokens(knockoutPrice, lowerTick, upperTick, liq);

        } else {
            CurveMath.CurveState memory curve = queryCurve(base, quote, poolIdx);
            (baseQty, quoteQty) = concLiqToTokens(curve, lowerTick, upperTick, liq);
        }
    }

    function convertSeedsToLiq (CurveMath.CurveState memory curve, uint128 seeds) 
                                internal pure returns (uint128 liq, uint128 baseQty, uint128 quoteQty) {
        liq = CompoundMath.inflateLiqSeed(seeds, curve.seedDeflator_);
        (baseQty, quoteQty) = liquidityToTokens(curve, liq);
    }

    function concLiqToTokens (CurveMath.CurveState memory curve, 
                              int24 lowerTick, int24 upperTick, uint128 liq) 
        internal pure returns (uint128 baseQty, uint128 quoteQty) {
        return concLiqToTokens(curve.priceRoot_, lowerTick, upperTick, liq);
    }

    function concLiqToTokens (uint128 curvePrice, 
                              int24 lowerTick, int24 upperTick, uint128 liq) 
        internal pure returns (uint128 baseQty, uint128 quoteQty) {
        uint128 lowerPrice = TickMath.getSqrtRatioAtTick(lowerTick);
        uint128 upperPrice = TickMath.getSqrtRatioAtTick(upperTick);

        (uint128 lowerBase, uint128 lowerQuote) = liquidityToTokens(lowerPrice, liq);
        (uint128 upperBase, uint128 upperQuote) = liquidityToTokens(upperPrice, liq);
        (uint128 ambBase, uint128 ambQuote) = liquidityToTokens(curvePrice, liq);

        if (curvePrice < lowerPrice) {
            return (0, lowerQuote - upperQuote);
        } else if (curvePrice >= upperPrice) {
            return (upperBase - lowerBase, 0);
        } else {
            return (ambBase - lowerBase, ambQuote - upperQuote);
        }
    }

    function liquidityToTokens (CurveMath.CurveState memory curve, uint128 liq) 
                                internal pure returns (uint128 baseQty, uint128 quoteQty) {
        return liquidityToTokens(curve.priceRoot_, liq);
    }

    function liquidityToTokens (uint128 curvePrice, uint128 liq)
                                internal pure returns (uint128 baseQty, uint128 quoteQty) {
        baseQty = uint128(FixedPoint.mulQ64(liq, curvePrice));
        quoteQty = uint128(FixedPoint.divQ64(liq, curvePrice));        
    }
}