// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISwapRouter {
    function factory() external view returns(address);

    function WETH() external view returns(address);

    function creatorOf(address pair) external view returns(address);

    function baseTokenOf(address pair) external view returns(address);

    function sellUserRateOf(address pair) external view returns(uint);

    function sellLpRateOf(address pair) external view returns(uint);

    function sellOtherFeesLengthOf(address pair) external view returns(uint);

    function sellOtherFeeToOf(address pair,uint index) external view returns(address);

    function sellOtherFeeRateOf(address pair,uint index) external view returns(uint);

    function sellLpReceiverOf(address pair) external;

    function sellBurnRateOf(address pair) external view returns(uint);

    function sellStopBurnSupplyOf(address pair) external view returns(uint);

    function isWhiteList(address pair,address account) external view returns(bool);

    function setSellLpReceiver(address pair,address receiver) external;

    function setWhiteList(address pair,address account,bool status) external;

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external;

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external;
}