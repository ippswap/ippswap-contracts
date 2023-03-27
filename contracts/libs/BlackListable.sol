//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './Ownable.sol';

abstract contract BlackListable is Ownable {

    /////// Getters to allow the same blacklist to be used also by other contracts (including upgraded Tether) ///////
    function getBlackListStatus(address _maker) public view returns (bool) {
        return isBlackListed[_maker];
    }

    mapping (address => bool) public isBlackListed;
    
    function addBlackList(address _evilUser) public onlyOwner {
        isBlackListed[_evilUser] = true;
        emit AddedBlackList(_evilUser);
    }

    function removeBlackList(address _clearedUser) public onlyOwner {
        isBlackListed[_clearedUser] = false;
        emit RemovedBlackList(_clearedUser);
    }

    modifier notBlackListed {
        require(!isBlackListed[_msgSender()],"BlackListable: blacklisted");
        _;
    }

    event AddedBlackList(address _user);

    event RemovedBlackList(address _user);

}