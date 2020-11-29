pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-value/value.sol";
import "ds-token/token.sol";
import {Vat}              from "dss/vat.sol";
import {Spotter}          from "dss/spot.sol";
import {Vow}              from "dss/vow.sol";
import {GemJoin, DaiJoin} from "dss/join.sol";
import {Dai}              from "dss/dai.sol";

import "./DssGovRewards.sol";
import "./DaiRewardsDistributor.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract TestVat is Vat {
    function mint(address usr, uint256 rad) public {
        dai[usr] += rad;
    }
}

contract User {

    DssGovRewards public rewards;
    DSToken public iouToken;

    constructor(DssGovRewards _rewards, DSToken _iouToken) public {
        rewards = _rewards;
        iouToken = _iouToken;
    }

    function doStake(uint256 amount) public {
        iouToken.approve(address(rewards), amount);
        rewards.stake(amount);
    }

    function doWithdraw(uint256 amount) public {
        rewards.withdraw(amount);
    }

    function doGetReward() public {
        rewards.getReward();
    }

    function doExit() public {
        rewards.exit();
    }

}

contract DssGovRewardsTest is DSTest {
    Hevm hevm;

    address me;

    TestVat vat;
    DaiJoin daiJoin;
    Dai dai;
    DSToken iouToken;

    DaiRewardsDistributor distributor;
    DssGovRewards rewards;

    User user1;
    User user2;
    User user3;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    uint256 constant REWARDS_TOLERANCE = uint256(1 ether) / 1 days;

    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 9;
    }

    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 27;
    }

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));

        me = address(this);

        vat = new TestVat();
        vat = vat;

        dai = new Dai(0);
        daiJoin = new DaiJoin(address(vat), address(dai));
        vat.rely(address(daiJoin));
        dai.rely(address(daiJoin));

        iouToken = new DSToken("IOU");
        iouToken.mint(1300 ether);

        rewards = new DssGovRewards(address(dai), address(iouToken), 1 days);
        distributor = new DaiRewardsDistributor(address(daiJoin), address(rewards));
        rewards.rely(address(distributor));

        user1 = new User(rewards, iouToken);
        iouToken.transfer(address(user1), 100 ether);
        user2 = new User(rewards, iouToken);
        iouToken.transfer(address(user2), 100 ether);
        user3 = new User(rewards, iouToken);
        iouToken.transfer(address(user3), 100 ether);
    }

    function assertEq(uint256 a, uint256 b, uint256 tolerance) internal {
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > tolerance) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", b);
            emit log_named_uint("    Actual", a);
            fail();
        }
    }

    function test_stake() public {
        assertEq(rewards.balanceOf(me), 0);
        assertEq(rewards.totalSupply(), 0);

        iouToken.approve(address(rewards), 100 ether);
        rewards.stake(100 ether);

        assertEq(rewards.balanceOf(me), 100 ether);
        assertEq(rewards.totalSupply(), 100 ether);
    }

    function test_withdraw() public {
        iouToken.approve(address(rewards), 100 ether);
        rewards.stake(100 ether);

        assertEq(rewards.balanceOf(me), 100 ether);
        assertEq(iouToken.balanceOf(me), 900 ether);

        rewards.withdraw(100 ether);

        assertEq(iouToken.balanceOf(me), 1000 ether);
        assertEq(rewards.balanceOf(me), 0 ether);
        assertEq(rewards.totalSupply(), 0 ether);
    }

    function test_stake_issue_rewards() public {
        user1.doStake(10 ether);

        assertEq(rewards.periodFinish(), 0);

        vat.mint(address(distributor), rad(24 ether));
        distributor.drip();

        assertEq(rewards.rewardRate(), uint256(24 ether) / 1 days);
        assertEq(rewards.lastUpdateTime(), now);
        assertEq(rewards.periodFinish(), now + 1 days);
        assertEq(rewards.earned(address(user1)), 0 ether, REWARDS_TOLERANCE);

        user1.doGetReward();

        assertEq(dai.balanceOf(address(user1)), 0 ether, REWARDS_TOLERANCE);
        assertEq(rewards.earned(address(user1)), 0 ether, REWARDS_TOLERANCE);

        hevm.warp(now + 1 hours);

        assertEq(dai.balanceOf(address(user1)), 0 ether, REWARDS_TOLERANCE);
        assertEq(rewards.earned(address(user1)), 1 ether, REWARDS_TOLERANCE);

        user1.doGetReward();

        assertEq(dai.balanceOf(address(user1)), 1 ether, REWARDS_TOLERANCE);
        assertEq(rewards.earned(address(user1)), 0 ether, REWARDS_TOLERANCE);

        user2.doStake(10 ether);

        assertEq(dai.balanceOf(address(user2)), 0 ether, REWARDS_TOLERANCE);
        assertEq(rewards.earned(address(user2)), 0 ether, REWARDS_TOLERANCE);

        hevm.warp(now + 2 hours);

        assertEq(rewards.earned(address(user1)), 1 ether, REWARDS_TOLERANCE);
        assertEq(rewards.earned(address(user2)), 1 ether, REWARDS_TOLERANCE);

        user2.doGetReward();

        assertEq(rewards.earned(address(user1)), 1 ether, REWARDS_TOLERANCE);
        assertEq(dai.balanceOf(address(user2)), 1 ether, REWARDS_TOLERANCE);
        assertEq(rewards.earned(address(user2)), 0 ether, REWARDS_TOLERANCE);

        vat.mint(address(distributor), rad(27 ether));
        distributor.drip();

        assertEq(rewards.rewardRate(), uint256(48 ether) / 1 days, 1);
        assertEq(rewards.lastUpdateTime(), now);
        assertEq(rewards.periodFinish(), now + 1 days);
        assertEq(rewards.earned(address(user1)), 1 ether, REWARDS_TOLERANCE);
        assertEq(rewards.earned(address(user2)), 0 ether, REWARDS_TOLERANCE);

        hevm.warp(now + 1 hours);

        assertEq(dai.balanceOf(address(user1)), 1 ether, REWARDS_TOLERANCE);
        assertEq(rewards.earned(address(user1)), 2 ether, REWARDS_TOLERANCE);
        assertEq(dai.balanceOf(address(user2)), 1 ether, REWARDS_TOLERANCE);
        assertEq(rewards.earned(address(user2)), 1 ether, REWARDS_TOLERANCE);

        user1.doGetReward();
        user2.doGetReward();

        assertEq(dai.balanceOf(address(user1)), 3 ether, REWARDS_TOLERANCE);
        assertEq(dai.balanceOf(address(user2)), 2 ether, REWARDS_TOLERANCE);

        hevm.warp(now + 7 days);

        user1.doGetReward();
        user2.doGetReward();

        assertEq(dai.balanceOf(address(user1)), 26 ether, REWARDS_TOLERANCE);
        assertEq(dai.balanceOf(address(user2)), 25 ether, REWARDS_TOLERANCE);
    }

}