// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {CollateralWrapper} from "./CollateralWrapper.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title Collateral Factory
 */
contract CollateralFactory {
    /**************************************************************************/
    /* State */
    /**************************************************************************/

    address public immutable poolFactory;

    address public immutable collateralImplementationContract = address(new CollateralWrapper());

    /* Collateral wrapper address for a specific collection */
    mapping(address => address) public collateralWrapper;

    /**************************************************************************/
    /* Events */
    /**************************************************************************/

    /**
     * @notice Emitted when a new collateral wrapper is created
     * @param collection Address of the collection
     * @param collateralWrapper Address of the new collateral wrapper
     */
    event CollateralWrapperCreated(address indexed collection, address indexed collateralWrapper);

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/

    constructor(address poolFactory_) {
        poolFactory = poolFactory_;
    }

    /**************************************************************************/
    /* Modifiers */
    /**************************************************************************/

    modifier onlyPoolFactory() {
        require(msg.sender == poolFactory, "CollateralWrapper: Only pool factory can call");
        _;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    function deployCollateralWrapper(
        address collection_
    ) external onlyPoolFactory returns (address collateralWrapperAddress) {
        /* Check if collateral wrapper already exists */
        require(
            collateralWrapper[collection_] == address(0),
            "CollateralWrapper: Collateral wrapper already exists"
        );

        /* Deploy collateral wrapper */
        collateralWrapperAddress = Clones.clone(collateralImplementationContract);

        /* Initialize collateral wrapper */
        CollateralWrapper(collateralWrapperAddress).initialize(collection_, poolFactory);

        /* Update collateralWrapper mapping to avoid deploying twice the  */
        collateralWrapper[collection_] = collateralWrapperAddress;

        /* Emit event */
        emit CollateralWrapperCreated(collection_, collateralWrapperAddress);
    }
}
