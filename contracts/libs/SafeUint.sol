// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library SafeUint {
    function safe8(uint n) internal pure returns (uint8) {
        require(n < 2**8, "number overflow uint16");
        return uint8(n);
    }

    function safe16(uint n) internal pure returns (uint16) {
        require(n < 2**16, "number overflow uint16");
        return uint16(n);
    }

    function safe24(uint n) internal pure returns (uint24) {
        require(n < 2**24, "number overflow uint24");
        return uint24(n);
    }    

    function safe32(uint n) internal pure returns (uint32) {
        require(n < 2**32, "number overflow uint32");
        return uint32(n);
    }

    function safe64(uint n) internal pure returns (uint64) {
        require(n < 2**64, "number overflow uint64");
        return uint64(n);
    }

    function safe96(uint n) internal pure returns (uint96) {
        require(n < 2**96, "number overflow uint96");
        return uint96(n);
    }
}