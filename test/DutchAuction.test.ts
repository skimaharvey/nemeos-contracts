import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deployMockERC721 } from './helpers';

describe('DutchAuctionLiquidator', async () => {
  const buildTestContext = async () => {
    const [nftOwner, owner, borrower, bidder, pool] = await ethers.getSigners();

    // deploy ERC721 mock contract
    const NFTWrapperToken = await deployMockERC721(nftOwner);

    // deploy PoolFactoryMock contract
    const PoolFactoryMock = await ethers.getContractFactory('PoolFactoryMock');
    const poolFactoryMock = await PoolFactoryMock.deploy(pool.address);

    // Deploy the DutchAuctionLiquidator contract
    const DutchAuctionLiquidator = await ethers.getContractFactory('DutchAuctionLiquidator');
    const liquidator = await DutchAuctionLiquidator.deploy(poolFactoryMock.address, 7); // 7 days liquidation duration
    await liquidator.deployed();

    // deploy Pool Mock contract
    const PoolMock = await ethers.getContractFactory('PoolMock');
    const poolMock = await PoolMock.deploy(liquidator.address, NFTWrapperToken.address);

    // add pool to the factory
    await poolFactoryMock.addPool(poolMock.address);

    return {
      nftOwner,
      owner,
      poolMock,
      borrower,
      liquidator,
      poolFactoryMock,
      bidder,
      NFTWrapperToken,
    };
  };

  it('should start a liquidation', async () => {
    const { nftOwner, liquidator, poolMock, borrower, NFTWrapperToken } = await buildTestContext();

    const NFTWrapperTokenId = 1;
    await NFTWrapperToken.mint(nftOwner.address, NFTWrapperTokenId);
    const startingPrice = ethers.utils.parseEther('1');

    // transfer the  token to the liquidator
    await NFTWrapperToken.connect(nftOwner).transferFrom(
      nftOwner.address,
      liquidator.address,
      NFTWrapperTokenId,
    );

    // Start a liquidation
    const liquidationTx = await poolMock.liquidateLoan(NFTWrapperTokenId, borrower.address);
    expect(liquidationTx)
      .to.emit(liquidator, 'LiquidationStarted')
      .withArgs(
        poolMock.address,
        NFTWrapperToken.address,
        NFTWrapperTokenId,
        borrower.address,
        startingPrice,
      );

    const liquidation = await liquidator.getLiquidation(NFTWrapperToken.address, NFTWrapperTokenId);
    expect(liquidation.liquidationStatus).to.equal(true);
    expect(liquidation.pool).to.equal(poolMock.address);
    expect(liquidation.collection).to.equal(NFTWrapperToken.address);
    expect(liquidation.tokenId).to.equal(NFTWrapperTokenId);
    expect(liquidation.startingPrice).to.equal(startingPrice);
  });

  it('should allow a bidder to buy a liquidation', async () => {
    const { nftOwner, liquidator, poolMock, borrower, bidder, NFTWrapperToken } =
      await buildTestContext();
    const NFTWrapperTokenId = 1;
    await NFTWrapperToken.mint(nftOwner.address, NFTWrapperTokenId);

    // transfer the  token to the liquidator
    await NFTWrapperToken.connect(nftOwner).transferFrom(
      nftOwner.address,
      liquidator.address,
      NFTWrapperTokenId,
    );

    // Start a liquidation
    await poolMock.liquidateLoan(NFTWrapperTokenId, borrower.address);

    // Calculate the current price
    const currentPrice = await liquidator.getLiquidationCurrentPrice(
      NFTWrapperToken.address,
      NFTWrapperTokenId,
    );

    // Bidder places a bid
    const tx = await liquidator.connect(bidder).buy(NFTWrapperToken.address, NFTWrapperTokenId, {
      value: currentPrice,
    });

    // Check if the liquidation is ended
    const liquidation = await liquidator.getLiquidation(NFTWrapperToken.address, NFTWrapperTokenId);
    expect(liquidation.liquidationStatus).to.equal(false);

    // Check if the nft wrapper is transferred to the bidder
    const ownerAfterLiquidation = await NFTWrapperToken.ownerOf(NFTWrapperTokenId);
    expect(ownerAfterLiquidation).to.equal(bidder.address);

    // Check the emitted event
    await expect(tx)
      .to.emit(liquidator, 'LiquidationEnded')
      .withArgs(
        NFTWrapperToken.address,
        NFTWrapperTokenId,
        borrower.address,
        bidder.address,
        currentPrice,
      );
  });

  it('should revert if the liquidation is not active when buying', async () => {
    const { nftOwner, liquidator, poolMock, borrower, bidder, NFTWrapperToken } =
      await buildTestContext();

    const NFTWrapperTokenId = 2;
    await NFTWrapperToken.mint(nftOwner.address, NFTWrapperTokenId);
    const startingPrice = ethers.utils.parseEther('2');

    // Transfer the token to the liquidator
    await NFTWrapperToken.connect(nftOwner).transferFrom(
      nftOwner.address,
      liquidator.address,
      NFTWrapperTokenId,
    );

    // Start a liquidation
    await poolMock.liquidateLoan(NFTWrapperTokenId, borrower.address);

    // buy the liquidation
    await liquidator.connect(bidder).buy(NFTWrapperToken.address, NFTWrapperTokenId, {
      value: startingPrice,
    });

    // Try to buy a liquidation that has ended
    await expect(
      liquidator.connect(bidder).buy(NFTWrapperToken.address, NFTWrapperTokenId, {
        value: startingPrice,
      }),
    ).to.be.revertedWith('Liquidator: Liquidation is not active');
  });

  it('should revert if the bid amount is too low', async () => {
    const { nftOwner, liquidator, poolMock, borrower, bidder, NFTWrapperToken } =
      await buildTestContext();

    const NFTWrapperTokenId = 3;
    await NFTWrapperToken.mint(nftOwner.address, NFTWrapperTokenId);

    // Transfer the token to the liquidator
    await NFTWrapperToken.connect(nftOwner).transferFrom(
      nftOwner.address,
      liquidator.address,
      NFTWrapperTokenId,
    );

    // Start a liquidation
    await poolMock.liquidateLoan(NFTWrapperTokenId, borrower.address);

    // Bid with an amount lower than the current price
    const currentPrice = await liquidator.getLiquidationCurrentPrice(
      NFTWrapperToken.address,
      NFTWrapperTokenId,
    );
    const lowBidAmount = currentPrice.sub(ethers.utils.parseEther('0.01')); // Bid is less by 0.01 Ether

    // Try to buy the liquidation with a low bid amount
    await expect(
      liquidator.connect(bidder).buy(NFTWrapperToken.address, NFTWrapperTokenId, {
        value: lowBidAmount,
      }),
    ).to.be.revertedWith('Liquidator: Bid amount is too low');
  });

  it('should not allow non-pool to start a liquidation', async () => {
    const { nftOwner, liquidator, borrower, NFTWrapperToken } = await buildTestContext();

    const NFTWrapperTokenId = 4;
    await NFTWrapperToken.mint(nftOwner.address, NFTWrapperTokenId);
    const startingPrice = ethers.utils.parseEther('4');

    // Transfer the token to the liquidator
    await NFTWrapperToken.connect(nftOwner).transferFrom(
      nftOwner.address,
      liquidator.address,
      NFTWrapperTokenId,
    );

    // Try to start a liquidation as a non-pool
    await expect(
      liquidator
        .connect(borrower) // A non-pool address
        .liquidate(NFTWrapperToken.address, NFTWrapperTokenId, startingPrice, borrower.address),
    ).to.be.revertedWith('Liquidator: Caller is not a pool');
  });
});
