pragma solidity ^0.5.16;

import "dss-interfaces/dss/VatAbstract.sol";
import "dss-interfaces/dss/DaiAbstract.sol";
import "dss-interfaces/dss/DaiJoinAbstract.sol";
import "./RewardsDistributionRecipient.sol";

// Takes Dai distributed by the keg and forwards it to the rewards contract
contract DaiRewardsDistributor {

    uint256 constant internal RAY = 10 ** 27;

    VatAbstract public immutable vat;
    DaiAbstract public immutable dai;
    DaiJoinAbstract public immutable daiJoin;
    RewardsDistributionRecipient public immutable target;

    constructor(address _daiJoin, address _target) {
        DaiJoinAbstract __daiJoin = daiJoin = DaiJoinAbstract(_daiJoin);
        vat = VatAbstract(__daiJoin.vat());
        dai = DaiAbstract(__daiJoin.dai());
        target = RewardsDistributionRecipient(_target);
    }

    function drip() external {
        uint256 wad = vat.dai(address(this)) / RAY;
        daiJoin.exit(address(target), wad);
        target.notifyRewardAmount(wad);
    }

}