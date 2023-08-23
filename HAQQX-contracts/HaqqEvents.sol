// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

library HaqqEvents {
    event TreasurySet (address indexed treasury, uint64 indexed startTime);

    event ProtocolDividend (address indexed token, address indexed recv);

    event UpgradeProxy (address indexed proxy, uint16 proxyIdx);

    event HotPathOpen (bool);

    event SafeMode (bool);

    event AuthorityTransfer (address indexed authority);

    event SetNewPoolLiq (uint128 liq);

    event SetTakeRate (uint8 takeRate);

    event SetRelayerTakeRate (uint8 takeRate);

    event DisablePoolTemplate (uint256 indexed poolIdx);

    event SetPoolTemplate (uint256 indexed poolIdx, uint16 feeRate, uint16 tickSize,
                           uint8 jitThresh, uint8 knockout, uint8 oracleFlags);

    event ResyncTakeRate (address indexed base, address indexed quote,
                          uint256 indexed poolIdx, uint8 takeRate);

    event PriceImproveThresh (address indexed token, uint128 unitTickCollateral,
                              uint16 awayTickTol);
}
