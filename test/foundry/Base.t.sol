// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {Test} from "forge-std/Test.sol";

import {CollateralFactory} from "../../contracts/CollateralFactory.sol";
import {CollateralWrapperMock} from "./mocks/CollateralWrapperMock.sol";
import {DutchAuctionLiquidator} from "../../contracts/DutchAuctionLiquidator.sol";
import {NFTFilterMock} from "./mocks/NFTFilterMock.sol";
import {Pool} from "../../contracts/Pool.sol";
import {PoolFactoryMock} from "./mocks/PoolFactoryMock.sol";
import {SeaportSettlementManager} from "../../contracts/SeaportSettlementManager.sol";

import {Users} from "./utils/Types.sol";
import {Constants} from "./utils/Constants.sol";

/// @notice Base test contract with common logic needed by all tests.
abstract contract Base_Test is Test, Constants {
    /**************************************************************************/
    /* Variables */
    /**************************************************************************/

    Users internal users;
    /**************************************************************************/
    /* Tests contracts */
    /**************************************************************************/

    CollateralFactory internal collateralFactory;
    CollateralWrapperMock internal collateralWrapper;
    DutchAuctionLiquidator internal dutchAuctionLiquidator;
    NFTFilterMock internal nftFilter;
    Pool internal pool;
    PoolFactoryMock internal poolFactory;
    SeaportSettlementManager internal seaportSettlementManager;
    ERC721 internal collection;

    /**************************************************************************/
    /* setUP function */
    /**************************************************************************/

    function setUp() public virtual {
        users = Users({
            factoryProxyAdmin: createUser("factoryProxyAdmin"),
            admin: createUser("admin"),
            alice: createUser("alice"),
            eve: createUser("eve"),
            factoryOwner: createUser("factoryOwner"),
            oracle: createUser("oracle"),
            protocolFeeCollector: createUser("protocolFeeCollector"),
            recipient: createUser("recipient"),
            sender: createUser("sender")
        });

        collection = new ERC721("Test", "TST");

        poolFactory = new PoolFactoryMock();
        PoolFactoryMock(address(poolFactory)).initialize(
            users.factoryOwner,
            users.protocolFeeCollector,
            minimalDepositAtCreation,
            maxPoolDailyInterestRateInBPS
        );

        collateralFactory = new CollateralFactory(address(poolFactory));

        vm.startPrank({msgSender: users.factoryOwner});
        // set CollateralFactory to PoolFactory
        PoolFactoryMock(address(poolFactory)).updateCollateralFactory(address(collateralFactory));

        collateralWrapper = new CollateralWrapperMock();
        CollateralWrapperMock(address(collateralWrapper)).initialize(
            address(collection),
            address(poolFactory)
        );

        // set Pool implementation to PoolFactory
        Pool poolImplemenation = new Pool();
        poolFactory.updatePoolImplementation(address(poolImplemenation));

        // set ltvs to PoolFactory
        uint256[] memory ltvsInBPS = new uint256[](1);
        ltvsInBPS[0] = ltvInBPS;
        poolFactory.updateAllowedLTVs(ltvsInBPS);

        dutchAuctionLiquidator = new DutchAuctionLiquidator(
            address(poolFactory),
            liquidationDurationInDays
        );

        seaportSettlementManager = new SeaportSettlementManager();

        address[] memory supportedSettlementManagers = new address[](1);
        nftFilter = new NFTFilterMock(
            users.oracle,
            users.protocolFeeCollector,
            supportedSettlementManagers // left empty since verifyLoanValidity is overriden
        );

        // set liquidator to PoolFactory
        address[] memory liquidators = new address[](1);
        liquidators[0] = address(dutchAuctionLiquidator);
        PoolFactoryMock(address(poolFactory)).updateAllowedLiquidators(liquidators);

        // set NFTFilter to PoolFactory
        address[] memory nftFilters = new address[](1);
        nftFilters[0] = address(nftFilter);
        PoolFactoryMock(address(poolFactory)).updateAllowedNFTFilters(nftFilters);

        address poolAddress = poolFactory.createPool{value: minimalDepositAtCreation}(
            address(collection),
            address(0),
            ltvInBPS,
            initialDailyRateInBPS,
            minimalDepositAtCreation,
            address(nftFilter),
            address(dutchAuctionLiquidator)
        );
        vm.stopPrank();

        pool = Pool(poolAddress);

        // label contracts
        vm.label({account: address(collection), newLabel: "nftCollection"});
        vm.label({account: address(poolFactory), newLabel: "poolFactory"});
        vm.label({account: address(pool), newLabel: "pool"});
        vm.label({account: address(collateralFactory), newLabel: "collateralFactory"});
        vm.label({account: address(collateralWrapper), newLabel: "collateralWrapper"});
        vm.label({account: address(dutchAuctionLiquidator), newLabel: "dutchAuctionLiquidator"});
        vm.label({account: address(nftFilter), newLabel: "nftFilter"});
        vm.label({
            account: address(seaportSettlementManager),
            newLabel: "seaportSettlementManager"
        });

        // Warp to May 1, 2023 at 00:00 GMT to provide a more realistic testing environment.
        vm.warp(MAY_1_2023);
    }

    /**************************************************************************/
    /* Helpers */
    /**************************************************************************/

    /* @dev Generates a user, labels its address, and funds it with test assets. */
    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: 100 ether});
        return user;
    }
}
