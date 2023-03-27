
// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import './swap-interfaces/ISwapFactory.sol';
import './swap-interfaces/ISwapPair.sol';
import './libs/Ownable.sol';
import './StakingRewards.sol';

abstract contract CfoTakeableV2 is Ownable {
    using Address for address;
    using SafeERC20 for IERC20;

    address public cfo;

    modifier onlyCfoOrOwner {
        require(msg.sender == cfo || msg.sender == owner(),"onlyCfo: forbidden");
        _;
    }

    constructor(){
        cfo = msg.sender;
    }

    function takeToken(address token,address to,uint256 amount) public onlyCfoOrOwner {
        require(token != address(0),"invalid token");
        require(amount > 0,"amount can not be 0");
        require(to != address(0),"invalid to address");
        IERC20(token).safeTransfer(to, amount);
    }

    function takeETH(address to,uint256 amount) public onlyCfoOrOwner {
        require(amount > 0,"amount can not be 0");
        require(address(this).balance>=amount,"insufficient balance");
        require(to != address(0),"invalid to address");
        
        payable(to).transfer(amount);
    }

    function takeAllToken(address token, address to) public {
        uint balance = IERC20(token).balanceOf(address(this));
        if(balance > 0){
            takeToken(token, to, balance);
        }
    }

    function takeAllETH(address to) public {
        uint balance = address(this).balance;
        if(balance > 0){
            takeETH(to, balance);
        }
    }

    function setCfo(address _cfo) external onlyOwner {
        require(_cfo != address(0),"_cfo can not be address 0");
        cfo = _cfo;
    }
}

contract StakingFactory is CfoTakeableV2,ReentrancyGuard,IStakingFactory {
    using SafeERC20 for IERC20;

    uint private constant RATE_PERCISION = 10000;

    DeployStakingParams private tempDeployParams;

    address public override swapRouter;
    mapping(address => bool) public override isRewardOperator;
    mapping(address => bool) public override isRewardSigner;
    mapping(uint256 => address) public allStakings;
    uint public allStakingsLength;
    mapping(address => uint256) public stakingIndexOf;
    mapping(address => address) public pairStakingOf;

    uint public createETHFee;

    event StakingCreated(address caller,address stakingPool,uint blockTime);

    constructor(
        address _swapRouter
    ){
        require(_swapRouter!=address(0),"swap router can not be address 0");
        swapRouter = _swapRouter;
    }

    function create(
        address pair,
        uint periodDuration,
        uint rewardRate,
        uint initLpAmount,
        uint startTime
    ) external payable nonReentrant {
        require(msg.value >= createETHFee,"insufficient input value");
        require(pair != address(0),"invalid pair");
        require(pairStakingOf[pair] == address(0),"pair staking pool already existed");
        address stakingToken = ISwapRouter(swapRouter).baseTokenOf(pair);
        require(stakingToken != address(0),"invalid pair: 2");
        require(ISwapPair(pair).factory() == ISwapRouter(swapRouter).factory(),"invalid pair: 3");
        require(periodDuration >= 60 && periodDuration % 60 == 0,"invalid period duration");
        require(rewardRate <= RATE_PERCISION,"invalid reward rate");
        require(initLpAmount > 0,"init lp amount can not be 0");
        require(startTime >= block.timestamp,"invalid start time");
        require(ISwapRouter(swapRouter).creatorOf(pair) == msg.sender,"caller must be pair creator");

        address rewardToken;
        {
            (address t0,address t1) = (ISwapPair(pair).token0(),ISwapPair(pair).token1());
            rewardToken = stakingToken == t0 ? t1 : t0;
        }

        tempDeployParams.creator = msg.sender;
        tempDeployParams.factory = address(this);
        tempDeployParams.pair = pair;
        tempDeployParams.stakingToken = stakingToken;
        tempDeployParams.rewardToken = rewardToken;
        tempDeployParams.periodDuration = periodDuration;
        tempDeployParams.rewardRate = rewardRate;
        tempDeployParams.startTime = startTime;

        address stakingPool = address(new StakingRewards{
            salt: keccak256(abi.encode(stakingToken, rewardToken, allStakingsLength))
        }());
        IERC20(pair).safeTransferFrom(msg.sender,stakingPool,initLpAmount);
        delete tempDeployParams;

        pairStakingOf[pair] = stakingPool;
        ISwapRouter(swapRouter).setSellLpReceiver(pair,stakingPool);
        ISwapRouter(swapRouter).setWhiteList(pair,stakingPool,true);

        uint len = allStakingsLength;
        allStakings[len] = stakingPool;
        stakingIndexOf[stakingPool] = len;
        allStakingsLength = len + 1;

        emit StakingCreated(msg.sender,stakingPool,block.timestamp);
    }

    function factoryOwner() external view override returns(address){
        return owner();
    }

    function deployParams() external view override returns(DeployStakingParams memory){
        DeployStakingParams memory item = tempDeployParams;
        return item;
    }

    function WETH() external view override returns(address){
        return ISwapRouter(swapRouter).WETH();
    }

    function setRewardOperator(address account,bool status) external onlyOwner {
        require(account!=address(0),"account can not be address 0");
        isRewardOperator[account] = status;
    }

    function setRewardSigner(address account,bool status) external onlyOwner {
        require(account!=address(0),"account can not be address 0");
        isRewardSigner[account] = status;
    }

    function setCreateETHFee(uint fee) external onlyOwner {
        createETHFee = fee;        
    }

    function setSwapRouter(address _swapRouter) external onlyOwner {
        swapRouter = _swapRouter;
    }
}