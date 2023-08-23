// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import "../libraries/PoolSpecs.sol";
import "../interfaces/IHaqqLpConduit.sol";
import "@rari-capital/solmate/src/tokens/ERC20.sol";

contract HaqqLpErc20 is ERC20, IHaqqLpConduit {

    bytes32 public immutable poolHash;
    address public immutable baseToken;
    address public immutable quoteToken;
    uint256 public immutable poolType;
    
    constructor (address base, address quote, uint256 poolIdx)
        ERC20 ("Haqq HaqqX LP ERC20 Token", "LP-HaqqAmb", 18) {

        require(quote != address(0) && base != quote && quote > base, "Invalid Token Pair");

        baseToken = base;
        quoteToken = quote;
        poolType = poolIdx;
        poolHash = PoolSpecs.encodeKey(base, quote, poolIdx);
    }
    
    function depositHaqqLiq (address sender, bytes32 pool,
                             int24 lowerTick, int24 upperTick, uint128 seeds,
                             uint64) public override returns (bool) {
        require(pool == poolHash, "Wrong pool");
        require(lowerTick == 0 && upperTick == 0, "Non-HaqqX LP Deposit");
        _mint(sender, seeds);
        return true;
    }

    function withdrawHaqqLiq (address sender, bytes32 pool,
                              int24 lowerTick, int24 upperTick, uint128 seeds,
                              uint64) public override returns (bool) {
        require(pool == poolHash, "Wrong pool");
        require(lowerTick == 0 && upperTick == 0, "Non-HaqqX LP Deposit");
        _burn(sender, seeds);
        return true;
    }

}