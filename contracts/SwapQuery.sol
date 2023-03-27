
// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import './swap-interfaces/ISwapFactory.sol';
import './swap-interfaces/ISwapPair.sol';

interface ISwapRouter {
    function factory() external view returns(address);

    function creatorOf(address pair) external view returns(address);

    function baseTokenOf(address pair) external view returns(address);

    function sellUserRateOf(address pair) external view returns(uint);

    function sellLpRateOf(address pair) external view returns(uint);

    function sellOtherFeesLengthOf(address pair) external view returns(uint);

    function sellOtherFeeToOf(address pair,uint index) external view returns(address);

    function sellOtherFeeRateOf(address pair,uint index) external view returns(uint);

    function sellLpReceiverOf(address pair) external view returns(address);

    function sellBurnRateOf(address pair) external view returns(uint);

    function sellStopBurnSupplyOf(address pair) external view returns(uint);

    function isWhiteList(address pair,address account) external view returns(bool);
}

contract SwapQuery {

    function pairInfos(address router,address pair) external view returns(
        address token0,
        address token1,
        address baseToken,
        address creator,
        uint sellBurnRate,
        uint sellStopBurnSupply,
        uint sellUserRate,
        uint sellLpRate,
        address[] memory sellOtherFeeTos,
        uint[] memory sellOtherFeeRates,
        address sellLpReceiver
    ){
        token0 = ISwapPair(pair).token0();
        token1 = ISwapPair(pair).token1();
        baseToken = ISwapRouter(router).baseTokenOf(pair);
        creator = ISwapRouter(router).creatorOf(pair);
        sellBurnRate = ISwapRouter(router).sellBurnRateOf(pair);
        sellStopBurnSupply = ISwapRouter(router).sellStopBurnSupplyOf(pair);
        sellUserRate = ISwapRouter(router).sellUserRateOf(pair);
        sellLpRate = ISwapRouter(router).sellLpRateOf(pair);
        sellOtherFeeTos = new address[](ISwapRouter(router).sellOtherFeesLengthOf(pair));
        sellOtherFeeRates = new uint[](sellOtherFeeTos.length);
        for(uint i=0;i<sellOtherFeeTos.length;i++){
            sellOtherFeeTos[i] = ISwapRouter(router).sellOtherFeeToOf(pair,i);
            sellOtherFeeRates[i] = ISwapRouter(router).sellOtherFeeRateOf(pair,i);
        }
        sellLpReceiver = ISwapRouter(router).sellLpReceiverOf(pair);
    }

    function isWhiteList(address router,address pair,address account) external view returns(bool){
        return ISwapRouter(router).isWhiteList(pair, account);
    }

    function getPairs(address router, uint start,uint length) public view returns(uint total,address[] memory pairs,uint[] memory feeRates) {
        address factory = ISwapRouter(router).factory();
        total = ISwapFactory(factory).allPairsLength();
        if(length == 0){
             return (total,new address[](0),new uint[](0));
        }
        if(start >= total || length == 0){
            return (total,new address[](0),new uint[](0));
        }
        if(start + length > total){
            length = total - start;
        }
        
        pairs = new address[](length);
        feeRates = new uint[](length);
        uint swapFee = ISwapFactory(factory).swapFee();
        for(uint i=0;i<length;i++){
            pairs[i] = ISwapFactory(factory).allPairs(i+start);
            feeRates[i] = swapFee;
        }
    }

    function getAllPairs(address router) public view returns(address[] memory pairs,uint[] memory feeRates){
        address factory = ISwapRouter(router).factory();
        uint len = ISwapFactory(factory).allPairsLength();
        (,pairs,feeRates) = getPairs(router, 0, len);
    }

    function getPairReserves(address[] calldata pairs) external view returns(address[] memory _tokens,uint[] memory _reserves){
        _tokens = new address[](pairs.length * 2);
        _reserves = new uint[](pairs.length * 2);
        for(uint i=0;i<pairs.length;i++){
            ISwapPair pair = ISwapPair(pairs[i]);
            _tokens[i*2] = pair.token0();
            _tokens[i*2+1] = pair.token1();

            (_reserves[i*2],_reserves[i*2+1],)= pair.getReserves();
        }
    }
}