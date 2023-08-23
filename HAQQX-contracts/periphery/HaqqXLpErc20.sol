// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import "../libraries/PoolSpecs.sol";
import "../interfaces/IHaqqXLpConduit.sol";
import "@rari-capital/solmate/src/tokens/ERC20.sol";

contract HaqqXLpErc20 is ERC20, IHaqqXLpConduit {

    bytes32 public immutable poolHash;
    address public immutable baseToken;
    address public immutable quoteToken;
    uint256 public immutable poolType;
    
    constructor (address base, address quote, uint256 poolIdx)
        ERC20 ("HaqqX Haqq LP ERC20 Token", "LP-HaqqXAmb", 18) {

        // HaqqXSwap protocol uses 0x0 for native ETH, so it's possible that base
        // token could be 0x0, which means the pair is against native ETH. quote
        // will never be 0x0 because native ETH will always be the base side of
        // the pair.
        require(quote != address(0) && base != quote && quote > base, "Invalid Token Pair");

        baseToken = base;
        quoteToken = quote;
        poolType = poolIdx;
        poolHash = PoolSpecs.encodeKey(base, quote, poolIdx);
    }
    
    function depositHaqqXLiq (address sender, bytes32 pool,
                             int24 lowerTick, int24 upperTick, uint128 seeds,
                             uint64) public override returns (bool) {
        require(pool == poolHash, "Wrong pool");
        require(lowerTick == 0 && upperTick == 0, "Non-Haqq LP Deposit");
        _mint(sender, seeds);
        return true;
    }

    function withdrawHaqqXLiq (address sender, bytes32 pool,
                              int24 lowerTick, int24 upperTick, uint128 seeds,
                              uint64) public override returns (bool) {
        require(pool == poolHash, "Wrong pool");
        require(lowerTick == 0 && upperTick == 0, "Non-Haqq LP Deposit");
        _burn(sender, seeds);
        return true;
    }

}
