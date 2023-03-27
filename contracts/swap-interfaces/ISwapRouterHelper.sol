
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISwapRouterHelper {
    // function calcAmounts(address thirdPair,uint amountIn,uint amountOut, address[] calldata path,bool useInCalcOut) external view returns(uint[] memory _amounts997,uint[] memory _amounts);

    function pairFor(address tokenA,address tokenB) external view returns(address);

    function calcAmountToPair(uint originalAmountIn,address[] calldata path) external view returns(uint amountToPair,bool isThirdPair);

    function calcAmountToPairByOut(uint amountOut,address[] calldata path) external view returns(uint allAmountIn,uint amountToPair,bool isThirdPair);

    function swap(address caller,address[] calldata path,address _to,bool isThird) external;

    function allPairsLength() external view returns(uint);

    function getPair(address tokenA,address tokenB) external view returns(address,bool);

    function getSwapPath(address tokenA,address tokenB,address[] calldata bridgeTokens) external view returns(address[] memory path,address[] memory pairPath, bool isThird);

    function getAllPairs() external view returns(address[] memory pairs,bool[] memory isThirds, uint[] memory feeRateNumerators);

}