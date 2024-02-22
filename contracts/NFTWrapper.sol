// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

// libraries
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// interfaces
import {INFTWrapper} from "./interfaces/INFTWrapper.sol";

/**
 * @title NFT Wrapper
 * @author Nemeos
 * @notice ERC721 wrapper for NFTs used as wrapped in the Nemeos protocol
 */
contract NFTWrapper is ERC721, ReentrancyGuard, Initializable, INFTWrapper {
    /**************************************************************************/
    /* State */
    /**************************************************************************/

    /**
     * @dev see {INFTWrapper-collection}
     */
    address public collection;

    /**
     * @dev see {INFTWrapper-poolFactory}
     */
    address public poolFactory;

    address[] private _pools;

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/

    constructor() ERC721("NFT Wrapper", "NFT Wrapper") {
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
        require(existsInPools(msg.sender), "NFTWrapper: Only pool can call");
        _;
    }

    modifier onlyPoolFactory() {
        require(msg.sender == poolFactory, "NFTWrapper: Only pool factory can call");
        _;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * @dev see {INFTWrapper-addPool}
     */
    function addPool(address pool_) external onlyPoolFactory {
        _pools.push(pool_);

        emit AddPool(pool_);
    }

    /**
     * @dev see {INFTWrapper-burn}
     */
    function burn(uint256 tokenId_) external onlyPool {
        _burn(tokenId_);

        emit NFTBurnt(tokenId_, msg.sender);
    }

    /**
     * @dev see {INFTWrapper-exists}
     */
    function exists(uint256 tokenId_) external view returns (bool) {
        return _exists(tokenId_);
    }

    /**
     * @dev see {INFTWrapper-existsInPools}
     */
    function existsInPools(address pool_) public view returns (bool) {
        for (uint256 i = 0; i < _pools.length; i++) {
            if (_pools[i] == pool_) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev see {INFTWrapper-mint}
     */
    function mint(
        uint256 tokenId_,
        address receiver_
    ) external nonReentrant onlyPool returns (uint256) {
        _mint(receiver_, tokenId_);

        emit NFTMinted(tokenId_, receiver_);

        return tokenId_;
    }

    /**
     * @dev see {INFTWrapper-pools}
     */
    function pools() external view returns (address[] memory) {
        return _pools;
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address, address, uint256) public virtual override {
        revert("NFTWrapper: transferFrom is disabled");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address, address, uint256) public virtual override {
        revert("NFTWrapper: safeTransferFrom is disabled");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address, address, uint256, bytes memory) public virtual override {
        revert("NFTWrapper: safeTransferFrom is disabled");
    }
}
