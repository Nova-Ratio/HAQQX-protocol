// SPDX-License-Identifier: GPL-3 

pragma solidity 0.8.19;

import '../libraries/Directives.sol';

interface IHaqqPermitOracle {

    function checkApprovedForHaqqPool (address user, address sender,
                                       address base, address quote,
                                       Directives.HaqqXDirective calldata haqqx,
                                       Directives.SwapDirective calldata swap,
                                       Directives.ConcentratedDirective[] calldata concs,
                                       uint16 poolFee)
        external returns (uint16 discount);

    function checkApprovedForHaqqSwap (address user, address sender,
                                       address base, address quote,
                                       bool isBuy, bool inBaseQty, uint128 qty,
                                       uint16 poolFee)
        external returns (uint16 discount);

    function checkApprovedForHaqqMint (address user, address sender,
                                       address base, address quote,
                                       int24 bidTick, int24 askTick, uint128 liq)
        external returns (bool);

    function checkApprovedForHaqqBurn (address user, address sender,
                                       address base, address quote,
                                       int24 bidTick, int24 askTick, uint128 liq)
        external returns (bool);

    function checkApprovedForHaqqInit (address user, address sender,
                                       address base, address quote, uint256 poolIdx)
        external returns (bool);

    function acceptsPermitOracle() external returns (bool);
}
