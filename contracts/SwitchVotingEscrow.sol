// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import "./modules/Configable.sol";
import "./modules/ReentrancyGuard.sol";
import "./modules/Initializable.sol";
import "./interfaces/ISwitchVotingEscrow.sol";
import "./interfaces/IRewardToken.sol";
import "./interfaces/IAddressWhitelist.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./libraries/TransferHelper.sol";

contract SwitchVotingEscrow is
    ISwitchVotingEscrow,
    ReentrancyGuard,
    Configable,
    Initializable
{
    using SafeMath for uint256;

    event LockCreated(
        address indexed account,
        uint256 amount,
        uint256 unlockTime,
        uint256 lockWeeks
    );
    event AmountIncreased(address indexed account, uint256 increasedAmount);
    event UnlockTimeIncreased(
        address indexed account,
        uint256 newUnlockTime,
        uint256 newLockWeeks
    );
    event Withdrawn(address indexed account, uint256 amount);
    event Harvest(address indexed account, address to);
    event UpdateLockWeights(
        address indexed account,
        uint256 lockWeeks,
        uint256 weight
    );

    uint256 public override maxTime;
    address public override token;
    string public constant name = "Voting Escrow Switch";
    string public constant symbol = "veSwitch";
    uint8 public constant decimals = 18;
    address public addressWhitelist;

    uint256 public constant BONUS_MULTIPLIER = 1;
    uint256 public mintPerBlock;
    uint256 public lastBlock;
    uint256 public accRewardPerShare;
    uint256 public depositTokenSupply;
    uint256 public depositTotalPower;

    mapping(address => LockedBalance) public locked;
    /// @notice Mapping of unlockTime => total amount that will be unlocked at unlockTime
    mapping(uint256 => uint256) public scheduledUnlock;
    /// @notice Mapping of lock weeks => weight
    mapping(uint256 => uint256) public lockWeights;

    function initialize(
        address _token,
        address _addressWhitelist,
        uint256 _maxTime,
        uint256 _mintPerBlock,
        uint256 _startBlock
    ) external initializer {
        require(
            _token != address(0) && _addressWhitelist != address(0),
            "Invalid address"
        );
        require(_maxTime > 0 && _mintPerBlock > 0, "Zero number");
        owner = msg.sender;
        token = _token;
        addressWhitelist = _addressWhitelist;
        maxTime = _maxTime;
        mintPerBlock = _mintPerBlock;
        lastBlock = block.number > _startBlock ? block.number : _startBlock;
    }

    function getTimestampDropBelow(address account, uint256 threshold)
        external
        view
        override
        returns (uint256)
    {
        LockedBalance memory lockedBalance = locked[account];
        if (lockedBalance.amount == 0 || lockedBalance.amount < threshold) {
            return 0;
        }
        return
            lockedBalance.unlockTime.sub(
                threshold.mul(maxTime).div(lockedBalance.amount)
            );
    }

    function balanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return _balanceOfAtTimestamp(account, block.timestamp);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupplyAtTimestamp(block.timestamp);
    }

    function getLockedBalance(address account)
        external
        view
        override
        returns (LockedBalance memory)
    {
        return locked[account];
    }

    function balanceOfAtTimestamp(address account, uint256 timestamp)
        external
        view
        override
        returns (uint256)
    {
        return _balanceOfAtTimestamp(account, timestamp);
    }

    function totalSupplyAtTimestamp(uint256 timestamp)
        external
        view
        returns (uint256)
    {
        return _totalSupplyAtTimestamp(timestamp);
    }

    function pendingReward(address account)
        external
        view
        override
        returns (uint256)
    {
        LockedBalance memory lockedBalance = locked[account];
        uint256 accRewardPerShareTmp = accRewardPerShare;
        if (getToBlock() > lastBlock && depositTotalPower != 0) {
            uint256 multiplier = getMultiplier(lastBlock, getToBlock());
            uint256 reward = multiplier.mul(mintPerBlock);
            accRewardPerShareTmp = accRewardPerShareTmp.add(
                reward.mul(1e18).div(depositTotalPower)
            );
        }
        return
            lockedBalance
                .amount
                .mul(lockWeights[lockedBalance.lockWeeks])
                .div(100)
                .mul(accRewardPerShareTmp)
                .div(1e18)
                .sub(lockedBalance.rewardDebt);
    }

    function getToBlock() public view returns (uint256) {
        return block.number;
    }

    function getMultiplier(uint256 from, uint256 to)
        public
        pure
        returns (uint256)
    {
        return to.sub(from).mul(BONUS_MULTIPLIER);
    }

    function batchUpdateLockWeights(
        uint256[] memory lockWeeksArr,
        uint256[] memory weightArr
    ) external onlyDev {
        require(
            lockWeeksArr.length == weightArr.length,
            "Arguments length wrong"
        );
        for (uint256 i = 0; i < lockWeeksArr.length; i++) {
            updateLockWeights(lockWeeksArr[i], weightArr[i]);
        }
    }

    function updateLockWeights(uint256 lockWeeks, uint256 weight)
        public
        onlyDev
    {
        lockWeights[lockWeeks] = weight;
        emit UpdateLockWeights(msg.sender, lockWeeks, weight);
    }

    function updateAddressWhitelist(address newWhitelist) external onlyDev {
        require(
            newWhitelist == address(0) || Address.isContract(newWhitelist),
            "Smart contract whitelist has to be null or a contract"
        );
        addressWhitelist = newWhitelist;
    }

    function createLock(uint256 amount, uint256 weeksCount)
        external
        nonReentrant
    {
        _assertNotContract();

        uint256 cw = (block.timestamp / 1 weeks) * 1 weeks + 1 weeks;
        uint256 unlockTime = cw.add(weeksCount * 1 weeks);

        LockedBalance memory lockedBalance = locked[msg.sender];

        require(amount > 0 && weeksCount > 0, "Zero value");
        require(lockedBalance.amount == 0, "Withdraw old tokens first");
        require(
            unlockTime <= block.timestamp + maxTime,
            "Voting lock cannot exceed max lock time"
        );
        require(
            lockWeights[weeksCount] != 0,
            "The weight of lock time no init"
        );

        _update();

        scheduledUnlock[unlockTime] = scheduledUnlock[unlockTime].add(amount);
        locked[msg.sender].unlockTime = unlockTime;
        locked[msg.sender].amount = amount;
        locked[msg.sender].lockWeeks = weeksCount;
        locked[msg.sender].rewardDebt = amount
            .mul(lockWeights[weeksCount])
            .div(100)
            .mul(accRewardPerShare)
            .div(1e18);

        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount
        );

        depositTokenSupply = depositTokenSupply.add(amount);
        depositTotalPower = depositTotalPower.add(
            amount.mul(lockWeights[weeksCount].div(100))
        );

        emit LockCreated(msg.sender, amount, unlockTime, weeksCount);
    }

    function increaseAmount(address account, uint256 amount)
        external
        nonReentrant
    {
        LockedBalance memory lockedBalance = locked[account];

        require(amount > 0, "Zero value");
        require(
            lockedBalance.unlockTime > block.timestamp,
            "Cannot add to expired lock"
        );

        _update();

        scheduledUnlock[lockedBalance.unlockTime] = scheduledUnlock[
            lockedBalance.unlockTime
        ].add(amount);
        locked[account].amount = lockedBalance.amount.add(amount);
        locked[account].rewardDebt = locked[account].rewardDebt.add(
            amount.mul(lockWeights[lockedBalance.lockWeeks]).div(100).mul(accRewardPerShare).div(
                1e18
            )
        );

        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount
        );

        depositTokenSupply = depositTokenSupply.add(amount);
        depositTokenSupply = depositTotalPower.add(
            amount.mul(lockWeights[lockedBalance.lockWeeks]).div(100)
        );

        emit AmountIncreased(account, amount);
    }

    function increaseUnlockTime(uint256 weeksCount) external nonReentrant {
        LockedBalance memory lockedBalance = locked[msg.sender];
        require(lockedBalance.unlockTime > block.timestamp, "Lock expired");
        require(weeksCount > 0, "Zero value");

        uint256 unlockTime = lockedBalance.unlockTime.add(weeksCount * 1 weeks);
        weeksCount = lockedBalance.lockWeeks.add(weeksCount);
        require(
            unlockTime <= block.timestamp + maxTime,
            "Voting lock cannot exceed max lock time"
        );

        _update();

        scheduledUnlock[lockedBalance.unlockTime] = scheduledUnlock[
            lockedBalance.unlockTime
        ].sub(lockedBalance.amount);
        scheduledUnlock[unlockTime] = scheduledUnlock[unlockTime].add(
            lockedBalance.amount
        );

        depositTotalPower = depositTotalPower.sub(
            lockedBalance.amount.mul(lockWeights[lockedBalance.lockWeeks]).div(
                100
            )
        );
        depositTotalPower = depositTotalPower.add(
            lockedBalance.amount.mul(lockWeights[weeksCount]).div(100)
        );
        locked[msg.sender].unlockTime = unlockTime;
        locked[msg.sender].lockWeeks = weeksCount;

        emit UnlockTimeIncreased(msg.sender, unlockTime, weeksCount);
    }

    function withdraw() external nonReentrant {
        LockedBalance storage lockedBalance = locked[msg.sender];
        require(
            block.timestamp >= lockedBalance.unlockTime,
            "The lock is not expired"
        );
        uint256 amount = uint256(lockedBalance.amount);

        _update();
        _harvestRewardToken(msg.sender);

        TransferHelper.safeTransfer(token, msg.sender, amount);

        lockedBalance.unlockTime = 0;
        lockedBalance.amount = 0;
        lockedBalance.rewardDebt = 0;

        depositTokenSupply = depositTokenSupply.sub(amount);
        depositTotalPower = depositTotalPower.sub(
            lockedBalance.amount.mul(lockWeights[lockedBalance.lockWeeks]).div(
                100
            )
        );

        emit Withdrawn(msg.sender, amount);
    }

    function harvest(address to) external nonReentrant {
        _update();
        _harvestRewardToken(to);
    }

    function safeTokenTransfer(
        address _token,
        address _to,
        uint256 _amount
    ) internal returns (uint256) {
        uint256 tokenBal = IRewardToken(_token).balanceOf(address(this));
        if (_amount > 0) {
            if (tokenBal == 0) {
                return 0;
            }
            if (_amount > tokenBal) {
                _amount = tokenBal;
            }
            TransferHelper.safeTransfer(_token, _to, _amount);
        }
        return _amount;
    }

    function _harvestRewardToken(address to) internal returns (uint256 amount) {
        LockedBalance storage lockedBalance = locked[msg.sender];
        amount = lockedBalance
            .amount
            .mul(lockWeights[lockedBalance.lockWeeks])
            .div(100)
            .mul(accRewardPerShare)
            .div(1e18)
            .sub(lockedBalance.rewardDebt);
        uint take = IRewardToken(token).take();
        if(amount > take) {
            amount = take;
        }
        IRewardToken(token).mint(to, amount);
        lockedBalance.rewardDebt = lockedBalance
            .amount
            .mul(lockWeights[lockedBalance.lockWeeks])
            .div(100)
            .mul(accRewardPerShare)
            .div(1e18);
        return amount;
    }

    function _update() internal {
        uint256 toBlock = getToBlock();
        if (toBlock <= lastBlock) {
            return;
        }
        if (depositTotalPower == 0) {
            lastBlock = toBlock;
            return;
        }

        (uint256 reward, ) = _mintRewardToken();
        accRewardPerShare = accRewardPerShare.add(
            reward.mul(1e18).div(depositTotalPower)
        );

        lastBlock = toBlock;
    }

    function _assertNotContract() internal view {
        if (msg.sender != tx.origin) {
            if (
                addressWhitelist != address(0) &&
                IAddressWhitelist(addressWhitelist).check(msg.sender)
            ) {
                return;
            }
            revert("Smart contract depositors not allowed");
        }
    }

    function _balanceOfAtTimestamp(address account, uint256 timestamp)
        private
        view
        returns (uint256)
    {
        require(timestamp >= block.timestamp, "Must be current or future time");
        LockedBalance memory lockedBalance = locked[account];
        if (timestamp > lockedBalance.unlockTime) {
            return 0;
        }
        return
            (lockedBalance.amount.mul(lockedBalance.unlockTime - timestamp)) /
            maxTime;
    }

    function _totalSupplyAtTimestamp(uint256 timestamp)
        private
        view
        returns (uint256)
    {
        uint256 weekCursor = (timestamp / 1 weeks) * 1 weeks + 1 weeks;
        uint256 total = 0;
        for (; weekCursor <= timestamp + maxTime; weekCursor += 1 weeks) {
            total = total.add(
                (scheduledUnlock[weekCursor].mul(weekCursor - timestamp)) /
                    maxTime
            );
        }
        return total;
    }

    function _mintRewardToken() internal view returns (uint256, uint256) {
        if (getToBlock() <= lastBlock) {
            return (0, getToBlock());
        }

        uint256 multiplier = getMultiplier(lastBlock, getToBlock());
        uint256 reward = multiplier.mul(mintPerBlock);

        if (reward > IRewardToken(token).funds(address(this))) {
            return (0, getToBlock());
        }
        return (reward, getToBlock());
    }
}
