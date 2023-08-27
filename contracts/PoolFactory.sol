// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Contracts
import {CollateralFactory} from "./CollateralFactory.sol";

// interfaces
import {IPool} from "./interfaces/IPool.sol";

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
     * @param deployer Pool deployer address
     */
    event PoolCreated(address indexed collection, uint256 ltv, address indexed deployer);

    /**
     * @notice Emitted when the allowed loan to value ratios are updated
     * @param allowedLtv New allowed loan to value ratios
     */
    event UpdateAllowedLtv(uint256[] allowedLtv);

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
    uint256[] allowedLtv;

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
    function initialize(address factoryOwner_) external initializer {
        _transferOwnership(factoryOwner_);
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * Create a 1167 proxy pool instance
     * @param collection_ Collection address
     * @param ltv_ Loan to value ratio
     * @param assets_ Assets address for the pool (address(0) for ETH)
     * @return Pool address
     */
    function createPool(
        address collection_,
        uint256 ltv_,
        address assets_
    ) external payable returns (address) {
        address collateralFactoryAddress = collateralFactory;
        /* Check that collateral factory is set */
        require(collateralFactoryAddress != address(0), "PoolFactory: Collateral factory not set");

        /* Check that pool implementation is set */
        require(poolImplementation != address(0), "PoolFactory: Pool implementation not set");

        /* Check that ltv is allowed */
        require(_verifyLtv(ltv_), "PoolFactory: LTV not allowed");

        /* Check if pool already exists */
        require(
            poolByCollectionAndLtv[collection_][ltv_] == address(0),
            "PoolFactory: Pool already exists"
        );

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

        /* Initialize pool */
        IPool(poolInstance).initialize(collection_, ltv_, collectionWrapper, liquidator);

        /* should deposit in the Pool in order to avoid inflation attack */

        /* Add pool to registry */
        _pools.add(poolInstance);

        /* Emit Pool Created */
        emit PoolCreated(collection_, ltv_, msg.sender);

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

    function updateAllowedLtv(uint256[] calldata allowedLtv_) external onlyOwner {
        allowedLtv = allowedLtv_;

        emit UpdateAllowedLtv(allowedLtv_);
    }

    /**************************************************************************/
    /* Internals */
    /**************************************************************************/

    function _verifyLtv(uint256 ltv_) internal view returns (bool) {
        for (uint256 i = 0; i < allowedLtv.length; i++) {
            if (allowedLtv[i] == ltv_) {
                return true;
            }
        }

        return false;
    }
}
