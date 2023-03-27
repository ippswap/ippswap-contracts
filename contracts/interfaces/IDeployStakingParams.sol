    
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDeployStakingParams {
    struct DeployStakingParams {
        address factory;
        address creator;
        address pair;
        address stakingToken;
        address rewardToken;
        uint periodDuration;
        uint rewardRate;
        uint startTime;
    }
}
