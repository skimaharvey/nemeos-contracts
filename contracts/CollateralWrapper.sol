// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

// libraries
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Collateral Wrapper
 * @author Nemeos
 */
contract CollateralWrapper is ERC721, ReentrancyGuard, Initializable {
    /**************************************************************************/
    /* State */
    /**************************************************************************/

    address public poolFactory;

    address[] public pools;

    address public collection;

    /**************************************************************************/
    /* Events */
    /**************************************************************************/

    /**
     * @notice Emitted when a pool is added
     * @param pool Address of the pool
     */
    event AddPool(address pool);

    /**
     * @notice Emitted when the NFT is unwrapped
     * @param tokenId Token ID of the NFT collateral wrapper token
     * @param account Address that unwrapped the NFT
     */
    event NFTBurnt(uint256 indexed tokenId, address indexed account);

    /**
     * @notice Emitted when NFT is minted
     * @param tokenId Token ID of the new collateral wrapper token
     * @param account Address that created the NFT
     */
    event NFTMinted(uint256 indexed tokenId, address indexed account);

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/

    constructor() ERC721("Nemeos Wrapper", "NMOSW") {
        _disableInitializers();
    }

    /**************************************************************************/
    /* Initializer */
    /**************************************************************************/

    function initialize(address collection_, address poolFactory_) external virtual initializer {
        collection = collection_;
        poolFactory = poolFactory_;
    }

    /**************************************************************************/
    /* Modifiers */
    /**************************************************************************/

    modifier onlyPool() {
        require(existsInPools(msg.sender), "CollateralWrapper: Only pool can call");
        _;
    }

    modifier onlyPoolFactory() {
        require(msg.sender == poolFactory, "CollateralWrapper: Only pool factory can call");
        _;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

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
    /* Pool API */
    /**************************************************************************/

    /**
     * @notice Burn NFT
     *
     * Emits a {NFTBurnt} event
     *
     * @dev Only pool can call
     * @param tokenId NFT token ID
     */
    function burn(uint256 tokenId) external nonReentrant onlyPool {
        _burn(tokenId);

        emit NFTBurnt(tokenId, msg.sender);
    }

    /**
     * @notice Deposit NFT collateral into contract and mint token
     *
     * Emits a {NFTMinted} event
     *
     * @dev Collateral token and token ids
     * @param tokenId_ NFT token IDs
     * @param receiver_ Address that receives the NFT
     */
    function mint(
        uint256 tokenId_,
        address receiver_
    ) external nonReentrant onlyPool returns (uint256) {
        /* Mint token */
        _mint(receiver_, tokenId_);

        emit NFTMinted(tokenId_, receiver_);

        return tokenId_;
    }

    /**************************************************************************/
    /* Pool Factory API */
    /**************************************************************************/

    function addPool(address pool) external onlyPoolFactory {
        pools.push(pool);

        emit AddPool(pool);
    }
}
