// SPDX-License-Identifier: GPL-3 

pragma solidity 0.8.19;

import '../libraries/Directives.sol';

interface IHaqqLpConduit {

    function depositHaqqLiq (address sender, bytes32 poolHash,
                             int24 lowerTick, int24 upperTick,
                             uint128 liq, uint64 mileage) external returns (bool);

    function withdrawHaqqLiq (address sender, bytes32 poolHash,
                              int24 lowerTick, int24 upperTick,
                              uint128 liq, uint64 mileage) external returns (bool);
}
