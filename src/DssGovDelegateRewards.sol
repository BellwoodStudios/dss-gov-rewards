pragma solidity ^0.6.7;

interface TokenLike {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface DssGovLike {
    function users(address usr) external view returns (uint256,address,uint256,uint256,uint256,uint256,uint256);
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
}

// Similar to DssGovRewards, but does not use a staked token
contract DssGovDelegateRewards {

    using SafeMath for uint256;

    /* ========== AUTH ========== */
    function rely(address guy) external auth { emit Rely(guy); wards[guy] = 1; }
    function deny(address guy) external auth { emit Deny(guy); wards[guy] = 0; }
    mapping (address => uint256) public wards;
    modifier auth {
        require(wards[msg.sender] == 1, "DssGovRewards/not-authorized");
        _;
    }

    /* ========== STATE VARIABLES ========== */

    TokenLike public rewardsToken;
    DssGovLike public gov;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 private locked = 1; // reentrancy guard
    uint256 public minStake;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _rewardsToken,
        address _gov,
        uint256 _rewardsDuration
    ) public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        rewardsToken = TokenLike(_rewardsToken);
        gov = DssGovLike(_gov);
        rewardsDuration = _rewardsDuration;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
            );
    }

    function earned(address account) public view returns (uint256) {
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function update(address usr) external {
        (,,uint256 rights, uint256 active,,,) = gov.users(usr);
        uint256 balance = _balances[usr];

        if (active == 1 && rights >= minStake) {
            // User is active and has enough MKR to qualify
            if (rights > balance) {
                // Increase balance to match
                stake(usr, rights.sub(balance));
            } else if (rights < balance) {
                // Decrease balance to match
                withdraw(usr, balance.sub(rights));
            }
        } else {
            // User is inactive or does not have enough MKR
            if (balance > 0) withdraw(usr, balance);
        }
    }

    function stake(address sender, uint256 amount) internal nonReentrant updateReward(sender) {
        require(amount > 0, "DssGovDelegateRewards/cannot-stake-0");
        _totalSupply = _totalSupply.add(amount);
        _balances[sender] = _balances[sender].add(amount);
        emit Staked(sender, amount);
    }

    function withdraw(address sender, uint256 amount) internal nonReentrant updateReward(sender) {
        require(amount > 0, "DssGovDelegateRewards/cannot-stake-0");
        _totalSupply = _totalSupply.sub(amount);
        _balances[sender] = _balances[sender].sub(amount);
        emit Withdrawn(sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(msg.sender, _balances[msg.sender]);
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) external auth updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardsToken.balanceOf(address(this));
        require(rewardRate <= balance.div(rewardsDuration), "DssGovDelegateRewards/provided-amount-too-high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    function file(bytes32 what, uint256 data) external auth {
        // Update parameter
        if (what == "minStake") minStake = data;
        else revert("DssGovDelegateRewards/file-unrecognized-param");

        // Emit event
        emit File(what, data);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier nonReentrant {
        require(locked == 1, "DssGovDelegateRewards/reentrancy-guard");
        locked = 2;
        _;
        locked = 1;
    }

    /* ========== EVENTS ========== */

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event File(bytes32 indexed what, uint256 data);
}
