// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface INameMapping {
    function getTokenId(string calldata name) external pure returns(uint256);

    function getNameMapTo(string calldata name) external view returns(address);

    function preferenceName(address account) external view returns(string memory);
}