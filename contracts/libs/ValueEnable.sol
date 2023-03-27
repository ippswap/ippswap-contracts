// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import '../libs/Ownable.sol';

abstract contract ValueEnable is Ownable {

    mapping(bytes32 => uint256) public funcValueOf;

    modifier verifyValue(string memory funcName) {
        require(msg.value >= funcValueOf[_funcKey(funcName)],"verifyValue: insufficient input value");
        _;
    }

    function setFuncValue(string memory funcName, uint val) external onlyOwner {
        require(bytes(funcName).length > 0,"funcName can not be empty");

        funcValueOf[_funcKey(funcName)] = val;
    }

    function _funcKey(string memory funcName) internal pure returns(bytes32) {
        return keccak256(bytes(funcName));
    }
    
}