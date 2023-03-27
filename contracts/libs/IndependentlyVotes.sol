// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './ChainId.sol';

abstract contract IndependentlyVotes {    

    mapping(address => uint256) private _nonces;
    mapping(address => uint96) public originVotesOf;

    mapping (address => uint32) private _numCheckpoints;

    bytes32 private immutable _HASHED_NAME;

    bytes32 private immutable _HASHED_VERSION;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 private constant _DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 private constant _DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    mapping(address => address) public delegates;
    mapping (address => mapping (uint32 => Checkpoint)) private _checkpoints;
    Checkpoint[] private _totalVotesCheckpoints;

    struct Checkpoint {
        uint32 fromBlock;
        uint96 votes;
    }

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    constructor(
        string memory _name,
        string memory _version
    ){
        _HASHED_NAME = keccak256(bytes(_name));
        _HASHED_VERSION = keccak256(bytes(_version));
    }

    function _transferVotes(address from,address to,uint96 voteAmount) internal {
        require(originVotesOf[from] >= voteAmount,"_transferVotes: vote amount exceeds hold votes");
        originVotesOf[from] = _sub96(originVotesOf[from],voteAmount,"_transferVotes: vote amount underflows");
        originVotesOf[to] = _add96(originVotesOf[to],voteAmount,"_transferVotes: vote amount underflows");

        _moveDelegates(delegates[from], delegates[to], voteAmount);
    }

    function _mintVotes(address to,uint96 voteAmount) internal {
        require(to!=address(0),"_mintVotes: to can not be zero address");
        originVotesOf[to] = _add96(originVotesOf[to],voteAmount,"_transferVotes: vote amount underflows");

        _moveDelegates(address(0), delegates[to], voteAmount);   
        _writeTotalVotesCheckpoint(voteAmount,true);
    }

    function _burnVotes(address account,uint96 voteAmount) internal {
        require(originVotesOf[account] >= voteAmount,"_burnVotes: exceeds hold votes");
        originVotesOf[account] = _sub96(originVotesOf[account],voteAmount,"_burnVotes: vote amount underflows");

        _moveDelegates(delegates[account],address(0), voteAmount);
        _writeTotalVotesCheckpoint(voteAmount,false);
    }

    function _writeTotalVotesCheckpoint(uint96 delta,bool isAdd) internal {
        uint256 pos = _totalVotesCheckpoints.length;
        uint96 oldWeight = pos == 0 ? 0 : _totalVotesCheckpoints[pos - 1].votes;
        uint96 newWeight = isAdd ? _add96(oldWeight,delta,"_writeTotalVotesCheckpoint: vote amount underflows") : _sub96(oldWeight,delta,"_writeTotalVotesCheckpoint: vote amount underflows");

        uint32 blockNumber = _safe32(block.number, "_writeCheckpoint: block number exceeds 32 bits");
        if (pos > 0 && _totalVotesCheckpoints[pos - 1].fromBlock == blockNumber) {
            _totalVotesCheckpoints[pos - 1].votes = newWeight;
        } else {            
            _totalVotesCheckpoints.push(Checkpoint({fromBlock: blockNumber, votes: newWeight}));
        }
    }

    function checkpoints(address account, uint32 pos) public view virtual returns (Checkpoint memory) {
        return _checkpoints[account][pos];
    }

    function numCheckpoints(address account) public view virtual returns (uint32) {
        return _numCheckpoints[account];
    }

    function getCurrentTotalVotes() public view returns(uint96) {
        return _totalVotesCheckpoints.length == 0 ? 0 : _totalVotesCheckpoints[_totalVotesCheckpoints.length - 1].votes;
    }

    function getPastTotalVotes(uint256 blockNumber) public view returns (uint96) {
        require(blockNumber < block.number, "getPastTotalSupply: block not yet mined");

        uint256 high = _totalVotesCheckpoints.length;
        uint256 low = 0;
        while (low < high) {
            uint256 mid = high - (high - low) / 2;
            if (_totalVotesCheckpoints[mid].fromBlock > blockNumber) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return high == 0 ? 0 : _totalVotesCheckpoints[high - 1].votes;
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(address delegatee, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(_DOMAIN_TYPEHASH, _HASHED_NAME, ChainId.get(), address(this)));
        bytes32 structHash = keccak256(abi.encode(_DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "delegateBySig: invalid signature");
        require(nonce == _nonces[signatory]++, "delegateBySig: invalid nonce");
        require(block.timestamp <= expiry, "delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint96) {
        uint32 nCheckpoints = _numCheckpoints[account];
        return nCheckpoints > 0 ? _checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber) public view returns (uint96) {
        require(blockNumber < block.number, "getPriorVotes: not yet determined");

        uint32 nCheckpoints = _numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (_checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return _checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (_checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = _checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return _checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        //require(delegatee != address(this),"can not delegate to this contract");
        address currentDelegate = delegates[delegator];
        uint96 delegatorBalance = originVotesOf[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint96 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = _numCheckpoints[srcRep];
                uint96 srcRepOld = srcRepNum > 0 ? _checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint96 srcRepNew = _sub96(srcRepOld, amount, "_moveVotes: vote amount underflows");
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = _numCheckpoints[dstRep];
                uint96 dstRepOld = dstRepNum > 0 ? _checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint96 dstRepNew = _add96(dstRepOld, amount, "_moveVotes: vote amount overflows");
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint96 oldVotes, uint96 newVotes) internal {
      uint32 blockNumber = _safe32(block.number, "_writeCheckpoint: block number exceeds 32 bits");

      if (nCheckpoints > 0 && _checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
          _checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
      } else {
          _checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
          _numCheckpoints[delegatee] = nCheckpoints + 1;
      }

      emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function _safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function _safe96(uint n, string memory errorMessage) internal pure returns (uint96) {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    function _add96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function _sub96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }
}