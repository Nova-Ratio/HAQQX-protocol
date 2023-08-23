// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

import "../HaqqSwapDex.sol";

contract HaqqDeployer {
    event HaqqDeploy(address addr, uint salt);

    address immutable owner_;
    address public dex_;

    constructor (address owner) {
        owner_ = owner;
    }

    function protocolCmd (address dex, uint16 proxyPath,
                          bytes calldata cmd, bool sudo) public {
        require(msg.sender == owner_, "Does not own deployer");
        HaqqSwapDex(dex).protocolCmd(proxyPath, cmd, sudo);
    }

    function getAddress(
        bytes memory bytecode,
        uint _salt
    ) public view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(bytecode))
        );

        return address(uint160(uint(hash)));
    }

    function deploy (bytes memory bytescode, uint salt) public returns (address) {
        dex_ = createContract(bytescode, salt);
        emit HaqqDeploy(dex_, salt);
        return dex_;
    }

    function createContract(bytes memory bytecode, uint _salt) internal returns (address addr) {
        assembly {
            addr := create2(
                0, 
                add(bytecode, 0x20),
                mload(bytecode), 
                _salt 
            )

            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
    }
}