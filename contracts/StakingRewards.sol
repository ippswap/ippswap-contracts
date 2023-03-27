
// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import './swap-interfaces/IWETH.sol';
import './swap-interfaces/ISwapRouter.sol';
import './interfaces/IStakingFactory.sol';
import './interfaces/IDeployStakingParams.sol';
import './libs/ReentrancyGuard.sol';
import './libs/SafeERC20.sol';
import './libs/SafeMath.sol';
import './libs/Pausable.sol';

contract StakingRewards is Pausable,ReentrancyGuard,IDeployStakingParams {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint private constant RATE_PERCISION = 10000;
    // address private constant ETHAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    address private immutable factory;
    address private creator;
    address private immutable pair;
    address private immutable stakingToken;
    address private immutable rewardToken;
    uint private immutable periodDuration;
    uint private rewardRate;
    uint private immutable startTime;

    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant WITHDRAW_REWARDS_PERMIT_TYPEHASH = keccak256("claim(address account,address token,uint256 amount,uint256 rand)");
    bytes32 public constant NOTIFY_REWARDS_PERMIT_TYPEHASH = keccak256("notifyRewards(uint256 epoch)");
    bytes32 public immutable DOMAIN_SEPARATOR;

    mapping(address => uint256) public stakedOf;
    mapping(uint256 => bool) public isUsedRand;
    mapping(uint256 => bool) public isNotifiedEpoch;

    event Staked(address user,uint amount,uint blockTime);
    event RewardPaid(address user, address token,uint256 reward,uint rand,uint blockTime);
    event SwapedRewards(uint removedLpAmount,uint remainLpAmount,uint rewardAmount, uint blockTime);

    modifier onlyCreator() {
        require(msg.sender == creator,"caller must be creator");
        _;
    }

    constructor() {        
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("StakingRewards")), block.chainid, address(this)));

        DeployStakingParams memory paras = IStakingFactory(msg.sender).deployParams();
        factory = paras.factory;
        creator = paras.creator;
        pair = paras.pair;
        stakingToken = paras.stakingToken;
        rewardToken = paras.rewardToken;
        periodDuration = paras.periodDuration;
        rewardRate = paras.rewardRate;
        startTime = paras.startTime;

        address router = IStakingFactory(msg.sender).swapRouter();
        IERC20(paras.stakingToken).safeApprove(router,type(uint256).max); 
        IERC20(paras.rewardToken).safeApprove(router,type(uint256).max);
        IERC20(paras.pair).safeApprove(router,type(uint256).max);
    }

    function stake(uint amount) external payable whenNotPaused nonReentrant {
        require(amount > 0,"amount can not be 0");
        require(block.timestamp >= startTime,"not start");
        uint receivedAmount = _transferFrom(msg.sender,stakingToken,amount);

        _addLiquidity(receivedAmount);
        stakedOf[msg.sender] = stakedOf[msg.sender].add(receivedAmount);

        emit Staked(msg.sender, receivedAmount, block.timestamp);
    }

    function claim(address account, uint amount,uint rand,uint8 v,bytes32 r,bytes32 s) external whenNotPaused nonReentrant {
        require(account != address(0),"account can not be address 0");
        require(amount > 0,"amount can not be 0");
        require(rand > 0,"rand can not be 0");
        require(stakedOf[account] > 0,"account not staked");
        require(account == msg.sender,"caller must be account");
        require(!isUsedRand[rand],"rand used");
        isUsedRand[rand] = true;
    
        address signatory = recoverWithdrawRewardsSign(account,rewardToken,amount,rand,v,r,s);
        require(signatory != address(0), "invalid signature");
        require(IStakingFactory(factory).isRewardSigner(signatory), "unauthorized");

        _transferTo(rewardToken,account,amount);

        emit RewardPaid(account,rewardToken, amount,rand,block.timestamp);
    }

    function recoverWithdrawRewardsSign(address account,address token, uint amount,uint rand,uint8 v,bytes32 r,bytes32 s) public view returns(address){
        bytes32 structHash = keccak256(abi.encode(WITHDRAW_REWARDS_PERMIT_TYPEHASH, account, token, amount, rand));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signatory = ecrecover(digest, v, r, s);

        return signatory;
    }

    function notifyRewards(uint epoch,uint8 v,bytes32 r,bytes32 s) external nonReentrant {
        require(_calcPeriodStart(block.timestamp,startTime).add(epoch.mul(periodDuration)) <= block.timestamp,"can not notify future rewards");
        require(!isNotifiedEpoch[epoch],"notified");
        isNotifiedEpoch[epoch] = true;
        address signer = recoverNotifyRewardsSign(epoch,v,r,s);
        require(IStakingFactory(factory).isRewardOperator(signer),"unauthorized");

        uint lpAmount = IERC20(pair).balanceOf(address(this)).mul(rewardRate) / RATE_PERCISION;
        uint balanceBefore = IERC20(rewardToken).balanceOf(address(this));
        _removeLiquidityForRewards(lpAmount);
        uint rewardAmount = IERC20(rewardToken).balanceOf(address(this)).sub(balanceBefore);

        emit SwapedRewards(lpAmount,IERC20(pair).balanceOf(address(this)),rewardAmount,block.timestamp);
    }

    function recoverNotifyRewardsSign(uint epoch,uint8 v,bytes32 r,bytes32 s) public view returns(address){
        bytes32 structHash = keccak256(abi.encode(NOTIFY_REWARDS_PERMIT_TYPEHASH, epoch));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signatory = ecrecover(digest, v, r, s);

        return signatory;
    }
    
    function _transferFrom(address from,address token,uint amount) internal returns(uint receivedAmount){
        address weth = IStakingFactory(factory).WETH();
        if(token == weth){
            require(msg.value >= amount,"insufficient input value");
            IWETH(weth).deposit{value : msg.value}();
            return msg.value;
        }

        uint beforeBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).transferFrom(from, address(this), amount);
        return IERC20(token).balanceOf(address(this)).sub(beforeBalance);
    }

    function _transferTo(address token,address to,uint amount) internal {
        address weth = IStakingFactory(factory).WETH();
        if(token == weth){
            IWETH(weth).withdraw(amount);
            _safeTransferETH(to,amount);
        }else{
            IERC20(token).safeTransfer(to,amount);
        }
    }

    function _addLiquidity(uint stakeAmount) internal {
        uint stakingTokenAmount = stakeAmount / 2;
        ISwapRouter router = ISwapRouter(IStakingFactory(factory).swapRouter());
        address[] memory path = new address[](2);
        path[0] = stakingToken;
        path[1] = rewardToken;
        uint balanceBefore = IERC20(rewardToken).balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(stakingTokenAmount,1,path,address(this),type(uint256).max);
        uint swapedAmount = IERC20(rewardToken).balanceOf(address(this)).sub(balanceBefore);

        router.addLiquidity(stakingToken, rewardToken, stakingTokenAmount, swapedAmount, 1, 1, address(this), type(uint256).max);
    }

    function _removeLiquidityForRewards(uint lpAmount) internal {
        if(lpAmount == 0){
            return;
        }
        ISwapRouter router = ISwapRouter(IStakingFactory(factory).swapRouter());
        router.removeLiquidity(stakingToken, rewardToken, lpAmount, 1, 1, address(this), type(uint256).max);
        address[] memory path = new address[](2);
        path[0] = stakingToken;
        path[1] = rewardToken;
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(IERC20(path[0]).balanceOf(address(this)),1,path,address(this),type(uint256).max);
    }

    function _calcPeriodStart(uint _utcTime,uint _periodDuration) internal pure returns(uint){
        uint utcPeriodStart = _utcTime - (_utcTime % _periodDuration);

        return utcPeriodStart - 28800;
    }

    function _safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value : value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }

    function setRewardRate(uint _rate) external onlyCreator {
        require(_rate <= RATE_PERCISION,"rate too large");
        rewardRate = _rate;
    }

    function takeToken(address token,address to,uint amount) external onlyCreator {
        require(msg.sender == creator,"caller must be creator");
        if(token == address(0) || token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)){
            _safeTransferETH(to,amount);
        }else{
            IERC20(token).safeTransfer(to,amount);
        }
    }

    function setPauseStatus(bool _paused) external {
        require(msg.sender == creator || msg.sender == IStakingFactory(factory).factoryOwner(),"caller must be creator");
        if(_paused){
            _pause();
        }else{
            _unpause();
        }
    }

    function transferCreator(address newCreator) external {
        require(newCreator != address(0),"new creator can not be address 0");
        require(msg.sender == creator || msg.sender == IStakingFactory(factory).factoryOwner(),"caller must be creator");
        creator = newCreator;
    }

    function infos() external view returns(
        address _factory,
        address _creator,
        address _pair,
        address _stakingToken,
        address _rewardToken,
        uint _periodDuration,
        uint _rewardRate,
        uint _startTime
    ){
        _factory = factory;
        _creator = creator;
        _pair = pair;
        _stakingToken = stakingToken;
        _rewardToken = rewardToken;
        _periodDuration = periodDuration;
        _rewardRate = rewardRate;
        _startTime = startTime;
    }
}