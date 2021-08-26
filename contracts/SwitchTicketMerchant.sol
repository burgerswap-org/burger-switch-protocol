// SPDX-License-Identifier: MIT

pragma solidity >=0.6.6;

import "./interfaces/IERC20.sol";
import './interfaces/IWETH.sol';
import './interfaces/IRewardToken.sol';
import './interfaces/ISwitchFarm.sol';
import './interfaces/ISwitchTicketFactory.sol';
import './libraries/SafeMath.sol';
import "./modules/ReentrancyGuard.sol";
import './modules/Initializable.sol';


contract SwitchTicketConfigable {
    address public owner;
    address public admin;

    modifier onlyOwner() {
        require(msg.sender == owner, 'OWNER FORBIDDEN');
        _;
    }

    function changeOwner(address _user) external onlyOwner {
        require(owner != _user, 'Owner NO CHANGE');
        owner = _user;
    }
    
    modifier onlyAdmin() {
        require(msg.sender == admin || msg.sender == owner, 'admin FORBIDDEN');
        _;
    }

    function changeAdmin(address _user) external onlyAdmin {
        require(admin != _user, 'Admin NO CHANGE');
        admin = _user;
    }
}

// Have fun reading it. Hopefully it's bug-free. God bless.
contract SwitchTicketMerchant is SwitchTicketConfigable, ReentrancyGuard, Initializable {
    using SafeMath for uint;

    // Info of each user.
    struct UserInfo {
        uint amount;         // How many tokens the user has provided.
        uint rewardDebt;     // Reward debt. See explanation below.
        uint earnRewardDebt;    // Reward2 debt. See explanation below.
        uint earnTokenDebt;    // Reward3 debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of RewardTokens
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRewardPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
        //   5. User's `earnDebt1` gets updated.
        //   6. User's `earnTokenDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        uint pid;
        address depositToken;           // Address of LP token contract.
        address ticket;
        uint allocPoint;       // How many allocation points assigned to this pool. RewardTokens to distribute per block.
        uint lastRewardBlock;  // Last block number that RewardTokens distribution occurs.
        uint accRewardPerShare;   // Accumulated RewardTokens per share, times 1e18. See below.
        uint accEarnRewardPerShare;   // Accumulated RewardToken2s per share, times 1e18. See below.
        uint accEarnTokenPerShare;   // Accumulated RewardToken3s per share, times 1e18. See below.
        uint depositTokenSupply;
        uint16 depositFeeBP;      // Deposit fee in basis points
        bool added;
    }

    address public weth;

    // The reward TOKEN!
    address public rewardToken;
    // Dev address.
    address public team;
    // reward tokens created per block.
    uint public mintPerBlock;
    // Bonus muliplier for early rewardToken makers.
    uint public constant BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    mapping(uint => PoolInfo) public poolInfo;
    uint[] public pids;
    // Info of each user that stakes tokens.
    mapping(uint => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint public totalAllocPoint;
    // The block number when reward token mining starts.
    uint public startBlock;

    uint public teamRewardRate;
    uint public rewardTotal;
    uint public earnRewardTotal;
    uint public earnTokenTotal;

    address public switchFarm;
    address public switchTicketFactory;

    event Deposit(address indexed user, uint indexed pid, uint amount, uint fee);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount);
    event UpdateEmissionRate(address indexed user, uint mintPerBlock);

    function initialize(
        address _weth,
        address _switchFarm,
        address _switchTicketFactory,
        address _rewardToken,
        address _team,
        address _feeAddress,
        uint _mintPerBlock,
        uint _startBlock
    ) public {
        owner = msg.sender;
        admin = msg.sender;

        weth = _weth;
        switchFarm = _switchFarm;
        switchTicketFactory = _switchTicketFactory;
        rewardToken = _rewardToken;
        team = _team;
        feeAddress = _feeAddress;
        mintPerBlock = _mintPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint) {
        return pids.length;
    }

    mapping(address => bool) public poolExistence;
    
    modifier nonDuplicated(address _depositToken) {
        require(poolExistence[_depositToken] == false, "nonDuplicated: duplicated");
        _;
    }

    receive() external payable {
        assert(msg.sender == weth);
    }

    function checkSwitchAddr() public view returns (bool) {
        if(switchFarm != address(0) && switchTicketFactory != address(0)) {
            return true;
        }
        return false;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // _tokenType 1: token, 2: demax LP, 3: third LP
    function add(bool _withUpdate, uint _pid, uint _allocPoint, address _depositToken, uint16 _depositFeeBP) public onlyOwner nonDuplicated(_depositToken) {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        address ticket;
        if(checkSwitchAddr()) {
            (ticket,,,,,,,) = ISwitchFarm(switchFarm).poolInfo(_pid);
            _depositToken = ISwitchTicketFactory(switchTicketFactory).getTokenMap(ticket);
        }
        
        uint lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_depositToken] = true;
        if(poolInfo[_pid].added == false) {
            pids.push(_pid);
        }
        poolInfo[_pid] = PoolInfo({
            pid: _pid,
            depositToken : _depositToken,
            ticket: ticket,
            allocPoint : _allocPoint,
            lastRewardBlock : lastRewardBlock,
            accRewardPerShare : 0,
            accEarnRewardPerShare : 0,
            accEarnTokenPerShare : 0,
            depositTokenSupply: 0,
            depositFeeBP : _depositFeeBP,
            added: true
        });
    }

    function batchAdd(bool _withUpdate, uint[] memory _pids, uint[] memory _allocPoints, address[] memory _depositTokens, uint16[] memory _depositFeeBPs) public onlyOwner {
        require(_pids.length == _allocPoints.length && _allocPoints.length == _depositTokens.length && _depositTokens.length == _depositFeeBPs.length, 'invalid params');
        for(uint i; i<_allocPoints.length; i++) {
            add(false, _pids[i], _allocPoints[i], _depositTokens[i], _depositFeeBPs[i]);
        }
        if (_withUpdate) {
            massUpdatePools();
        }
    }

    function set(uint _pid, uint _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyAdmin {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    function batchSetAllocPoint(uint[] memory _pids, uint[] memory _allocPoints) public onlyAdmin {
        require(_pids.length == _allocPoints.length, 'invalid params');
        massUpdatePools();
        for (uint i; i<_pids.length; i++) {
            totalAllocPoint = totalAllocPoint.sub(poolInfo[_pids[i]].allocPoint).add(_allocPoints[i]);
            poolInfo[_pids[i]].allocPoint = _allocPoints[i];
        }
    }

    function batchSetDepositFeeBP(uint[] memory _pids, uint16[] memory _depositFeeBPs) public onlyAdmin {
        require(_pids.length == _depositFeeBPs.length, 'invalid params');
        for (uint i; i<_pids.length; i++) {
            poolInfo[_pids[i]].depositFeeBP = _depositFeeBPs[i];
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint _from, uint _to) public view returns (uint) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    function earnToken() public view returns (address) {
        return ISwitchFarm(switchFarm).rewardToken();
    }

    // View function to see pending RewardTokens on frontend.
    function pendingReward(uint _pid, address _user) external view returns (uint) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint accRewardPerShare = pool.accRewardPerShare;
        if (block.number > pool.lastRewardBlock && pool.depositTokenSupply != 0) {
            uint multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint reward = multiplier.mul(mintPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(reward.mul(1e18).div(pool.depositTokenSupply));
        }
        return user.amount.mul(accRewardPerShare).div(1e18).sub(user.rewardDebt);
    }

    function pendingEarnReward(uint _pid, address _user) external view returns (uint) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint accEarnRewardPerShare = pool.accEarnRewardPerShare;
        if (block.number > pool.lastRewardBlock && pool.depositTokenSupply != 0 && earnToken() != address(0)) {
            uint earn = ISwitchFarm(switchFarm).pendingReward(_pid, address(this));
            accEarnRewardPerShare = accEarnRewardPerShare.add(earn.mul(1e18).div(pool.depositTokenSupply));
        }
        return user.amount.mul(accEarnRewardPerShare).div(1e18).sub(user.earnRewardDebt);
    }

    function pendingEarnToken(uint _pid, address _user) external view returns (uint) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint accEarnTokenPerShare = pool.accEarnTokenPerShare;
        if (block.number > pool.lastRewardBlock && pool.depositTokenSupply != 0) {
            uint earn = ISwitchFarm(switchFarm).pendingEarn(_pid, address(this));
            accEarnTokenPerShare = accEarnTokenPerShare.add(earn.mul(1e18).div(pool.depositTokenSupply));
        }
        return user.amount.mul(accEarnTokenPerShare).div(1e18).sub(user.earnTokenDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint length = pids.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (pool.depositTokenSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint reward = multiplier.mul(mintPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        if(teamRewardRate > 0) {
            IRewardToken(rewardToken).mint(team, reward.div(teamRewardRate));
            rewardTotal = rewardTotal.add(reward.div(teamRewardRate));
        }
        IRewardToken(rewardToken).mint(address(this), reward);
        rewardTotal = rewardTotal.add(reward);
        pool.accRewardPerShare = pool.accRewardPerShare.add(reward.mul(1e18).div(pool.depositTokenSupply));

        if(earnToken() != address(0)) {
            if(ISwitchFarm(switchFarm).pendingReward(_pid, address(this)) > 0) {
                uint earn = ISwitchFarm(switchFarm).harvestRewardToken(_pid, address(this));
                earnRewardTotal = earnRewardTotal.add(earn);
                pool.accEarnRewardPerShare = pool.accEarnRewardPerShare.add(earn.mul(1e18).div(pool.depositTokenSupply));
            }
        }

        if(checkSwitchAddr()) {
            if(ISwitchFarm(switchFarm).pendingEarn(_pid, address(this)) > 0) {
                uint earn = ISwitchFarm(switchFarm).harvestEarnToken(_pid, address(this));
                earnTokenTotal = earnTokenTotal.add(earn);
                pool.accEarnTokenPerShare = pool.accEarnTokenPerShare.add(earn.mul(1e18).div(pool.depositTokenSupply));
            }
        }
        
        pool.lastRewardBlock = block.number;
    }

    // Deposit tokens to SwitchTicketMerchant for reward allocation.
    function deposit(uint _pid, uint _amount) payable public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint depositFee;
        if(address(pool.depositToken) == weth) {
            _amount = msg.value;
        }
        if (_amount > 0) {
            if(address(pool.depositToken) == weth) {
                IWETH(weth).deposit{value: _amount}();
            } else {
                IERC20(pool.depositToken).transferFrom(address(msg.sender), address(this), _amount);
            }
            
            if (pool.depositFeeBP > 0) {
                depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                IERC20(pool.depositToken).transfer(feeAddress, depositFee);
                _amount = _amount.sub(depositFee);
            }

            if(checkSwitchAddr()) {
                approveContract(pool.depositToken, switchTicketFactory, _amount);
                address ticket = ISwitchTicketFactory(switchTicketFactory).deposit(pool.depositToken, _amount, address(this));
                approveContract(ticket, switchFarm, _amount);
                (uint resAmount, uint resFee) = ISwitchFarm(switchFarm).deposit(_pid, _amount, address(this));
                _amount = resAmount.sub(resFee);
            }

            user.amount = user.amount.add(_amount);
            pool.depositTokenSupply  = pool.depositTokenSupply.add(_amount);
        }
        
        emit Deposit(msg.sender, _pid, _amount, depositFee);
    }

    // Withdraw tokens from SwitchTicketMerchant.
    function withdraw(uint _pid, uint _amount, bool _isTicket) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        _harvestRewardToken(_pid);
        _harvestEarnReward(_pid);
        _harvestEarnToken(_pid);

        if (_amount > 0) {
            if(checkSwitchAddr()) {
                ISwitchFarm(switchFarm).withdraw(_pid, _amount, address(this));
                address ticket = ISwitchTicketFactory(switchTicketFactory).getTokenMap(pool.depositToken);
                if(_isTicket) {
                    safeTransfer(ticket, msg.sender, _amount);
                } else {
                    bool isETH;
                    if(address(pool.depositToken) == weth) {
                        isETH = true;
                    }
                    ISwitchTicketFactory(switchTicketFactory).withdraw(isETH, msg.sender, ticket, _amount);
                }
            } else {
                safeTransfer(pool.depositToken, msg.sender, _amount);
            }
            user.amount = user.amount.sub(_amount);
            pool.depositTokenSupply = pool.depositTokenSupply.sub(_amount);
            
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        user.earnRewardDebt = user.amount.mul(pool.accEarnRewardPerShare).div(1e18);
        user.earnTokenDebt = user.amount.mul(pool.accEarnTokenPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function _harvestRewardToken(uint _pid) internal returns (uint amount) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint pending = user.amount.mul(pool.accRewardPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) {
            amount = safeTokenTransfer(rewardToken, msg.sender, pending);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        return amount;
    }

    function _harvestEarnReward(uint _pid) internal returns(uint amount) {
        if(switchFarm == address(0)) {
            return 0;
        }
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint pending = user.amount.mul(pool.accEarnRewardPerShare).div(1e18).sub(user.earnRewardDebt);
        if (pending > 0) {
            amount = safeTokenTransfer(earnToken(), msg.sender, pending);
        }
        user.earnRewardDebt = user.amount.mul(pool.accEarnRewardPerShare).div(1e18);
        return amount;
    }
    
    function _harvestEarnToken(uint _pid) internal returns(uint amount) {
        if(switchFarm == address(0)) {
            return 0;
        }
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint pending = user.amount.mul(pool.accEarnTokenPerShare).div(1e18).sub(user.earnTokenDebt);
        if (pending > 0) {
            amount = safeTokenTransfer(pool.depositToken, msg.sender, pending);
        }
        user.earnTokenDebt = user.amount.mul(pool.accEarnTokenPerShare).div(1e18);
        return amount;
    }

    function harvest(uint _pid) public nonReentrant returns (uint reward, uint earnReward, uint earnToken) {
        updatePool(_pid);
        reward = _harvestRewardToken(_pid);
        earnReward = _harvestEarnReward(_pid);
        earnToken = _harvestEarnToken(_pid);
        return (reward, earnReward, earnToken);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint _pid, bool _isTicket) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.earnRewardDebt = 0;
        user.earnTokenDebt = 0;
        pool.depositTokenSupply = pool.depositTokenSupply.sub(amount);
        if(checkSwitchAddr()) {
            ISwitchFarm(switchFarm).withdraw(_pid, amount, address(this));
            address ticket = ISwitchTicketFactory(switchTicketFactory).getTokenMap(pool.depositToken);
            if(_isTicket) {
                safeTransfer(ticket, msg.sender, amount);
            } else {
                bool isETH;
                if(address(pool.depositToken) == weth) {
                    isETH = true;
                }
                ISwitchTicketFactory(switchTicketFactory).withdraw(isETH, msg.sender, ticket, amount);
            }
        } else {
            safeTransfer(pool.depositToken, msg.sender, amount);
        }
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe Token transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeTokenTransfer(address _token, address _to, uint _amount) internal returns(uint) {
        uint tokenBal = IERC20(_token).balanceOf(address(this));
        if(_amount > 0 && tokenBal > 0) {
            if (_amount > tokenBal) {
                _amount = tokenBal;
            }
            IERC20(_token).transfer(_to, _amount);
        }
        return _amount;
    }

    function safeTransfer(address _token, address _to, uint _amount) internal returns(uint) {
        if(_token == weth) {
            IWETH(weth).withdraw(_amount);
            address(uint160(_to)).transfer(_amount);
        } else {
            IERC20(_token).transfer(_to, _amount);
        }
        return _amount;
    }

    function setTeamAddress(address _team) public onlyOwner {
        team = _team;
    }

    function setFeeAddress(address _feeAddress) public onlyOwner {
        feeAddress = _feeAddress;
    }

    function setTeamRewardRate(uint _value) public onlyOwner {
        require(_value >=0 && _value <=10, 'invalid param');
        teamRewardRate = _value;
    }

    //reward has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint _mintPerBlock) public onlyOwner {
        massUpdatePools();
        mintPerBlock = _mintPerBlock;
        emit UpdateEmissionRate(msg.sender, _mintPerBlock);
    }

    function approveContract(address _token, address _spender, uint _amount) internal {
        uint allowAmount = IERC20(_token).totalSupply();
        if(allowAmount < _amount) {
            allowAmount = _amount;
        }
        uint allowance = IERC20(_token).allowance(address(this), _spender);
        if(allowance < _amount) {
            if(allowance > 0) {
                IERC20(_token).approve(_spender, 0); //workaround usdt approve
            }
            IERC20(_token).approve(_spender, allowAmount);
        }
    }
}
