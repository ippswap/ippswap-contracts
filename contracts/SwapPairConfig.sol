
// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import './swap-interfaces/ISwapPair.sol';
import './swap-libs/CfoTakeableV2.sol';

contract SwapPairConfig is CfoTakeableV2 {

    address public router;

    mapping(address => address) public creatorOf;
    mapping(address => address) public baseTokenOf;

    mapping(address => uint256) public sellUserRateOf;
    mapping(address => uint256) public sellLpRateOf;
    mapping(address => mapping(uint256 => address)) public sellOtherFeeToOf;
    mapping(address => mapping(uint256 => uint256)) public sellOtherFeeRateOf;
    mapping(address => uint256) public sellOtherFeesLengthOf;

    mapping(address => address) public sellLpReceiverOf;
    mapping(address => uint256) public stopSellBurnSupplyOf;

    mapping(address => mapping(address => bool)) public isBuyWhiteList;

    function pairInfos(address pair) external view returns(
        address token0,
        address token1,
        address creator,
        address baseToken,
        uint sellUserRate,
        uint sellLpRate,
        address[] memory sellOtherFeeTos,
        uint[] memory sellOtherFeeRates,
        address sellLpReceiver,
        uint stopSellBurnSupply
    ){
        token0 = ISwapPair(pair).token0();
        token1 = ISwapPair(pair).token1();
        creator = creatorOf[pair];
        baseToken = baseTokenOf[pair];
        sellUserRate = sellUserRateOf[pair];
        sellLpRate = sellLpRateOf[pair];
        sellOtherFeeTos = new address[](sellOtherFeesLengthOf[pair]);
        sellOtherFeeRates = new uint[](sellOtherFeeTos.length);
        for(uint i=0;i<sellOtherFeeTos.length;i++){
            sellOtherFeeTos[i] = sellOtherFeeToOf[pair][i];
            sellOtherFeeRates[i] = sellOtherFeeRateOf[pair][i];
        }
        sellLpReceiver = sellLpReceiverOf[pair];
        stopSellBurnSupply = stopSellBurnSupplyOf[pair];
    }

    // function transferCreator(address pair,address newCreator) external view returns()
}