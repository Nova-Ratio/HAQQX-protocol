// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import '../libraries/Directives.sol';
import '../libraries/Encoding.sol';
import '../libraries/TokenFlow.sol';
import '../libraries/PriceGrid.sol';
import '../libraries/Chaining.sol';
import '../mixins/SettleLayer.sol';
import '../mixins/PoolRegistry.sol';
import '../mixins/MarketSequencer.sol';
import '../mixins/StorageLayout.sol';

contract MicroPaths is MarketSequencer {
    
    function acceptHaqqProxyRole (address, uint16 slot) public pure returns (bool) {
        return slot == HaqqSlots.MICRO_PROXY_IDX;
    }
   
    function burnRange (uint128 price, int24 priceTick, uint128 seed, uint128 conc,
                        uint64 seedGrowth, uint64 concGrowth,
                        int24 lowTick, int24 highTick, uint128 liq, bytes32 poolHash)
        public payable returns (int128 baseFlow, int128 quoteFlow,
                        uint128 seedOut, uint128 concOut) {
        CurveMath.CurveState memory curve;
        curve.priceRoot_ = price;
        curve.haqqxSeeds_ = seed;
        curve.concLiq_ = conc;
        curve.seedDeflator_ = seedGrowth;
        curve.concGrowth_ = concGrowth;
        
        (baseFlow, quoteFlow) = burnRange(curve, priceTick, lowTick, highTick,
                                          liq, poolHash, lockHolder_);

        concOut = curve.concLiq_;
        seedOut = curve.haqqxSeeds_;
    }
     
    function mintRange (uint128 price, int24 priceTick, uint128 seed, uint128 conc,
                        uint64 seedGrowth, uint64 concGrowth,
                        int24 lowTick, int24 highTick, uint128 liq, bytes32 poolHash)
        public payable returns (int128 baseFlow, int128 quoteFlow,
                        uint128 seedOut, uint128 concOut) {
        CurveMath.CurveState memory curve;
        curve.priceRoot_ = price;
        curve.haqqxSeeds_ = seed;
        curve.concLiq_ = conc;
        curve.seedDeflator_ = seedGrowth;
        curve.concGrowth_ = concGrowth;
        
        (baseFlow, quoteFlow) = mintRange(curve, priceTick, lowTick, highTick, liq,
                                          poolHash, lockHolder_);

        concOut = curve.concLiq_;
        seedOut = curve.haqqxSeeds_;
    }
       
    function burnHaqqX (uint128 price, uint128 seed, uint128 conc,
                          uint64 seedGrowth, uint64 concGrowth,
                          uint128 liq, bytes32 poolHash)
        public payable returns (int128 baseFlow, int128 quoteFlow, uint128 seedOut) {
        CurveMath.CurveState memory curve;
        curve.priceRoot_ = price;
        curve.haqqxSeeds_ = seed;
        curve.concLiq_ = conc;
        curve.seedDeflator_ = seedGrowth;
        curve.concGrowth_ = concGrowth;
        
        (baseFlow, quoteFlow) = burnHaqqX(curve, liq, poolHash, lockHolder_);
        
        seedOut = curve.haqqxSeeds_;
    }
       
    function mintHaqqX (uint128 price, uint128 seed, uint128 conc,
                          uint64 seedGrowth, uint64 concGrowth,
                          uint128 liq, bytes32 poolHash)
        public payable returns (int128 baseFlow, int128 quoteFlow, uint128 seedOut) {
        CurveMath.CurveState memory curve;
        curve.priceRoot_ = price;
        curve.haqqxSeeds_ = seed;
        curve.concLiq_ = conc;
        curve.seedDeflator_ = seedGrowth;
        curve.concGrowth_ = concGrowth;
        
        (baseFlow, quoteFlow) = mintHaqqX(curve, liq, poolHash, lockHolder_);

        seedOut = curve.haqqxSeeds_;
    }

    function sweepSwap (CurveMath.CurveState memory curve, int24 midTick,
                        Directives.SwapDirective memory swap,
                        PoolSpecs.PoolCursor memory pool)
        public payable returns (Chaining.PairFlow memory accum,
                                uint128 priceOut, uint128 seedOut, uint128 concOut,
                                uint64 haqqxOut, uint64 concGrowthOut) {
        sweepSwapLiq(accum, curve, midTick, swap, pool);
        
        priceOut = curve.priceRoot_;
        seedOut = curve.haqqxSeeds_;
        concOut = curve.concLiq_;
        haqqxOut = curve.seedDeflator_;
        concGrowthOut = curve.concGrowth_;
    }
}