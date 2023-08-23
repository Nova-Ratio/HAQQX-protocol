// SPDX-License-Identifier: GPL-3 

pragma solidity 0.8.19;

import '../libraries/CurveCache.sol';

interface IHaqqMinion {

    function protocolCmd (uint16 proxyPath, bytes calldata cmd, bool sudo)
        payable external;
}

interface IHaqqMaster {
    
    function acceptsHaqqAuthority() external returns (bool);
}