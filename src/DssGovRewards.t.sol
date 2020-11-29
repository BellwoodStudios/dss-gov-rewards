pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./DssGovRewards.sol";

contract DssGovRewardsTest is DSTest {
    
    DssGovRewards rewards;

    function setUp() public {
        rewards = new DssGovRewards();
    }

}
