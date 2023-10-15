// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NFTMock is ERC721 {
    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/

    constructor() ERC721("Nemeos NFT", "NMOS") {}

    /**************************************************************************/
    /* Minting */
    /**************************************************************************/

    /**
     * @notice Mint a new NFT
     * @param to Address to mint the NFT to
     * @param tokenId Token ID of the NFT
     */
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    /**
     * @notice Burn an NFT
     * @param tokenId Token ID of the NFT
     */
    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }
}
