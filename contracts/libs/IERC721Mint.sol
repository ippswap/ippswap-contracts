// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IERC721Mint {
    function isMinter(address minter) external view returns(bool);

    function safeMint(address to,uint tokenId) external returns(bool);
}