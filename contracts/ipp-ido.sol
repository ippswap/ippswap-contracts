// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import './libs/SafeMath.sol';
import './libs/IERC20.sol';
import './libs/SafeERC20.sol';
import './libs/ReentrancyGuard.sol';
import './libs/Pausable.sol';
import './libs/ICeresCore.sol';
import './libs/CfoTakeableV2.sol';
import './libs/Adminable.sol';

contract LPPIdo is CfoTakeableV2,Adminable,Pausable,ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable usdtToken;
    ICeresCore public immutable ceres;
    
    mapping(address => uint256) public userInvestOf;
    mapping(uint256 => uint256) public periodTotalInvestOf;
    uint public totalPaidUsdt;
    uint public totalPaidAccount;

    uint public payUsdtAmount = 1000 * 1e18;
    uint public maxPeriodInvest = 1000000 * 1e18;
    uint public periodDuration = 86400;

    uint public startTime;
    uint public endTime;

    address public incomeTo = address(this);

    event Invested(address account,uint usdtAmount,uint blockTime);

    modifier nonContract {
        require(!Address.isContract(msg.sender),"caller can not be contract");
        _;
    }

    constructor(
        address _usdt,
        address _ceres
    ){
        usdtToken = _usdt;
        ceres = ICeresCore(_ceres);
    }

    function invest() external payable nonContract nonReentrant whenNotPaused {
        require(incomeTo != address(0),"incomeTo not setted");
        require(ceres.parentOf(msg.sender)!=address(0),"caller has not parent");
        require(block.timestamp >= startTime,"ido not start");
        require(block.timestamp < endTime,"ido ended");
        require(userInvestOf[msg.sender]==0,"invested");

        uint payUsdtAmount_ = payUsdtAmount;
        uint periodStart = calcPeriodStart(block.timestamp, periodDuration);
        require(periodTotalInvestOf[periodStart].add(payUsdtAmount_) <= maxPeriodInvest,"period invest limited");

        IERC20(usdtToken).safeTransferFrom(msg.sender,incomeTo,payUsdtAmount_);
        userInvestOf[msg.sender] = payUsdtAmount_;
        periodTotalInvestOf[periodStart] = periodTotalInvestOf[periodStart].add(payUsdtAmount_);
        totalPaidUsdt = totalPaidUsdt.add(payUsdtAmount_);
        totalPaidAccount = totalPaidAccount.add(1);

        emit Invested(msg.sender,payUsdtAmount_,block.timestamp);
    }

    function infos(address account) external view returns(
        uint _totalPaidUsdt,
        uint _totalPaidAccount,
        uint _startTime,
        uint _endTime,
        uint _payUsdtAmount,
        uint _maxPeriodInvest,
        uint _userInvestAmount,
        uint _periodTotalInvestAmount
    ){
        _totalPaidUsdt = totalPaidUsdt;
        _totalPaidAccount = totalPaidAccount;
        _startTime = startTime;
        _endTime = endTime;
        _payUsdtAmount = payUsdtAmount;
        _maxPeriodInvest = maxPeriodInvest;
        _userInvestAmount = userInvestOf[account];
        _periodTotalInvestAmount = periodTotalInvestOf[calcPeriodStart(block.timestamp, periodDuration)];
    }

    function calcPeriodStart(uint _utcTime,uint _periodDuration) internal pure returns(uint){
        uint utcPeriodStart = _utcTime - (_utcTime % _periodDuration);

        return utcPeriodStart - 28800;
    }

    function setTimes(uint _startTime,uint _endTime) external onlyAdmin {
        require(_startTime <= _endTime,"start time can not greater than end time");
        startTime = _startTime;
        endTime = _endTime;
    }

    function setPayUsdtAmount(uint _payUsdtAmount) external onlyAdmin {
        payUsdtAmount = _payUsdtAmount;
    }

    function setMaxPeriodInvest(uint _maxPeriodInvest) external onlyAdmin {
        maxPeriodInvest = _maxPeriodInvest;
    }

    function setIncomeTo(address _incomeTo) external onlyOwner {
        require(_incomeTo != address(0),"incomeTo can not be address 0");
        incomeTo = _incomeTo;
    }

    function setPeriodDuration(uint duration) external onlyOwner {
        require(duration>0,"duration can not be 0");
        periodDuration = duration;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}