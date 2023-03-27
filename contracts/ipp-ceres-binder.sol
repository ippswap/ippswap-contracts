// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import './libs/SafeMath.sol';
import './libs/IERC20.sol';
import './libs/SafeERC20.sol';
import './libs/ReentrancyGuard.sol';
import './libs/ICeresCore.sol';
import './libs/INameMapping.sol';
import './libs/CfoTakeableV2.sol';
import './libs/Adminable.sol';

contract CeresBinderV3 is CfoTakeableV2,Adminable,ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public immutable ceres;

    address public rewardsToken;

    uint public selfAmount;
    uint public parentAmount;
    uint public grandpAmount;

    uint256 public addRelationBNBFee = 5 * 1e15;

    mapping(address => bool) public exists;
    uint256 public totalAccount;

    constructor(
        address _ceres,
        address _reawrdsToken
    ){
        require(_ceres != address(0),"_ceres can not be address 0");
        ceres = _ceres;
        rewardsToken = _reawrdsToken;
        
        if(_reawrdsToken != address(0)){
           IERC20(_reawrdsToken).safeApprove(_ceres,type(uint256).max);
        }
    }

    function recordedUserCount() external view returns(uint){
        return totalAccount;
    }

    function isParent(address child,address parent) external view returns(bool){
        return ICeresCore(ceres).isParent(child, parent);
    }    
    
    function parentOf(address account) external view returns(address){
        return ICeresCore(ceres).parentOf(account);
    }

    function addRelation(address child,address parent) external payable nonReentrant {
        require(child == msg.sender,"child must be tx sender");
        require(msg.value >= addRelationBNBFee,"value too low");
        ICeresCore(ceres).addRelation(child, parent);

        _afterAddedRelation(child);
    }

    function _afterAddedRelation(address child) internal {

        address rewardToken_ = rewardsToken;
        if(rewardToken_ != address(0)){
            (uint selfAmount_,uint parentAmount_,uint grandpaAmount_) = (selfAmount,parentAmount,grandpAmount);
            uint totalAmount_ = selfAmount_.add(parentAmount_).add(grandpaAmount_);
            if(totalAmount_ > 0 && IERC20(rewardToken_).balanceOf(address(this)) >= totalAmount_){
                ICeresCore(ceres).distribute(rewardToken_, child, totalAmount_, 0,parentAmount_, grandpaAmount_);
            }
        }

        if(!exists[child]){
            totalAccount += 1;
            exists[child] = true;
        }
    }

    function setRewardsToken(address _rewardsToken) external onlyAdmin {
        address oldRewardToken = rewardsToken;
        require(oldRewardToken != _rewardsToken,"_rewardsToken can not be same as old");
        rewardsToken = _rewardsToken;
        if(_rewardsToken != address(0)){
            IERC20(_rewardsToken).safeApprove(ceres,type(uint256).max);
        }
    }

    function setRewardAmounts(uint _selfAmount,uint _parentAmount,uint _grandpaAmount) public onlyAdmin {
        selfAmount = _selfAmount;
        parentAmount = _parentAmount;
        grandpAmount = _grandpaAmount;
    }

    function setAddRelationBNBFee(uint _fee) external onlyAdmin {
        addRelationBNBFee = _fee;
    }
}