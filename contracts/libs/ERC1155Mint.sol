
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '../libs/Ownable.sol';
import '../libs/ERC1155Supply.sol';

abstract contract ERC1155Mint is ERC1155Supply {

    mapping(address => bool) private _minters;

    modifier onlyMinter {
        require(_minters[msg.sender],"Mintable: forbidden");
        _;
    }

    

}