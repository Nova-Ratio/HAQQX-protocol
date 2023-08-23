// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import "../interfaces/IHaqqXPermitOracle.sol";

contract MockPermit is IHaqqXPermitOracle {

    address public user_;
    address public base_;
    address public quote_;
    address public sender_;
    bool public passThru_;

    bool public isBuySnap_;
    bool public inBaseQtySnap_;
    uint128 public qtySnap_;
    int24 public bidTickSnap_;
    int24 public askTickSnap_;
    uint128 public liqSnap_;
    uint8 public codeSnap_;
    uint16 public poolFee_;
    uint256 public poolIdx_;
    
    function setMatching (address user, address base, address quote) public {
        user_ = user;
        base_ = base;
        quote_ = quote;
    }

    function setPassThru (bool passThru) public {
        passThru_ = passThru;
    }
        

    function checkApprovedForHaqqXPool (address user, address sender,
                                       address base, address quote,
                                       Directives.HaqqDirective calldata,
                                       Directives.SwapDirective calldata,
                                       Directives.ConcentratedDirective[] calldata,
                                       uint16 poolFee)
        external override returns (uint16 discount) {
        if (passThru_) { return 1; }
        codeSnap_ = 1;
        sender_ = sender;
        poolFee_ = poolFee;
        discount = (user == user_ && base == base_ && quote_ == quote) ? 1 : 0;
     }

    function checkApprovedForHaqqXSwap (address user, address sender,
                                       address base, address quote,
                                       bool isBuy, bool inBaseQty, uint128 qty,
                                       uint16 poolFee)
        external override returns (uint16 discount) {
        if (passThru_) { return 1; }
        sender_ = sender;
        codeSnap_ = 2;
        isBuySnap_ = isBuy;
        inBaseQtySnap_ = inBaseQty;
        qtySnap_ = qty;
        poolFee_ = poolFee;
        discount = (user == user_ && base == base_ && quote_ == quote) ? 1 : 0;
    }

    function checkApprovedForHaqqXMint (address user, address sender,
                                       address base, address quote,
                                       int24 bidTick, int24 askTick, uint128 liq)
         external override returns (bool) {
         if (passThru_) { return true; }
         codeSnap_ = 3;
         sender_ = sender;
         bidTickSnap_ = bidTick;
         askTickSnap_ = askTick;
         liqSnap_ = liq;
         return user == user_ && base == base_ && quote_ == quote;
     }

    function checkApprovedForHaqqXBurn (address user, address sender,
                                       address base, address quote,
                                       int24 bidTick, int24 askTick, uint128 liq)
         external override returns (bool) {
         if (passThru_) { return true; }
         sender_ = sender;
         bidTickSnap_ = bidTick;
         askTickSnap_ = askTick;
         liqSnap_ = liq;
         codeSnap_ = 4;                 
         return user == user_ && base == base_ && quote_ == quote;
     }

    function checkApprovedForHaqqXInit (address user, address sender,
                                       address base, address quote, uint256 poolIdx)
         external override returns (bool) {
         if (passThru_) { return true; }
         sender_ = sender;
         codeSnap_ = 5;
         poolIdx_ = poolIdx;
         return user == user_ && base == base_ && quote_ == quote;
     }

     /* @notice Just used to validate the contract address at pool creation time. */
    function acceptsPermitOracle() external pure override returns (bool) { return true; }
}
