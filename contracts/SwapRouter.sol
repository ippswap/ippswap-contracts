
// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import './swap-interfaces/IWETH.sol';
import './swap-interfaces/ISwapFactory.sol';
import './swap-interfaces/ISwapPair.sol';
import './swap-libs/SafeMath.sol';
import './swap-libs/TransferHelper.sol';
import './swap-libs/CfoTakeableV2.sol';

contract SwapRouter is Ownable {
    using SafeMath for uint256;

    address public immutable factory;
    address public immutable WETH;

    uint private constant RATE_PERCISION = 10000;

    mapping(address => address) public creatorOf;
    mapping(address => address) public baseTokenOf;

    mapping(address => uint256) public sellUserRateOf;
    mapping(address => uint256) public sellLpRateOf;
    mapping(address => mapping(uint256 => address)) public sellOtherFeeToOf;
    mapping(address => mapping(uint256 => uint256)) public sellOtherFeeRateOf;
    mapping(address => uint256) public sellOtherFeesLengthOf;

    mapping(address => address) public sellLpReceiverOf;

    mapping(address => uint256) public sellBurnRateOf;
    mapping(address => uint256) public sellStopBurnSupplyOf;

    mapping(address => mapping(address => bool)) public isWhiteList;

    address public stakingFactory;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'SwapRouter: EXPIRED');
        _;
    }

    modifier checkSwapPath(address[] calldata path){
        require(path.length == 2,"path length err");

        address pair = pairFor(path[0],path[1]);
        address baseToken = baseTokenOf[pairFor(path[0],path[1])];
        require(baseToken != address(0),"pair of path not found");
        require(path[0] != baseToken || isWhiteList[pair][msg.sender],"buy disabled");
        _;
    }

    modifier onlyCreator(address pair){
        require(pair != address(0),"pair can not be address 0");
        require(msg.sender == creatorOf[pair] || msg.sender==owner(),"caller must be creator");
        _;
    }

    event NewPairCreated(address caller,address pair,uint blockTime);
    event SellLpFeeAdded(address caller,address pair,uint addedLpBaseTokenAmount,uint blockTime);
    event PairConfigChanged(address caller,uint blockTime);
    event WhiteListChanged(address pair,address user,bool status);

    struct CreatePairParams {
        address tokenA;
        address tokenB;
        address baseToken;
        uint amountA;
        uint amountB;
        // address to;
        uint sellUserRate;
        uint sellLpRate;
        uint sellBurnRate;
        uint sellStopBurnSupply;
    }

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH);
        // only accept ETH via fallback from the WETH contract
    }

    function pairFor(address tokenA, address tokenB) public view returns (address pair) {
        pair = ISwapFactory(factory).pairFor(tokenA, tokenB);
    }

    function createPair(CreatePairParams calldata paras,address[] calldata otherFeeTos, uint[] calldata otherFeeRates) external {
        require(paras.baseToken == paras.tokenA || paras.baseToken == paras.tokenB,"invalid base token");
        require(ISwapFactory(factory).getPair(paras.tokenA, paras.tokenB) == address(0),"pair existed");
        require(paras.sellBurnRate <= RATE_PERCISION,"sell burn token rate too big");
        // require(paras.to != address(0),"to can not be address 0");
        require(paras.amountA > 0 && paras.amountB > 0,"invalid amountA or amountB");

        address pair = ISwapFactory(factory).createPair(paras.tokenA, paras.tokenB);
        TransferHelper.safeTransferFrom(paras.tokenA, msg.sender, pair, paras.amountA);
        TransferHelper.safeTransferFrom(paras.tokenB, msg.sender, pair, paras.amountB);
        ISwapPair(pair).mint(msg.sender);

        creatorOf[pair] = msg.sender;
        baseTokenOf[pair] = paras.baseToken;
        sellLpReceiverOf[pair] = msg.sender;

        _setPairConfigs(pair,paras.sellBurnRate,paras.sellStopBurnSupply,paras.sellUserRate,paras.sellLpRate,otherFeeTos,otherFeeRates);

        isWhiteList[pair][msg.sender] = true;

        emit NewPairCreated(msg.sender, pair, block.timestamp);
    }


    function _setPairConfigs(
        address pair,
        uint sellBurnRate,
        uint sellStopBurnSupply,
        uint sellUserRate,
        uint sellLpRate,
        address[] calldata otherFeeTos,
        uint[] calldata otherFeeRates
    ) internal {
        require(sellBurnRate <= RATE_PERCISION,"sell burn token rate too big");
        require(otherFeeTos.length == otherFeeRates.length && otherFeeTos.length <= 50,"otherFeeRates length err");
        
        sellBurnRateOf[pair] = sellBurnRate;
        sellStopBurnSupplyOf[pair] = sellStopBurnSupply;

        uint totalRate = sellUserRate.add(sellLpRate);
        require(totalRate <= RATE_PERCISION,"sum of rates too big");
        sellUserRateOf[pair] = sellUserRate;
        sellLpRateOf[pair] = sellLpRate;
        for(uint i=0;i<otherFeeTos.length;i++){
            require(otherFeeTos[i]!=address(0),"otherFeeAccount can not be address 0");
            totalRate = totalRate.add(otherFeeRates[i]);
            require(totalRate <= RATE_PERCISION,"sum of rates too big");

            sellOtherFeeToOf[pair][i] = otherFeeTos[i];
            sellOtherFeeRateOf[pair][i] = otherFeeRates[i];
        }
        uint oldLen = sellOtherFeesLengthOf[pair];
        sellOtherFeesLengthOf[pair] = otherFeeTos.length;

        for(uint i=otherFeeTos.length;i<oldLen;i++){
            delete sellOtherFeeToOf[pair][i];
            delete sellOtherFeeRateOf[pair][i];
        }
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal view returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        // if (ISwapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
        //     ISwapFactory(factory).createPair(tokenA, tokenB);
        // }
        require(ISwapFactory(factory).getPair(tokenA, tokenB) != address(0),"pair not exists");
        
        (uint reserveA, uint reserveB) = ISwapFactory(factory).getReserves(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = ISwapFactory(factory).quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'SwapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = ISwapFactory(factory).quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'SwapRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = pairFor(tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = ISwapPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = pairFor(token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value : amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = ISwapPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountA, uint amountB) {
        require(ISwapFactory(factory).getPair(tokenA, tokenB) != address(0),"pair not exists");

        address pair = pairFor(tokenA, tokenB);
        ISwapPair(pair).transferFrom(msg.sender, pair, liquidity);
        // send liquidity to pair
        (uint amount0, uint amount1) = ISwapPair(pair).burn(to);
        (address token0,) = ISwapFactory(factory).sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'SwapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'SwapRouter: INSUFFICIENT_B_AMOUNT');
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public  ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = ISwapFactory(factory).sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? pairFor(output, path[i + 2]) : _to;
            ISwapPair(pairFor(input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal returns(uint) {
        (address input, address output) = (path[0], path[1]);
        (address token0,) = ISwapFactory(factory).sortTokens(input, output);
        ISwapPair pair = ISwapPair(pairFor(input, output));
        uint amountInput;
        uint amountOutput;
        {// scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = ISwapFactory(factory).getAmountOut(amountInput, reserveInput, reserveOutput, input, output);
        }

        (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
        // address to = i < path.length - 2 ? pairFor(output, path[i + 2]) : _to;
        pair.swap(amount0Out, amount1Out, _to, new bytes(0));

        return amountInput;
    }

    function _isBuy(address[] calldata path) internal view returns(bool) {
        return path[0] == baseTokenOf[pairFor(path[0],path[1])] ? true : false;
    }

    struct SwapTempVals {
        bool isBuy;
        address swapTo;
        uint balanceBefore;
        uint amountInput;
        uint amountOut;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) checkSwapPath(path) {
        TransferHelper.safeTransferFrom(path[0], msg.sender, pairFor(path[0], path[1]), amountIn);

        SwapTempVals memory tempVals;
        tempVals.isBuy = _isBuy(path);
        tempVals.swapTo = tempVals.isBuy ? to : address(this);

        tempVals.balanceBefore = IERC20(path[path.length - 1]).balanceOf(tempVals.swapTo);
        tempVals.amountInput = _swapSupportingFeeOnTransferTokens(path, tempVals.swapTo);
        tempVals.amountOut = IERC20(path[path.length - 1]).balanceOf(tempVals.swapTo).sub(tempVals.balanceBefore);
        require(tempVals.amountOut >= amountOutMin,'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');

        if(!tempVals.isBuy){
            _burnPairToken(path,tempVals.amountInput);
            
            if(isWhiteList[pairFor(path[0], path[1])][msg.sender]){
                _distributeTo(path[1], to, tempVals.amountOut);
            }else{
                _distributeForSell(path,tempVals.amountOut,to);
                _addLiquidityForSell(path,tempVals.amountOut);
            }
        }        
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable ensure(deadline) checkSwapPath(path) {
        require(path[0] == WETH, 'SwapRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value : amountIn}();
        assert(IWETH(WETH).transfer(pairFor(path[0], path[1]), amountIn));

        SwapTempVals memory tempVals;
        tempVals.isBuy = _isBuy(path);
        tempVals.swapTo = tempVals.isBuy ? to : address(this);

        tempVals.balanceBefore = IERC20(path[path.length - 1]).balanceOf(tempVals.swapTo);
        tempVals.amountInput = _swapSupportingFeeOnTransferTokens(path, tempVals.swapTo);
        tempVals.amountOut = IERC20(path[path.length - 1]).balanceOf(tempVals.swapTo).sub(tempVals.balanceBefore);
        require(tempVals.amountOut >= amountOutMin,'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');

        if(!tempVals.isBuy){
            _burnPairToken(path,tempVals.amountInput);

            if(isWhiteList[pairFor(path[0], path[1])][msg.sender]){
                _distributeTo(path[1], to, tempVals.amountOut);
            }else{
                _distributeForSell(path,tempVals.amountOut,to);
                _addLiquidityForSell(path,tempVals.amountOut);
            }
        }
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) checkSwapPath(path) {
        require(path[path.length - 1] == WETH, 'SwapRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(path[0], msg.sender, pairFor(path[0], path[1]), amountIn);

        SwapTempVals memory tempVals;
        tempVals.isBuy = _isBuy(path);
        tempVals.swapTo = tempVals.isBuy ? to : address(this);

        tempVals.balanceBefore = IERC20(path[path.length - 1]).balanceOf(address(this));
        tempVals.amountInput = _swapSupportingFeeOnTransferTokens(path, address(this));
        tempVals.amountOut = IERC20(path[path.length - 1]).balanceOf(address(this)).sub(tempVals.balanceBefore);
        require(tempVals.amountOut >= amountOutMin, 'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        // IWETH(WETH).withdraw(tempVals.amountOut);

        if(!tempVals.isBuy){
            _burnPairToken(path,tempVals.amountInput);

            if(isWhiteList[pairFor(path[0], path[1])][msg.sender]){
                _distributeTo(path[1], to, tempVals.amountOut);
            }else{
                _distributeForSell(path,tempVals.amountOut,to);
                _addLiquidityForSell(path,tempVals.amountOut);
            }
        }else{
            IWETH(WETH).withdraw(tempVals.amountOut);
            TransferHelper.safeTransferETH(to, tempVals.amountOut);
        }
    }

    function _burnPairToken(address[] calldata path,uint amountInput) internal {
        address pair = pairFor(path[0], path[1]);

        uint burnedAmount = IERC20(path[0]).balanceOf(address(0));
        burnedAmount = burnedAmount.add(IERC20(path[0]).balanceOf(address(0x000000000000000000000000000000000000dEaD)));
        uint totalSupply = IERC20(path[0]).totalSupply().sub(burnedAmount);
        uint stopBurnSupply = sellStopBurnSupplyOf[pair];
        uint burnAmount = amountInput.mul(sellBurnRateOf[pair]) / RATE_PERCISION;
        if(burnAmount > 0 && totalSupply > stopBurnSupply){
            if(totalSupply.sub(burnAmount) < stopBurnSupply){
                burnAmount = totalSupply.sub(stopBurnSupply);
            }
            if(burnAmount > 0){
                ISwapPair(pair).burnToken(path[0],burnAmount);
            }
        }
    }

    function _distributeForSell(address[] calldata path,uint amountOut,address user) internal {
        address pair = pairFor(path[0], path[1]);
        _distributeTo(path[1], user, amountOut.mul(sellUserRateOf[pair]) / RATE_PERCISION);
        uint l = sellOtherFeesLengthOf[pair];
        for(uint i=0;i<l;i++){
            address otherTo = sellOtherFeeToOf[pair][i];
            _distributeTo(path[1],otherTo,amountOut.mul(sellOtherFeeRateOf[pair][i]) / RATE_PERCISION);
        }
    }

    function _distributeTo(address token,address to,uint amount) internal {
        if(token == WETH){
            IWETH(token).withdraw(amount);
            TransferHelper.safeTransferETH(to, amount);
        }else{
            TransferHelper.safeTransfer(token, to, amount);
        }
    }

    function _addLiquidityForSell(address[] calldata path,uint amountOut) internal {
        address pair = pairFor(path[0], path[1]);
        uint addLpAmount = amountOut.mul(sellLpRateOf[pair]) / RATE_PERCISION / 2;
        if(addLpAmount == 0){
            return;
        }

        TransferHelper.safeTransfer(path[1], pair, addLpAmount);
        uint balanceBefore = IERC20(path[0]).balanceOf(address(this));
        _swapSupportingFeeOnTransferTokens(_flipPath(path), address(this));
        uint swapOut = IERC20(path[0]).balanceOf(address(this)).sub(balanceBefore);

        (uint amountA, uint amountB) = _addLiquidity(path[1], path[0], addLpAmount, swapOut, 1, 1);
        TransferHelper.safeTransfer(path[1], pair, amountA);
        TransferHelper.safeTransfer(path[0], pair, amountB);
        ISwapPair(pair).mint(sellLpReceiverOf[pair]);
        emit SellLpFeeAdded(msg.sender,pair,amountA.mul(2),block.timestamp);
    }

    function _flipPath(address[] calldata path) internal pure returns(address[] memory flipedPath){
        flipedPath  = new address[](2);
        flipedPath[0] = path[1];
        flipedPath[1] = path[0];
    }

    function setPairCreator(address pair,address newCreator) external onlyCreator(pair) {
        creatorOf[pair] = newCreator;

        emit PairConfigChanged(msg.sender,block.timestamp);
    }

    function setSellLpReceiver(address pair,address receiver) external {
        require(msg.sender == stakingFactory || msg.sender == owner(),"invalid caller");
        sellLpReceiverOf[pair] = receiver;

        emit PairConfigChanged(msg.sender,block.timestamp);
    }

    function setPairConfigs(
        address pair,
        uint sellBurnRate,
        uint sellStopBurnSupply,
        uint sellUserRate,
        uint sellLpRate,
        address[] calldata otherFeeTos,
        uint[] calldata otherFeeRates
    ) external onlyCreator(pair) {
        _setPairConfigs(pair,sellBurnRate,sellStopBurnSupply,sellUserRate,sellLpRate,otherFeeTos,otherFeeRates);

        emit PairConfigChanged(msg.sender,block.timestamp);
    }

    function setWhiteList(address pair,address account,bool status) external {
        require(msg.sender == stakingFactory || msg.sender == creatorOf[pair] || msg.sender == owner(),"caller must be creator");
        isWhiteList[pair][account] = status;
        
        emit WhiteListChanged(pair,account,status);
        emit PairConfigChanged(msg.sender,block.timestamp);
    }

    function setStakingFactory(address _stakingFactory) external onlyOwner {
        stakingFactory = _stakingFactory;
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public view returns (uint256 amountB) {
        return ISwapFactory(factory).quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, address token0, address token1) public view returns (uint256 amountOut){
        return ISwapFactory(factory).getAmountOut(amountIn, reserveIn, reserveOut, token0, token1);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, address token0, address token1) public view returns (uint256 amountIn){
        return ISwapFactory(factory).getAmountIn(amountOut, reserveIn, reserveOut, token0, token1);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts){
        return ISwapFactory(factory).getAmountsOut(amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts){
        return ISwapFactory(factory).getAmountsIn(amountOut, path);
    }
}