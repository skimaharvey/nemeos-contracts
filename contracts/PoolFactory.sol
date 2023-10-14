// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Contracts
import {CollateralFactory} from "./CollateralFactory.sol";

// interfaces
import {IPool} from "./interfaces/IPool.sol";
import {ICollateralWrapper} from "./interfaces/ICollateralWrapper.sol";

// libraries
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {
    ERC1967Upgrade
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title PoolFactory
 * @author Nemeos
 */
contract PoolFactory is Ownable, ERC1967Upgrade, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**************************************************************************/
    /* Events */
    /**************************************************************************/

    /**
     * @notice Emitted when a pool is created
     * @param collection Collection address
     * @param ltv Loan to value ratio
     * @param pool Pool address
     * @param deployer Pool deployer address
     */
    event PoolCreated(
        address indexed collection,
        uint256 ltv,
        address pool,
        address indexed deployer
    );

    /**
     * @notice Emitted when the allowed loan to value ratios are updated
     * @param allowdLTVs New allowed loan to value ratios
     */
    event UpdateAllowedLTVs(uint256[] allowdLTVs);

    /**
     * @notice Emitted when the collateral factory is updated
     * @param collateralFactory New collateral factory address
     */
    event UpdateCollateralFactory(address indexed collateralFactory);

    /**
     * @notice Emitted when the pool implementation is updated
     * @param poolImplementation New pool implementation address
     */
    event UpdatePoolImplementation(address indexed poolImplementation);

    /**************************************************************************/
    /* States */
    /**************************************************************************/

    /**
     * @notice Allowed loan to value ratio
     */
    uint256[] public allowdLTVs;

    /**
     * @notice Minimal deposit at creation to avoid inflation attack
     */
    uint256 public minimalDepositAtCreation;

    /**
     * @notice Allowed NFT filters
     */
    address[] public allowedNFTFilters;

    /**
     * @notice Collateral factory address
     */
    address public collateralFactory;

    /**
     * @notice Liquidator address
     */
    address liquidator;

    /**
     * @notice Pool implementation address
     */
    address public poolImplementation;

    /**
     * @notice Protocol fee collector address
     */
    address public protocolFeeCollector;

    /**
     * @notice Set of deployed pools
     */
    EnumerableSet.AddressSet private _pools;

    /**
     * @notice Mapping of collection address to ltv to pool address
     */
    mapping(address => mapping(uint256 => address)) public poolByCollectionAndLtv;

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/

    /**
     * @notice PoolFactory constructor
     */
    constructor() {
        /* Disable initialization of implementation contract */
        _disableInitializers();
    }

    /**************************************************************************/
    /* Initializer */
    /**************************************************************************/

    /**
     * @notice PoolFactory initializator
     */
    function initialize(
        address factoryOwner_,
        address protocolFeeCollector_,
        uint256 minimalDepositAtCreation_
    ) external initializer {
        require(factoryOwner_ != address(0), "PoolFactory: Factory owner cannot be zero address");
        require(
            protocolFeeCollector_ != address(0),
            "PoolFactory: Protocol fee collector cannot be zero address"
        );
        _transferOwnership(factoryOwner_);
        protocolFeeCollector = protocolFeeCollector_;
        minimalDepositAtCreation = minimalDepositAtCreation_;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * Create a 1167 proxy pool instance
     * @param collection_ Collection address
     * @param assets_ Assets address for the pool (address(0) for ETH)
     * @param ltvInBPS_ Loan to value ratio
     * @param initialDailyInterestRateInBPS_ Initial daily interest rate
     * @param nftFilter_ NFT filter address
     * @param liquidator_ Liquidator address
     * @return Pool address
     */
    function createPool(
        address collection_,
        address assets_,
        uint256 ltvInBPS_,
        uint256 initialDailyInterestRateInBPS_,
        uint256 initialDeposit_,
        address nftFilter_,
        address liquidator_
    ) external payable returns (address) {
        address collateralFactoryAddress = collateralFactory;

        /* Check that collateral factory is set */
        require(collateralFactoryAddress != address(0), "PoolFactory: Collateral factory not set");

        /* Check that pool implementation is set */
        require(poolImplementation != address(0), "PoolFactory: Pool implementation not set");

        /* Check that ltv is allowed */
        require(_verifyLtv(ltvInBPS_), "PoolFactory: LTV not allowed");

        /* Check if pool already exists */
        require(
            poolByCollectionAndLtv[collection_][ltvInBPS_] == address(0),
            "PoolFactory: Pool already exists"
        );

        /* Check if nft filter is allowed */
        require(_verifyNFTFilter(nftFilter_), "PoolFactory: NFT filter not allowed");

        /* Check if collection already registered in collateral factory, if not create it */
        address collectionWrapper = CollateralFactory(collateralFactoryAddress).collateralWrapper(
            collection_
        );
        if (collectionWrapper == address(0)) {
            collectionWrapper = CollateralFactory(collateralFactoryAddress).deployCollateralWrapper(
                collection_
            );
        }

        /* Create pool instance */
        address poolInstance = Clones.clone(poolImplementation);

        /* Set pool address in mapping */
        poolByCollectionAndLtv[collection_][ltvInBPS_] = poolInstance;

        /* Add pool to collateral wrapper*/
        ICollateralWrapper(collectionWrapper).addPool(poolInstance);

        /* Initialize pool */
        IPool(poolInstance).initialize(
            collection_,
            assets_,
            ltvInBPS_,
            initialDailyInterestRateInBPS_,
            collectionWrapper,
            liquidator_,
            nftFilter_,
            protocolFeeCollector
        );

        /* should deposit in the Pool in order to avoid inflation attack todo: double check safety */

        if (assets_ == address(0)) {
            require(
                msg.value >= minimalDepositAtCreation && msg.value == initialDeposit_,
                "PoolFactory: ETH deposit required to be equal to initial deposit"
            );
            IPool(poolInstance).depositAndVote{value: msg.value}(
                msg.sender,
                initialDailyInterestRateInBPS_
            );
        } else {
            require(msg.value == 0, "PoolFactory: ETH deposit not allowed");
            IPool(poolInstance).depositERC20(
                msg.sender,
                initialDeposit_,
                initialDailyInterestRateInBPS_
            );
        }

        /* Add pool to registry */
        _pools.add(poolInstance);

        /* Emit Pool Created */
        emit PoolCreated(collection_, ltvInBPS_, poolInstance, msg.sender);

        return poolInstance;
    }

    /**
     * @notice Check if address is a pool
     * @param pool Pool address
     * @return True if address is a pool, otherwise false
     */
    function isPool(address pool) external view returns (bool) {
        return _pools.contains(pool);
    }

    /**
     * @notice Get list of pools
     * @return List of pool addresses
     */
    function getPools() external view returns (address[] memory) {
        return _pools.values();
    }

    /**
     * @notice Get count of pools
     * @return Count of pools
     */
    function getPoolCount() external view returns (uint256) {
        return _pools.length();
    }

    /**
     * @notice Retrieves all allowed LTVs
     * @return List of allowed LTVs
     */
    function getallowdLTVss() external view returns (uint256[] memory) {
        return allowdLTVs;
    }

    /**
     * @notice Retrieves all allowed NFT filters
     * @return List of allowed NFT filters
     */
    function getAllowedNFTFilters() external view returns (address[] memory) {
        return allowedNFTFilters;
    }

    /**************************************************************************/
    /* Admin API */
    /**************************************************************************/

    /**
     * @notice Get Proxy Implementation of the factory
     * @return Implementation address
     */
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    /**
     * @notice Upgrade Proxy of the factory
     * @param newImplementation New implementation contract
     * @param data Optional calldata
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external onlyOwner {
        _upgradeToAndCall(newImplementation, data, false);
    }

    function updateAllowedLTVs(uint256[] calldata allowdLTVs_) external onlyOwner {
        allowdLTVs = allowdLTVs_;

        emit UpdateAllowedLTVs(allowdLTVs_);
    }

    function updateAllowedNFTFilters(address[] calldata allowedNFTFilters_) external onlyOwner {
        allowedNFTFilters = allowedNFTFilters_;
    }

    function updateProtocolFeeCollector(address protocolFeeCollector_) external onlyOwner {
        protocolFeeCollector = protocolFeeCollector_;
    }

    /**
     * @notice Update collateral factory address
     * @param collateralFactory_ New collateral factory address
     */
    function updateCollateralFactory(address collateralFactory_) external onlyOwner {
        collateralFactory = collateralFactory_;
        emit UpdateCollateralFactory(collateralFactory_);
    }

    function updatePoolImplementation(address poolImplementation_) external onlyOwner {
        poolImplementation = poolImplementation_;

        emit UpdatePoolImplementation(poolImplementation_);
    }

    function updateMinimalDepositAtCreation(uint256 minimalDepositAtCreation_) external onlyOwner {
        minimalDepositAtCreation = minimalDepositAtCreation_;
    }

    /**************************************************************************/
    /* Internals */
    /**************************************************************************/

    function _verifyLtv(uint256 ltv_) internal view returns (bool) {
        for (uint256 i = 0; i < allowdLTVs.length; i++) {
            if (allowdLTVs[i] == ltv_) {
                return true;
            }
        }

        return false;
    }

    function _verifyNFTFilter(address nftFilter_) internal view returns (bool) {
        for (uint256 i = 0; i < allowedNFTFilters.length; i++) {
            if (allowedNFTFilters[i] == nftFilter_) {
                return true;
            }
        }

        return false;
    }
}
