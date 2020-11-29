pragma solidity ^0.6.7;

import "dss-interfaces/dss/VatAbstract.sol";
import "dss-interfaces/dss/DaiAbstract.sol";
import "dss-interfaces/dss/DaiJoinAbstract.sol";

import "./DssGovRewards.sol";

// Takes Dai distributed by the keg and forwards it to the rewards contract
contract DaiRewardsDistributor {

    uint256 constant internal RAY = 10 ** 27;

    VatAbstract public immutable vat;
    DaiAbstract public immutable dai;
    DaiJoinAbstract public immutable daiJoin;
    DssGovRewards public immutable target;

    constructor(address _daiJoin, address _target) public {
        DaiJoinAbstract __daiJoin = daiJoin = DaiJoinAbstract(_daiJoin);
        VatAbstract __vat = vat = VatAbstract(__daiJoin.vat());
        dai = DaiAbstract(__daiJoin.dai());
        target = DssGovRewards(_target);
        __vat.hope(_daiJoin);
    }

    function drip() external {
        uint256 wad = vat.dai(address(this)) / RAY;
        daiJoin.exit(address(target), wad);
        target.notifyRewardAmount(wad);
    }

}