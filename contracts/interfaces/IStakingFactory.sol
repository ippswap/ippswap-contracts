
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './IDeployStakingParams.sol';

interface IStakingFactory is IDeployStakingParams {

    function deployParams() external view returns(DeployStakingParams memory paras);

    function WETH() external view returns(address);

    function factoryOwner() external view returns(address);

    // function isAdmin(address account) external view returns(address);

    function swapRouter() external view returns(address);

    function isRewardOperator(address account) external view returns(bool);

    function isRewardSigner(address account) external view returns(bool);
}
