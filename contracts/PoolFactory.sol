// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";



/**
 * @title PoolFactory
 * @author Nemeos
 */
contract PoolFactory is Ownable, ERC1967Upgrade, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Emitted when a pool is created
     * @param pool Pool instance
     * @param implementation Implementation contract
     */
    event PoolCreated(address indexed pool, address indexed implementation);



    /**
     * @notice Set of deployed pools
     */
    EnumerableSet.AddressSet private _pools;



    /**
     * @notice PoolFactory constructor
     */
    constructor() {
        /* Disable initialization of implementation contract */
        _disableInitializers();
    }



    /**
     * @notice PoolFactory initializator
     */
    function initialize() onlyInitializing external {
        _transferOwnership(msg.sender);
    }


    /**
     * Create a 1167 proxy pool instance
     * @param poolImplementation Pool implementation contract
     * @param params Pool parameters
     * @return Pool address
     */
    function create(address poolImplementation, bytes calldata params) external returns (address) {
        /* Create pool instance */
        address poolInstance = Clones.clone(poolImplementation);
        Address.functionCall(poolInstance, abi.encodeWithSignature("initialize(bytes)", params));

        /* Add pool to registry */
        _pools.add(poolInstance);

        /* Emit Pool Created */
        emit PoolCreated(poolInstance, poolImplementation);

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


    function getPoolAt(uint256 index) external view returns (address) {
        return _pools.at(index);
    }

    /**************************************************************************/
    /* Admin API */
    /**************************************************************************/

    /**
     * @notice Get Proxy Implementation
     * @return Implementation address
     */
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    /**
     * @notice Upgrade Proxy
     * @param newImplementation New implementation contract
     * @param data Optional calldata
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external onlyOwner {
        _upgradeToAndCall(newImplementation, data, false);
    }
}
