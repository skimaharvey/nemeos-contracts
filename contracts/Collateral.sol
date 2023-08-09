// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/ICollateralWrapper.sol";

/**
 * @title Collateral Wrapper
 */
contract CollateralWrapper is  ERC721, ReentrancyGuard, Initializable, ICollateralWrapper {

    /**************************************************************************/
    /* Errors */
    /**************************************************************************/

    /**
     * @notice Invalid caller
     */
    error InvalidCaller();

    /**
     * @notice Invalid context
     */
    error InvalidContext();

    /**************************************************************************/
    /* State */
    /**************************************************************************/


    address immutable public poolFactory;

    address[] public pools;

    address private _collection;



    /**************************************************************************/
    /* Events */
    /**************************************************************************/

    /**
     * @notice Emitted when NFT is minted
     * @param tokenId Token ID of the new collateral wrapper token
     * @param account Address that created the NFT
     */
    event NFTMinted(uint256 indexed tokenId, address indexed account);

    /**
     * @notice Emitted when the NFT is unwrapped
     * @param tokenId Token ID of the NFT collateral wrapper token
     * @param account Address that unwrapped the NFT
     */
    event NFTBurnt(uint256 indexed tokenId, address indexed account);

    /**************************************************************************/
    /* Initialization */
    /**************************************************************************/

    constructor() ERC721("Nemeos Wrapper", "NMOSW") {
      _disableInitializers();
    }

    function initialize(address collection_, address poolFactory_) onlyInitializing external {
        _collection = collection_;
        poolFactory = poolFactory_;
    }


    /**************************************************************************/
    /* Modifiers */
    /**************************************************************************/

    modifier onlyPool() {
        require(existsInPools(msg.sender), 'CollateralWrapper: Only pool can call');
        _;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/


    function collection() public view returns(address) {
        return _collection;
    }


    /**
     * @notice Check if token ID exists
     * @param tokenId Token ID
     * @return True if token ID exists, otherwise false
     */
    function exists(uint256 tokenId) external view returns (bool) {
        return _exists(tokenId);
    }


        function existsInPools(address pool_) public view returns (bool) {
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i] == pool_) {
                return true;
            }
        }
        return false;
    }



    /**************************************************************************/
    /* User API */
    /**************************************************************************/


    // Todo: add pool logic so that it is only callable by operator
    /**
     * @notice Deposit NFT collateral into contract and mint a BundleCollateralWrapper token
     *
     * Emits a {NFTMinted} event
     *
     * @dev Collateral token and token ids
     * @param token Collateral token address
     * @param tokenId NFT token IDs
     */
    function mint(address token, uint256 tokenId) external nonReentrant onlyPool returns (uint256) {

        /* Mint BundleCollateralWrapper token */
        _mint(msg.sender, tokenId);

        emit NFTMinted(tokenId, msg.sender);

        return tokenId;
    }



    // TODO: add logic for operator to unwrap as owner will be borrower but unwrapper will be operator (Pool)
    function burn(uint256 tokenId, bytes calldata context) external nonReentrant onlyPool {

        _burn(tokenId);

        emit NFTBurnt(tokenId, msg.sender);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        revert('Not allowed');
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        revert('Not allowed');
    }

    function addPool(address pool) external {
        require(msg.sender == poolFactory, 'CollateralWrapper: Not allowed');
        pools.push(pool);
    }


    /******************************************************/
    /* ERC165 interface */
    /******************************************************/

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(ICollateralWrapper).interfaceId || super.supportsInterface(interfaceId);
    }

}
