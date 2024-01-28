import { ethers } from 'hardhat';
import { expect } from 'chai';
import '@openzeppelin/hardhat-upgrades';

describe('PoolFactory', async () => {
  const buildTestContext = async () => {
    const [poolFactoryOwner, protocolFeeCollector, proxyAdmin] = await ethers.getSigners();

    const randomCollectionAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    const randomWrappedNFTAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    const randomLiquidatorAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    const randomNFTFilterAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));

    const loanToValueInBps = 3_000;
    const initialDailyInterestRateInBps = 50;
    const minimalDepositInWei = ethers.utils.parseEther('1');

    // Deploy the implementation contract
    const PoolFactory = await ethers.getContractFactory('PoolFactory');
    const poolFactoryImpl = await PoolFactory.deploy();
    await poolFactoryImpl.deployed();

    // Deploy the TransparentUpgradeableProxy contract
    const TransparentUpgradeableProxy = await ethers.getContractFactory(
      'TransparentUpgradeableProxy',
    );
    const proxy = await TransparentUpgradeableProxy.deploy(
      poolFactoryImpl.address, // logic
      proxyAdmin.address, // admin
      [], // data
    );
    await proxy.deployed();
    const poolFactoryProxy = PoolFactory.attach(proxy.address);
    await poolFactoryProxy.initialize(
      poolFactoryOwner.address,
      protocolFeeCollector.address,
      minimalDepositInWei,
      100, // max pool daily interest rate
    );

    // deploy NFTWrapper Factory
    const NFTWrapperFactoryFactory = await ethers.getContractFactory('NFTWrapperFactory');
    const NFTWrapperFactory = await NFTWrapperFactoryFactory.deploy(poolFactoryProxy.address);
    await NFTWrapperFactory.deployed();

    // deploy Pool implementation
    const Pool = await ethers.getContractFactory('Pool');
    const poolImpl = await Pool.deploy();
    await poolImpl.deployed();

    // update NFTWrapper factory to poolFactory
    await poolFactoryProxy.updateNFTWrapperFactory(NFTWrapperFactory.address);

    // update allowed liquidators to poolFactory
    await poolFactoryProxy.updateAllowedLiquidators([randomLiquidatorAddress]);

    // update pool implementation to poolFactory
    await poolFactoryProxy.updatePoolImplementation(poolImpl.address);

    // update allowed ltv to poolFactory
    await poolFactoryProxy.updateAllowedMinimalDepositsInBPS([loanToValueInBps]);

    // update allowed NFT filters to poolFactory
    await poolFactoryProxy.updateAllowedNFTFilters([randomNFTFilterAddress]);

    return {
      poolFactoryImpl,
      poolFactoryProxy,
      poolFactoryOwner,
      loanToValueInBps,
      randomCollectionAddress,
      initialDailyInterestRateInBps,
      randomWrappedNFTAddress,
      randomLiquidatorAddress,
      randomNFTFilterAddress,
      NFTWrapperFactory,
      minimalDepositInWei,
    };
  };
  it('should deploy PoolFactory', async () => {
    const { poolFactoryImpl } = await buildTestContext();
    expect(poolFactoryImpl.address).to.not.equal(0);
  });
  it('should be initialized', async () => {
    const { poolFactoryProxy, poolFactoryOwner } = await buildTestContext();

    expect(await poolFactoryProxy.owner()).to.equal(poolFactoryOwner.address);
  });
  it('should create a pool if creator is owner', async () => {
    const {
      poolFactoryProxy,
      initialDailyInterestRateInBps,
      loanToValueInBps,
      randomCollectionAddress,
      randomLiquidatorAddress,
      randomNFTFilterAddress,
    } = await buildTestContext();

    const initialDeposit = ethers.utils.parseEther('1');

    const poolProxyAddress = await poolFactoryProxy.callStatic.createPool(
      randomCollectionAddress,
      loanToValueInBps,
      initialDailyInterestRateInBps,
      randomNFTFilterAddress,
      randomLiquidatorAddress,
      { value: initialDeposit },
    );

    await poolFactoryProxy.createPool(
      randomCollectionAddress,
      loanToValueInBps,
      initialDailyInterestRateInBps,
      randomNFTFilterAddress,
      randomLiquidatorAddress,
      { value: initialDeposit },
    );

    const poolProxy = await ethers.getContractAt('Pool', poolProxyAddress);

    expect(await poolProxy.liquidator()).to.deep.equal(randomLiquidatorAddress);
    expect(await poolProxy.nftCollection()).to.deep.equal(randomCollectionAddress);
    expect(await poolProxy.nftFilter()).to.deep.equal(randomNFTFilterAddress);
  });

  it('should create a new pool and emit PoolCreated event if creator is owner', async () => {
    const {
      poolFactoryProxy,
      randomCollectionAddress,
      loanToValueInBps,
      randomNFTFilterAddress,
      randomLiquidatorAddress,
      poolFactoryOwner,
    } = await buildTestContext();
    const initialDeposit = ethers.utils.parseEther('1');

    const [deployer] = await ethers.getSigners();

    const newRandomLiquidatorAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    // update allowed liquidators to poolFactory
    await poolFactoryProxy.updateAllowedLiquidators([newRandomLiquidatorAddress]);

    const futurePoolAddress = await poolFactoryProxy.connect(deployer).callStatic.createPool(
      randomCollectionAddress,
      loanToValueInBps,
      50, // initialDailyInterestRateInBps
      randomNFTFilterAddress,
      newRandomLiquidatorAddress,
      { value: initialDeposit },
    );

    const createPoolTx = await poolFactoryProxy.connect(deployer).createPool(
      randomCollectionAddress,
      loanToValueInBps,
      50, // initialDailyInterestRateInBps
      randomNFTFilterAddress,
      newRandomLiquidatorAddress, // randomLiquidatorAddress
      { value: initialDeposit },
    );

    const receipt = await createPoolTx.wait();

    expect(receipt)
      .to.emit(poolFactoryProxy, 'PoolCreated')
      .withArgs(randomCollectionAddress, loanToValueInBps, futurePoolAddress, deployer.address);
  });

  it('should not create a pool if creator is not owner', async () => {
    const {
      poolFactoryProxy,
      initialDailyInterestRateInBps,
      loanToValueInBps,
      randomCollectionAddress,
      randomLiquidatorAddress,
      randomNFTFilterAddress,
    } = await buildTestContext();

    const initialDeposit = ethers.utils.parseEther('1');

    const [, nonOwner] = await ethers.getSigners();

    await expect(
      poolFactoryProxy
        .connect(nonOwner)
        .createPool(
          randomCollectionAddress,
          loanToValueInBps,
          initialDailyInterestRateInBps,
          randomNFTFilterAddress,
          randomLiquidatorAddress,
          { value: initialDeposit },
        ),
    ).to.be.revertedWith('Ownable: caller is not the owner');
  });

  it('should allow the owner to update allowed LTVs', async () => {
    const { poolFactoryProxy, poolFactoryOwner } = await buildTestContext();
    const newAllowedLTVs = [4000, 5000, 6000];

    await poolFactoryProxy
      .connect(poolFactoryOwner)
      .updateAllowedMinimalDepositsInBPS(newAllowedLTVs);

    const updatedAllowedLTVs = await poolFactoryProxy.getAllowedMinimalDepositsInBPSs();
    expect(updatedAllowedLTVs).to.deep.equal(newAllowedLTVs);
  });

  it('should allow the owner to update allowed NFT filters', async () => {
    const { poolFactoryProxy, poolFactoryOwner, randomNFTFilterAddress } = await buildTestContext();
    const newAllowedNFTFilters = [
      ethers.utils.getAddress(randomNFTFilterAddress),
      ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20))),
    ];

    await expect(
      poolFactoryProxy.connect(poolFactoryOwner).updateAllowedNFTFilters(newAllowedNFTFilters),
    )
      .to.emit(poolFactoryProxy, 'UpdateAllowedNFTFilters')
      .withArgs(newAllowedNFTFilters);

    const updatedAllowedNFTFilters = await poolFactoryProxy.getAllowedNFTFilters();
    expect(updatedAllowedNFTFilters).to.deep.equal(newAllowedNFTFilters);
  });

  it('should allow the owner to update the protocol fee collector', async () => {
    const { poolFactoryProxy, poolFactoryOwner } = await buildTestContext();
    const newProtocolFeeCollector = ethers.utils.hexlify(ethers.utils.randomBytes(20));

    await poolFactoryProxy
      .connect(poolFactoryOwner)
      .updateProtocolFeeCollector(newProtocolFeeCollector);

    const updatedProtocolFeeCollector = await poolFactoryProxy.protocolFeeCollector();
    expect(updatedProtocolFeeCollector).to.deep.equal(newProtocolFeeCollector);
  });

  it('should allow the owner to update the NFTWrapper factory', async () => {
    const { poolFactoryProxy, poolFactoryOwner } = await buildTestContext();
    const newNFTWrapperFactory = ethers.utils.hexlify(ethers.utils.randomBytes(20));

    await poolFactoryProxy.connect(poolFactoryOwner).updateNFTWrapperFactory(newNFTWrapperFactory);

    const updatedNFTWrapperFactory = await poolFactoryProxy.nftWrapperFactory();
    expect(updatedNFTWrapperFactory).to.deep.equal(newNFTWrapperFactory);
  });

  it('should allow the owner to update the pool implementation', async () => {
    const { poolFactoryProxy, poolFactoryOwner } = await buildTestContext();
    const newPoolImplementation = ethers.utils.hexlify(ethers.utils.randomBytes(20));

    await poolFactoryProxy
      .connect(poolFactoryOwner)
      .updatePoolImplementation(newPoolImplementation);

    const updatedPoolImplementation = await poolFactoryProxy.poolImplementation();
    expect(updatedPoolImplementation).to.deep.equal(newPoolImplementation);
  });

  it('should allow the owner to update the minimal deposit', async () => {
    const { poolFactoryProxy, poolFactoryOwner } = await buildTestContext();
    const newMinimalDeposit = ethers.utils.parseEther('2');

    await expect(
      poolFactoryProxy.connect(poolFactoryOwner).updateMinimalDepositAtCreation(newMinimalDeposit),
    )
      .to.emit(poolFactoryProxy, 'UpdateMinimalDepositAtCreation')
      .withArgs(newMinimalDeposit);

    const updatedMinimalDeposit = await poolFactoryProxy.minimalDepositAtCreation();
    expect(updatedMinimalDeposit).to.deep.equal(newMinimalDeposit);
  });

  it('should not allow the same collection and LTV to be used for creating multiple pools', async () => {
    const { poolFactoryProxy, randomCollectionAddress, loanToValueInBps, randomNFTFilterAddress } =
      await buildTestContext();
    const initialDeposit = ethers.utils.parseEther('1');

    const newRandomLiquidatorAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    // update allowed liquidators to poolFactory
    await poolFactoryProxy.updateAllowedLiquidators([newRandomLiquidatorAddress]);

    // Create the first pool
    await poolFactoryProxy.createPool(
      randomCollectionAddress,
      loanToValueInBps,
      50, // initialDailyInterestRateInBps
      randomNFTFilterAddress,
      newRandomLiquidatorAddress, // randomLiquidatorAddress
      { value: initialDeposit },
    );

    // Attempt to create another pool with the same collection and LTV
    await expect(
      poolFactoryProxy.createPool(
        randomCollectionAddress,
        loanToValueInBps,
        50, // initialDailyInterestRateInBps
        randomNFTFilterAddress,
        newRandomLiquidatorAddress, // randomLiquidatorAddress
        { value: initialDeposit },
      ),
    ).to.be.revertedWith('PoolFactory: Pool already exists');
  });

  it('should not allow a non-owner to update allowed LTVs', async () => {
    const { poolFactoryProxy } = await buildTestContext();
    const newAllowedLTVs = [4000, 5000, 6000];

    const [, nonOwner] = await ethers.getSigners();

    // Attempt to update allowed LTVs by a non-owner account
    await expect(
      poolFactoryProxy.connect(nonOwner).updateAllowedMinimalDepositsInBPS(newAllowedLTVs),
    ).to.be.revertedWith('Ownable: caller is not the owner');
  });

  it('should not allow a non-owner to update allowed NFT filters', async () => {
    const { poolFactoryProxy, randomNFTFilterAddress } = await buildTestContext();
    const newAllowedNFTFilters = [
      randomNFTFilterAddress,
      ethers.utils.hexlify(ethers.utils.randomBytes(20)),
    ];

    const [, nonOwner] = await ethers.getSigners();

    // Attempt to update allowed NFT filters by a non-owner account
    await expect(
      poolFactoryProxy.connect(nonOwner).updateAllowedNFTFilters(newAllowedNFTFilters),
    ).to.be.revertedWith('Ownable: caller is not the owner');
  });

  it('should not allow a non-owner to update the protocol fee collector', async () => {
    const { poolFactoryProxy } = await buildTestContext();
    const newProtocolFeeCollector = ethers.utils.hexlify(ethers.utils.randomBytes(20));

    const [, nonOwner] = await ethers.getSigners();

    // Attempt to update the protocol fee collector by a non-owner account
    await expect(
      poolFactoryProxy.connect(nonOwner).updateProtocolFeeCollector(newProtocolFeeCollector),
    ).to.be.revertedWith('Ownable: caller is not the owner');
  });

  it('should not allow a non-owner to update the NFTWrapper factory', async () => {
    const { poolFactoryProxy } = await buildTestContext();
    const newNFTWrapperFactory = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    const [, nonOwner] = await ethers.getSigners();
    // Attempt to update the NFTWrapper factory by a non-owner account
    await expect(
      poolFactoryProxy.connect(nonOwner).updateNFTWrapperFactory(newNFTWrapperFactory),
    ).to.be.revertedWith('Ownable: caller is not the owner');
  });

  it('should not allow a non-owner to update the pool implementation', async () => {
    const { poolFactoryProxy } = await buildTestContext();
    const newPoolImplementation = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    const [, nonOwner] = await ethers.getSigners();

    // Attempt to update the pool implementation by a non-owner account
    await expect(
      poolFactoryProxy.connect(nonOwner).updatePoolImplementation(newPoolImplementation),
    ).to.be.revertedWith('Ownable: caller is not the owner');
  });

  it('should not allow creating a pool with an unsupported NFT filter', async () => {
    const { poolFactoryProxy, randomCollectionAddress, loanToValueInBps } =
      await buildTestContext();
    const initialDeposit = ethers.utils.parseEther('1');
    const unsupportedNFTFilter = ethers.utils.hexlify(ethers.utils.randomBytes(20));

    const newRandomLiquidatorAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    // update allowed liquidators to poolFactory
    await poolFactoryProxy.updateAllowedLiquidators([newRandomLiquidatorAddress]);

    // Attempt to create a pool with an unsupported NFT filter
    await expect(
      poolFactoryProxy.createPool(
        randomCollectionAddress,
        loanToValueInBps,
        50, // initialDailyInterestRateInBps
        unsupportedNFTFilter, // unsupported NFT filter
        newRandomLiquidatorAddress,
        { value: initialDeposit },
      ),
    ).to.be.revertedWith('PoolFactory: NFT filter not allowed');
  });

  it('should not allow creating a pool with insufficient initial ETH deposit', async () => {
    const {
      poolFactoryProxy,
      randomCollectionAddress,
      loanToValueInBps,
      randomNFTFilterAddress,
      minimalDepositInWei,
    } = await buildTestContext();
    const initialDeposit = minimalDepositInWei.sub(1); // Less than required

    const newRandomLiquidatorAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    // update allowed liquidators to poolFactory
    await poolFactoryProxy.updateAllowedLiquidators([newRandomLiquidatorAddress]);

    // Attempt to create a pool with insufficient initial ETH deposit
    await expect(
      poolFactoryProxy.createPool(
        randomCollectionAddress,
        loanToValueInBps,
        50, // initialDailyInterestRateInBps
        randomNFTFilterAddress,
        newRandomLiquidatorAddress,
        { value: initialDeposit },
      ),
    ).to.be.revertedWith('PoolFactory: ETH deposit required to be equal to initial deposit');
  });

  it('should return the list of deployed pools', async () => {
    const { poolFactoryProxy, randomCollectionAddress, loanToValueInBps, randomNFTFilterAddress } =
      await buildTestContext();
    const initialDeposit = ethers.utils.parseEther('1');

    const newRandomLiquidatorAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    // update allowed liquidators to poolFactory
    await poolFactoryProxy.updateAllowedLiquidators([newRandomLiquidatorAddress]);

    // Create a pool
    await poolFactoryProxy.createPool(
      randomCollectionAddress,
      loanToValueInBps,
      50, // initialDailyInterestRateInBps
      randomNFTFilterAddress,
      newRandomLiquidatorAddress,
      { value: initialDeposit },
    );

    // Get the list of deployed pools
    const pools = await poolFactoryProxy.getPools();

    expect(pools.length).to.equal(1);
  });

  it('should check if an address is a pool', async () => {
    const { poolFactoryProxy, randomCollectionAddress, loanToValueInBps, randomNFTFilterAddress } =
      await buildTestContext();
    const initialDeposit = ethers.utils.parseEther('1');

    const newRandomLiquidatorAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    // update allowed liquidators to poolFactory
    await poolFactoryProxy.updateAllowedLiquidators([newRandomLiquidatorAddress]);

    const futurePoolAddress = await poolFactoryProxy.callStatic.createPool(
      randomCollectionAddress,
      loanToValueInBps,
      50, // initialDailyInterestRateInBps
      randomNFTFilterAddress,
      newRandomLiquidatorAddress,
      { value: initialDeposit },
    );

    // Create a pool
    const poolAddress = await poolFactoryProxy.createPool(
      randomCollectionAddress,
      loanToValueInBps,
      50, // initialDailyInterestRateInBps
      randomNFTFilterAddress,
      newRandomLiquidatorAddress,
      { value: initialDeposit },
    );

    // Check if the pool address is recognized as a pool
    const isPool = await poolFactoryProxy.isPool(futurePoolAddress);

    expect(isPool).to.equal(true);
  });

  it('should not allow updating parameters after initialization', async () => {
    const { poolFactoryProxy, poolFactoryOwner } = await buildTestContext();

    // Attempt to update parameters after initialization
    await expect(
      poolFactoryProxy.connect(poolFactoryOwner).initialize(
        ethers.utils.hexlify(ethers.utils.randomBytes(20)), // New factory owner
        ethers.utils.hexlify(ethers.utils.randomBytes(20)), // New protocol fee collector
        0, // New minimal deposit
        100, // New max pool daily interest rate
      ),
    ).to.be.revertedWith('Initializable: contract is already initialized');
  });

  it('should not allow non owner to update the minimal deposit', async () => {
    const { poolFactoryProxy } = await buildTestContext();
    const newMinimalDeposit = ethers.utils.parseEther('2');

    const [, nonOwner] = await ethers.getSigners();

    // Attempt to update the minimal deposit by a non-owner account
    await expect(
      poolFactoryProxy.connect(nonOwner).updateMinimalDepositAtCreation(newMinimalDeposit),
    ).to.be.revertedWith('Ownable: caller is not the owner');
  });

  // TODO: Add test for upgradeToAndCall
});
