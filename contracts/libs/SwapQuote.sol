// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '../libs/Math.sol';
import '../libs/SafeMath.sol';
import '../libs/Ownable.sol';


interface ISwapRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns(uint[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] memory path) external view returns (uint256[] memory amounts);
}

interface ISwapPair {    
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface ISwapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

library SwapQuote {
    using SafeMath for uint256;

    function quoteAnotherTokenAmount(address pair,address token,uint tokenAmount) internal view returns(uint){

        require(pair != address(0),"pair can not be address 0");
        uint tokenReserve = 0;
        uint anotherTokenReserve = 0;
        {
            (uint r0,uint r1,) = ISwapPair(pair).getReserves();
            (tokenReserve,anotherTokenReserve) = ISwapPair(pair).token0() == token ? (r0,r1) : (r1,r0);
        }

        return _quote(tokenAmount, tokenReserve, anotherTokenReserve);
    }    

    function _quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'quote: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'quote: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }
}