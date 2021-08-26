// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

interface ISwitchFarm {
    function poolInfo(uint _pid) external view returns (
        address depositToken,           // Address of LP token contract.
        uint allocPoint,       // How many allocation points assigned to this pool. RewardTokens to distribute per block.
        uint lastRewardBlock,  // Last block number that RewardTokens distribution occurs.
        uint accRewardPerShare,   // Accumulated RewardTokens per share, times 1e18. See below.
        uint depositTokenSupply,
        uint16 depositFeeBP,      // Deposit fee in basis points
        bool paused,
        uint16 tokenType
    );
    function rewardToken() external view returns (address);
    function pendingReward(uint _pid, address _user) external view returns (uint);
    function pendingEarn(uint _pid, address _user) external view returns (uint);
    function deposit(uint _pid, uint _amount, address _to) payable external returns(uint, uint);
    function withdraw(uint _pid, uint _amount, address _to) external returns(uint);
    function harvest(uint _pid, address _to) external returns (uint reward, uint earn);
    function harvestRewardToken(uint _pid, address _to) external returns(uint amount);
    function harvestEarnToken(uint _pid, address _to) external returns(uint amount);
    function emergencyWithdraw(uint _pid, address _to) external returns(uint);
}