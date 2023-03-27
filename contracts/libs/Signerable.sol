// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './Ownable.sol';

abstract contract Signerable is Ownable {

    mapping(address => bool) public isSigner;

    modifier onlySigner {
        require(isSigner[msg.sender],"onlyAdmin: forbidden");
        _;
    }

    function addSigner(address account) external onlyOwner {
        require(account != address(0),"account can not be address 0");
        isSigner[account] = true;
    }

    function removeSigner(address account) external onlyOwner {
        require(account != address(0),"account can not be address 0");
        isSigner[account] = false;
    }
}