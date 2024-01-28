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
import {IPoolFactory} from "./interfaces/IPoolFactory.sol";

/**
 * @title PoolFactory
 * @author Nemeos
 */
contract PoolFactory is Ownable, ERC1967Upgrade, Initializable, IPoolFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**************************************************************************/
    /* States */
    /**************************************************************************/

    /**
     * @notice Allowed loan to value ratio
     */
    uint256[] public allowedMinimalDepositsInBPS;

    /**
     * @dev see {IPoolFactory-minimalDepositAtCreation}
     */
    uint256 public minimalDepositAtCreation;

    /**
     * @dev see {IPoolFactory-maxPoolDailyLendingRateInBPS}
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
     * @dev see {IPoolFactory-nftWrapperFactory}
     */
    address public nftWrapperFactory;

    /**
     * @dev see {IPoolFactory-liquidator}
     */
    address liquidator;

    /**
     * @dev see {IPoolFactory-poolImplementation}
     */
    address public poolImplementation;

    /**
     * @dev see {IPoolFactory-protocolFeeCollector}
     */
    address public protocolFeeCollector;

    /**
     * @notice Set of deployed pools
     */
    EnumerableSet.AddressSet private _pools;

    /**
     * @notice Mapping of pool address by collection and minimal deposits in BPS
     */
    mapping(address => mapping(uint256 => address)) public _poolByCollectionAndMinimalDeposits;

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
     * @dev see {IPoolFactory-initialize}
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
     * @dev see {IPoolFactory-createPool}
     */
    function createPool(
        address collection_,
        uint256 minimalDepositInBPS_,
        uint256 initialDailyInterestRateInBPS_,
        address nftFilter_,
        address liquidator_
    ) external payable onlyOwner returns (address) {
        address nftWrapperFactoryAddress = nftWrapperFactory;

        /* Check that collateral factory is set */
        require(nftWrapperFactoryAddress != address(0), "PoolFactory: Collateral factory not set");

        /* Check that pool implementation is set */
        require(poolImplementation != address(0), "PoolFactory: Pool implementation not set");

        /* Check that ltv is allowed */
        require(_verifyLtv(minimalDepositInBPS_), "PoolFactory: LTV not allowed");

        /* Check that liquidator is allowed */
        require(_verifyLiquidator(liquidator_), "PoolFactory: Liquidator not allowed");

        /* Check if pool already exists */
        require(
            _poolByCollectionAndMinimalDeposits[collection_][minimalDepositInBPS_] == address(0),
            "PoolFactory: Pool already exists"
        );

        /* should deposit in the Pool in order to avoid inflation attack  */
        require(
            msg.value >= minimalDepositAtCreation,
            "PoolFactory: ETH deposit required to be equal to initial deposit"
        );

        /* Check if nft filter is allowed */
        require(_verifyNFTFilter(nftFilter_), "PoolFactory: NFT filter not allowed");

        /* Check if collection already registered in collateral factory, if not create it */
        address collectionWrapper = NFTWrapperFactory(nftWrapperFactoryAddress).nftWrappers(
            collection_
        );
        if (collectionWrapper == address(0)) {
            collectionWrapper = NFTWrapperFactory(nftWrapperFactoryAddress).deployNFTWrapper(
                collection_
            );
        }

        /* Create pool instance */
        address poolInstance = Clones.clone(poolImplementation);

        /* Set pool address in mapping */
        _poolByCollectionAndMinimalDeposits[collection_][minimalDepositInBPS_] = poolInstance;

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
     * @dev see {IPoolFactory-isPool}
     */
    function isPool(address pool) external view returns (bool) {
        return _pools.contains(pool);
    }

    /**
     * @dev see {IPoolFactory-get_PoolByCollectionAndMinimalDeposits}
     */
    function getPoolByCollectionAndMinimalDeposits(
        address collection_,
        uint256 minimalDepositInBPS_
    ) external view returns (address) {
        return _poolByCollectionAndMinimalDeposits[collection_][minimalDepositInBPS_];
    }

    /**
     * @dev see {IPoolFactory-getPools}
     */
    function getPools() external view returns (address[] memory) {
        return _pools.values();
    }

    /**
     * @dev see {IPoolFactory-getPoolCount}
     */
    function getPoolCount() external view returns (uint256) {
        return _pools.length();
    }

    /**
     * @dev see {IPoolFactory-getAllowedMinimalDepositsInBPSs}
     */
    function getAllowedMinimalDepositsInBPSs() external view returns (uint256[] memory) {
        return allowedMinimalDepositsInBPS;
    }

    /**
     * @dev see {IPoolFactory-getAllowedNFTFilters}
     */
    function getAllowedNFTFilters() external view returns (address[] memory) {
        return allowedNFTFilters;
    }

    /**************************************************************************/
    /* Admin API */
    /**************************************************************************/

    /**
     * @dev see {IPoolFactory-getImplementation}
     */
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    /**
     * @dev see {IPoolFactory-updateAllowedMinimalDepositsInBPS}
     */
    function updateAllowedMinimalDepositsInBPS(
        uint256[] calldata allowedMinimalDepositsInBPS_
    ) external onlyOwner {
        allowedMinimalDepositsInBPS = allowedMinimalDepositsInBPS_;

        emit UpdateAllowedMinimalDepositsInBPS(allowedMinimalDepositsInBPS_);
    }

    /**
     * @dev see {IPoolFactory-updateAllowedLiquidators}
     */
    function updateAllowedLiquidators(address[] calldata allowedLiquidators_) external onlyOwner {
        allowedLiquidators = allowedLiquidators_;

        emit UpdateAllowedLiquidators(allowedLiquidators_);
    }

    /**
     * @dev see {IPoolFactory-updateAllowedNFTFilters}
     */
    function updateAllowedNFTFilters(address[] calldata allowedNFTFilters_) external onlyOwner {
        allowedNFTFilters = allowedNFTFilters_;

        emit UpdateAllowedNFTFilters(allowedNFTFilters_);
    }

    /**
     * @dev see {IPoolFactory-updateNftWrapperFactory}
     */
    function updateNFTWrapperFactory(address nftWrapperFactory_) external onlyOwner {
        nftWrapperFactory = nftWrapperFactory_;
        emit UpdateNFTWrapperFactory(nftWrapperFactory_);
    }

    /**
     * @dev see {IPoolFactory-updateMaxPoolDailyLendingRateInBPS}
     */
    function updateMaxPoolDailyLendingRateInBPS(
        uint256 maxPoolDailyLendingRateInBPS_
    ) external onlyOwner {
        maxPoolDailyLendingRateInBPS = maxPoolDailyLendingRateInBPS_;

        emit UpdateMaxPoolDailyLendingRateInBPS(maxPoolDailyLendingRateInBPS_);
    }

    /**
     * @dev see {IPoolFactory-updateProtocolFeeCollector}
     */
    function updateProtocolFeeCollector(address protocolFeeCollector_) external onlyOwner {
        protocolFeeCollector = protocolFeeCollector_;

        emit UpdateProtocolFeeCollector(protocolFeeCollector_);
    }

    /**
     * @dev see {IPoolFactory-updatePoolImplementation}
     */
    function updatePoolImplementation(address poolImplementation_) external onlyOwner {
        poolImplementation = poolImplementation_;

        emit UpdatePoolImplementation(poolImplementation_);
    }

    /**
     * @dev see {IPoolFactory-updateMinimalDepositAtCreation}
     */
    function updateMinimalDepositAtCreation(uint256 minimalDepositAtCreation_) external onlyOwner {
        minimalDepositAtCreation = minimalDepositAtCreation_;

        emit UpdateMinimalDepositAtCreation(minimalDepositAtCreation_);
    }

    /**
     * @dev see {IPoolFactory-upgradeToAndCall}
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external onlyOwner {
        _upgradeToAndCall(newImplementation, data, false);
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
        for (uint256 i = 0; i < allowedMinimalDepositsInBPS.length; i++) {
            if (allowedMinimalDepositsInBPS[i] == ltv_) {
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
