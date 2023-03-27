// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './Ownable.sol';
import './ERC721Permit.sol';
import './IERC721Mint.sol';

abstract contract ERC721Mintable is Ownable,ERC721Permit,IERC721Mint {
    mapping(address => bool) private _minters;

    modifier onlyMinter {
        require(_minters[msg.sender],"ERC721Mintable: forbidden");
        _;
    }

    function addMinter(address minter) public virtual onlyOwner {
        require(minter != address(0),"ERC721Mintable: invalid minter");
        _minters[minter] = true;
    }

    function removeMinter(address minter) public virtual onlyOwner {
        require(minter != address(0),"ERC721Mintable: invalid minter");
        _minters[minter] = false;
    }

    function isMinter(address minter) public view virtual override returns(bool) {
        return _minters[minter];
    }

    function safeMint(address to,uint tokenId) public virtual override onlyMinter returns(bool){
        _safeMint(to, tokenId);

        return true;
    }
}