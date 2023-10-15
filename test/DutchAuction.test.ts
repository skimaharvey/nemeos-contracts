import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deployMockERC721 } from './helpers';

describe('DutchAuctionCollateralLiquidator', async () => {
  const buildTestContext = async () => {
    const [nftOwner, owner, borrower, bidder] = await ethers.getSigners();

    // deploy ERC721 mock contract
    const collateralToken = await deployMockERC721(nftOwner);

    // deploy PoolFactoryMock contract
    const PoolFactoryMock = await ethers.getContractFactory('PoolFactoryMock');
    const poolFactoryMock = await PoolFactoryMock.deploy();

    // Deploy the DutchAuctionCollateralLiquidator contract
    const DutchAuctionCollateralLiquidator =
      await ethers.getContractFactory('DutchAuctionLiquidator');
    const liquidator = await DutchAuctionCollateralLiquidator.deploy(poolFactoryMock.address, 7); // 7 days liquidation duration
    await liquidator.deployed();

    // deploy Pool Mock contract
    const PoolMock = await ethers.getContractFactory('PoolMock');
    const poolMock = await PoolMock.deploy(liquidator.address, collateralToken.address);

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
      collateralToken,
    };
  };

  it('should start a liquidation', async () => {
    const { nftOwner, liquidator, poolMock, borrower, collateralToken } = await buildTestContext();

    const collateralTokenId = 1;
    await collateralToken.mint(nftOwner.address, collateralTokenId);
    const startingPrice = ethers.utils.parseEther('1');

    // transfer the  token to the liquidator
    await collateralToken
      .connect(nftOwner)
      .transferFrom(nftOwner.address, liquidator.address, collateralTokenId);

    // Start a liquidation
    const liquidationTx = await poolMock.liquidateLoan(collateralTokenId, borrower.address);
    expect(liquidationTx)
      .to.emit(liquidator, 'LiquidationStarted')
      .withArgs(
        poolMock.address,
        collateralToken.address,
        collateralTokenId,
        borrower.address,
        startingPrice,
      );

    const liquidation = await liquidator.getLiquidation(collateralToken.address, collateralTokenId);
    expect(liquidation.liquidationStatus).to.equal(true);
    expect(liquidation.pool).to.equal(poolMock.address);
    expect(liquidation.collection).to.equal(collateralToken.address);
    expect(liquidation.tokenId).to.equal(collateralTokenId);
    expect(liquidation.startingPrice).to.equal(startingPrice);
  });

  it('should allow a bidder to buy a liquidation', async () => {
    const { nftOwner, liquidator, poolMock, borrower, bidder, collateralToken } =
      await buildTestContext();
    const collateralTokenId = 1;
    await collateralToken.mint(nftOwner.address, collateralTokenId);

    // transfer the  token to the liquidator
    await collateralToken
      .connect(nftOwner)
      .transferFrom(nftOwner.address, liquidator.address, collateralTokenId);

    // Start a liquidation
    await poolMock.liquidateLoan(collateralTokenId, borrower.address);

    // Calculate the current price
    const currentPrice = await liquidator.getLiquidationCurrentPrice(
      collateralToken.address,
      collateralTokenId,
    );

    // Bidder places a bid
    const tx = await liquidator.connect(bidder).buy(collateralToken.address, collateralTokenId, {
      value: currentPrice,
    });

    // Check if the liquidation is ended
    const liquidation = await liquidator.getLiquidation(collateralToken.address, collateralTokenId);
    expect(liquidation.liquidationStatus).to.equal(false);

    // Check if the collateral is transferred to the bidder
    const ownerAfterLiquidation = await collateralToken.ownerOf(collateralTokenId);
    expect(ownerAfterLiquidation).to.equal(bidder.address);

    // Check the emitted event
    await expect(tx)
      .to.emit(liquidator, 'LiquidationEnded')
      .withArgs(
        collateralToken.address,
        collateralTokenId,
        borrower.address,
        bidder.address,
        currentPrice,
      );
  });

  it('should revert if the liquidation is not active when buying', async () => {
    const { nftOwner, liquidator, poolMock, borrower, bidder, collateralToken } =
      await buildTestContext();

    const collateralTokenId = 2;
    await collateralToken.mint(nftOwner.address, collateralTokenId);
    const startingPrice = ethers.utils.parseEther('2');

    // Transfer the token to the liquidator
    await collateralToken
      .connect(nftOwner)
      .transferFrom(nftOwner.address, liquidator.address, collateralTokenId);

    // Start a liquidation
    await poolMock.liquidateLoan(collateralTokenId, borrower.address);

    // buy the liquidation
    await liquidator.connect(bidder).buy(collateralToken.address, collateralTokenId, {
      value: startingPrice,
    });

    // Try to buy a liquidation that has ended
    await expect(
      liquidator.connect(bidder).buy(collateralToken.address, collateralTokenId, {
        value: startingPrice,
      }),
    ).to.be.revertedWith('Liquidator: Liquidation is not active');
  });

  it('should revert if the bid amount is too low', async () => {
    const { nftOwner, liquidator, poolMock, borrower, bidder, collateralToken } =
      await buildTestContext();

    const collateralTokenId = 3;
    await collateralToken.mint(nftOwner.address, collateralTokenId);

    // Transfer the token to the liquidator
    await collateralToken
      .connect(nftOwner)
      .transferFrom(nftOwner.address, liquidator.address, collateralTokenId);

    // Start a liquidation
    await poolMock.liquidateLoan(collateralTokenId, borrower.address);

    // Bid with an amount lower than the current price
    const currentPrice = await liquidator.getLiquidationCurrentPrice(
      collateralToken.address,
      collateralTokenId,
    );
    const lowBidAmount = currentPrice.sub(ethers.utils.parseEther('0.01')); // Bid is less by 0.01 Ether

    // Try to buy the liquidation with a low bid amount
    await expect(
      liquidator.connect(bidder).buy(collateralToken.address, collateralTokenId, {
        value: lowBidAmount,
      }),
    ).to.be.revertedWith('Liquidator: Bid amount is too low');
  });

  it('should not allow non-pool to start a liquidation', async () => {
    const { nftOwner, liquidator, borrower, collateralToken } = await buildTestContext();

    const collateralTokenId = 4;
    await collateralToken.mint(nftOwner.address, collateralTokenId);
    const startingPrice = ethers.utils.parseEther('4');

    // Transfer the token to the liquidator
    await collateralToken
      .connect(nftOwner)
      .transferFrom(nftOwner.address, liquidator.address, collateralTokenId);

    // Try to start a liquidation as a non-pool
    await expect(
      liquidator
        .connect(borrower) // A non-pool address
        .liquidate(collateralToken.address, collateralTokenId, startingPrice, borrower.address),
    ).to.be.revertedWith('Liquidator: Caller is not a pool');
  });
});
