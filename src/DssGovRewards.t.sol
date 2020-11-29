pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "dss/Vat.sol";

import "./DssGovRewards.sol";
import "./DaiRewardsDistributor.sol";

contract TestVat is Vat {

}

contract DssGovRewardsTest is DSTest {

    DaiRewardsDistributor distributor;
    DssGovRewards rewards;

    function setUp() public {
        rewards = new DssGovRewards();
    }

}
