
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './ERC721Enumerable.sol';
import './IERC721Permit.sol';
import './ChainId.sol';
import './IERC1271.sol';

abstract contract ERC721Permit is ERC721Enumerable,IERC721Permit {
    mapping(uint256 => uint256) private _nonces;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the permit struct used by the contract
    // permit(address spender, uint tokenId, uint deadline, uint8 v, bytes32 r, bytes32 s)
    bytes32 public constant override PERMIT_TYPEHASH = keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)");

    bytes32 private immutable _nameHash;

    bytes32 private immutable _versionHash;

    function DOMAIN_SEPARATOR() public view virtual override returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, _nameHash,_versionHash, ChainId.get(), address(this)));
    }

    constructor(
        string memory name_,
        string memory symbol_,
        string memory version_
    ) ERC721(name_,symbol_) {
        _nameHash = keccak256(bytes(name_));
        _versionHash = keccak256(bytes(version_));
    }

    function nonce(uint256 tokenId) public virtual view returns(uint256){
        return _nonces[tokenId];
    }

    function permit(address spender, uint tokenId, uint deadline, uint8 v, bytes32 r, bytes32 s) public virtual override {
        require(block.timestamp <= deadline, 'Permit expired');

        bytes32 digest =
            keccak256(
                abi.encodePacked(
                    '\x19\x01',
                    DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, spender, tokenId, _nonces[tokenId]++, deadline))
                )
            );
        address owner = ownerOf(tokenId);
        require(spender != owner, 'ERC721Permit: approval to current owner');

        if (Address.isContract(owner)) {
            require(IERC1271(owner).isValidSignature(digest, abi.encodePacked(r, s, v)) == 0x1626ba7e, 'Unauthorized');
        } else {
            address recoveredAddress = ecrecover(digest, v, r, s);
            require(recoveredAddress != address(0), 'Invalid signature');
            require(recoveredAddress == owner, 'Unauthorized');
        }

        _approve(spender, tokenId);
    }
}