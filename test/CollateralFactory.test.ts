import { ethers } from 'hardhat';
import { expect } from 'chai';

describe('CollateralFactory', async () => {
  const buildTestContext = async () => {
    const [poolFactoryOwner, randomCollectionOwner, pool] = await ethers.getSigners();

    // Deploy the PoolFactoryMock contract
    const PoolFactoryMock = await ethers.getContractFactory('PoolFactoryMock');
    const poolFactoryMock = await PoolFactoryMock.deploy(pool.address);
    await poolFactoryMock.deployed();

    // Deploy the CollateralFactory contract
    const CollateralFactory = await ethers.getContractFactory('CollateralFactory');
    const collateralFactory = await CollateralFactory.deploy(poolFactoryMock.address);
    await collateralFactory.deployed();

    // Add the collateral factory to the pool factory
    await poolFactoryMock.updateCollateralFactory(collateralFactory.address);
    expect(await poolFactoryMock.collateralFactory()).to.equal(collateralFactory.address);

    return {
      poolFactoryMock,
      poolFactoryOwner,
      randomCollectionOwner,
      collateralFactory,
    };
  };

  it('should create a collateral wrapper', async () => {
    const { collateralFactory, poolFactoryMock, randomCollectionOwner } = await buildTestContext();

    const collateralWrapper = await poolFactoryMock.callStatic.createPool(
      randomCollectionOwner.address,
      ethers.constants.AddressZero,
      1,
      1,
      1,
      ethers.utils.hexlify(ethers.utils.randomBytes(20)),
      ethers.utils.hexlify(ethers.utils.randomBytes(20)),
    );

    const createTx = await poolFactoryMock.createPool(
      randomCollectionOwner.address,
      ethers.constants.AddressZero,
      1,
      1,
      1,
      ethers.utils.hexlify(ethers.utils.randomBytes(20)),
      ethers.utils.hexlify(ethers.utils.randomBytes(20)),
    );

    expect(createTx)
      .to.emit(collateralFactory, 'CollateralWrapperCreated')
      .withArgs(randomCollectionOwner.address, collateralWrapper);

    const createdWrapper = await collateralFactory.collateralWrapper(randomCollectionOwner.address);

    expect(createdWrapper).to.not.equal(ethers.constants.AddressZero);
  });

  it('should revert if a collateral wrapper already exists for a collection', async () => {
    const { poolFactoryMock, randomCollectionOwner } = await buildTestContext();

    // Create a collateral wrapper for a random collection
    await poolFactoryMock.createPool(
      randomCollectionOwner.address,
      ethers.constants.AddressZero,
      1,
      1,
      1,
      ethers.utils.hexlify(ethers.utils.randomBytes(20)),
      ethers.utils.hexlify(ethers.utils.randomBytes(20)),
    );

    // Try to create another collateral wrapper for the same collection, should revert
    await expect(
      poolFactoryMock.createPool(
        randomCollectionOwner.address,
        ethers.constants.AddressZero,
        1,
        1,
        1,
        ethers.utils.hexlify(ethers.utils.randomBytes(20)),
        ethers.utils.hexlify(ethers.utils.randomBytes(20)),
      ),
    ).to.be.revertedWith('CollateralWrapper: Collateral wrapper already exists');
  });

  it('should only allow the pool factory to deploy a collateral wrapper', async () => {
    const { collateralFactory, randomCollectionOwner } = await buildTestContext();

    // Try to create a collateral wrapper without the pool factory, should revert
    await expect(
      collateralFactory.deployCollateralWrapper(randomCollectionOwner.address),
    ).to.be.revertedWith('CollateralWrapper: Only pool factory can call');
  });
});
