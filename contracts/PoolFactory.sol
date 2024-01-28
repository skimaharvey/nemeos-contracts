// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

// Contracts
import {NFTWrapperFactory} from "./NFTWrapperFactory.sol";

// interfaces
import {IPool} from "./interfaces/IPool.sol";
import {INFTWrapper} from "./interfaces/INFTWrapper.sol";

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
     * @notice Emitted when the allowed liquidators are updated
     * @param allowedLiquidators New allowed liquidators
     */
    event UpdateAllowedLiquidators(address[] allowedLiquidators);

    /**
     * @notice Emitted when the allowed loan to value ratios are updated
     * @param allowedLTVs New allowed loan to value ratios
     */
    event UpdateAllowedLTVs(uint256[] allowedLTVs);

    /**
     * @notice Emitted when the allowed NFT filters are updated
     * @param allowedNFTFilters New allowed NFT filters
     */
    event UpdateAllowedNFTFilters(address[] allowedNFTFilters);

    /**
     * @notice Emitted when the collateral factory is updated
     * @param collateralFactory New collateral factory address
     */
    event UpdateCollateralFactory(address indexed collateralFactory);

    /**
     * @notice Emitted when the max pool daily interest rate is updated
     * @param maxPoolDailyLendingRateInBPS New max pool daily interest rate
     */
    event UpdatemaxPoolDailyLendingRateInBPS(uint256 maxPoolDailyLendingRateInBPS);

    /**
     * @notice Emitted when the minimal deposit at creation is updated
     * @param minimalDepositAtCreation New minimal deposit at creation
     */
    event UpdateMinimalDepositAtCreation(uint256 minimalDepositAtCreation);

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
    uint256[] public allowedLTVs;

    /**
     * @notice Minimal deposit at creation to avoid inflation attack
     */
    uint256 public minimalDepositAtCreation;

    /**
     * @notice Max daily rate interest for the pool (in BPS)
     */
    uint256 public maxPoolDailyLendingRateInBPS;

    /**
     * @notice Allowed NFT filters
     */
    address[] public allowedNFTFilters;

    /**
     * @notice Allowed liquidators
     */
    address[] public allowedLiquidators;

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
        uint256 minimalDepositAtCreation_,
        uint256 maxPoolDailyLendingRateInBPS_
    ) external virtual initializer {
        require(factoryOwner_ != address(0), "PoolFactory: Factory owner cannot be zero address");
        require(
            protocolFeeCollector_ != address(0),
            "PoolFactory: Protocol fee collector cannot be zero address"
        );
        _transferOwnership(factoryOwner_);
        protocolFeeCollector = protocolFeeCollector_;
        minimalDepositAtCreation = minimalDepositAtCreation_;
        maxPoolDailyLendingRateInBPS = maxPoolDailyLendingRateInBPS_;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * Create a 1167 proxy pool instance
     * @param collection_ Collection address
     * @param minimalDepositInBPS_ Loan to value ratio
     * @param initialDailyInterestRateInBPS_ Initial daily interest rate
     * @param nftFilter_ NFT filter address
     * @param liquidator_ Liquidator address
     * @return Pool address
     */
    function createPool(
        address collection_,
        uint256 minimalDepositInBPS_,
        uint256 initialDailyInterestRateInBPS_,
        uint256 initialDeposit_,
        address nftFilter_,
        address liquidator_
    ) external payable onlyOwner returns (address) {
        address collateralFactoryAddress = collateralFactory;

        /* Check that collateral factory is set */
        require(collateralFactoryAddress != address(0), "PoolFactory: Collateral factory not set");

        /* Check that pool implementation is set */
        require(poolImplementation != address(0), "PoolFactory: Pool implementation not set");

        /* Check that ltv is allowed */
        require(_verifyLtv(minimalDepositInBPS_), "PoolFactory: LTV not allowed");

        /* Check that liquidator is allowed */
        require(_verifyLiquidator(liquidator_), "PoolFactory: Liquidator not allowed");

        /* Check if pool already exists */
        require(
            poolByCollectionAndLtv[collection_][minimalDepositInBPS_] == address(0),
            "PoolFactory: Pool already exists"
        );

        /* should deposit in the Pool in order to avoid inflation attack  */
        require(
            msg.value >= minimalDepositAtCreation && msg.value == initialDeposit_,
            "PoolFactory: ETH deposit required to be equal to initial deposit"
        );

        /* Check if nft filter is allowed */
        require(_verifyNFTFilter(nftFilter_), "PoolFactory: NFT filter not allowed");

        /* Check if collection already registered in collateral factory, if not create it */
        address collectionWrapper = NFTWrapperFactory(collateralFactoryAddress).nftWrappers(
            collection_
        );
        if (collectionWrapper == address(0)) {
            collectionWrapper = NFTWrapperFactory(collateralFactoryAddress).deployNFTWrapper(
                collection_
            );
        }

        /* Create pool instance */
        address poolInstance = Clones.clone(poolImplementation);

        /* Set pool address in mapping */
        poolByCollectionAndLtv[collection_][minimalDepositInBPS_] = poolInstance;

        /* Add pool to collateral wrapper*/
        INFTWrapper(collectionWrapper).addPool(poolInstance);

        /* Initialize pool */
        IPool(poolInstance).initialize(
            collection_,
            minimalDepositInBPS_,
            maxPoolDailyLendingRateInBPS,
            collectionWrapper,
            liquidator_,
            nftFilter_,
            protocolFeeCollector
        );

        IPool(poolInstance).depositAndVote{value: msg.value}(
            msg.sender,
            initialDailyInterestRateInBPS_
        );

        /* Add pool to registry */
        _pools.add(poolInstance);

        /* Emit Pool Created */
        emit PoolCreated(collection_, minimalDepositInBPS_, poolInstance, msg.sender);

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
    function getallowedLTVss() external view returns (uint256[] memory) {
        return allowedLTVs;
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

    function updateAllowedLTVs(uint256[] calldata allowedLTVs_) external onlyOwner {
        allowedLTVs = allowedLTVs_;

        emit UpdateAllowedLTVs(allowedLTVs_);
    }

    function updateAllowedLiquidators(address[] calldata allowedLiquidators_) external onlyOwner {
        allowedLiquidators = allowedLiquidators_;

        emit UpdateAllowedLiquidators(allowedLiquidators_);
    }

    function updateAllowedNFTFilters(address[] calldata allowedNFTFilters_) external onlyOwner {
        allowedNFTFilters = allowedNFTFilters_;

        emit UpdateAllowedNFTFilters(allowedNFTFilters_);
    }

    function updatemaxPoolDailyLendingRateInBPS(
        uint256 maxPoolDailyLendingRateInBPS_
    ) external onlyOwner {
        maxPoolDailyLendingRateInBPS = maxPoolDailyLendingRateInBPS_;

        emit UpdatemaxPoolDailyLendingRateInBPS(maxPoolDailyLendingRateInBPS_);
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

        emit UpdateMinimalDepositAtCreation(minimalDepositAtCreation_);
    }

    /**************************************************************************/
    /* Internals */
    /**************************************************************************/
    function _verifyLiquidator(address liquidator_) internal view returns (bool) {
        for (uint256 i = 0; i < allowedLiquidators.length; i++) {
            if (allowedLiquidators[i] == liquidator_) {
                return true;
            }
        }

        return false;
    }

    function _verifyLtv(uint256 ltv_) internal view returns (bool) {
        for (uint256 i = 0; i < allowedLTVs.length; i++) {
            if (allowedLTVs[i] == ltv_) {
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
