// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

interface ISwitchVotingEscrow {
    struct LockedBalance {
        uint256 amount;
        uint256 unlockTime;
        uint256 lockWeeks;
        uint256 rewardDebt;
    }

    function token() external view returns (address);
    function maxTime() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOfAtTimestamp(address account, uint256 timestamp)
        external
        view
        returns (uint256);

    function getTimestampDropBelow(address account, uint256 threshold)
        external
        view
        returns (uint256);

    function getLockedBalance(address account) external view returns (LockedBalance memory);
    function pendingReward(address _user) external view returns (uint256);
}
