import { ethers } from 'hardhat';
import { expect } from 'chai';

describe('NFTWrapperFactory', async () => {
  const buildTestContext = async () => {
    const [poolFactoryOwner, randomCollectionOwner, pool] = await ethers.getSigners();

    // Deploy the PoolFactoryMock contract
    const PoolFactoryMock = await ethers.getContractFactory('PoolFactoryMock');
    const poolFactoryMock = await PoolFactoryMock.deploy(pool.address);
    await poolFactoryMock.deployed();

    // Deploy the NFTWrapperFactory contract
    const NFTWrapperFactoryFactory = await ethers.getContractFactory('NFTWrapperFactory');
    const NFTWrapperFactory = await NFTWrapperFactoryFactory.deploy(poolFactoryMock.address);
    await NFTWrapperFactory.deployed();

    // Add the nft factory to the pool factory
    await poolFactoryMock.updateNFTWrapperFactory(NFTWrapperFactory.address);
    expect(await poolFactoryMock.NFTWrapperFactory()).to.equal(NFTWrapperFactory.address);

    return {
      poolFactoryMock,
      poolFactoryOwner,
      randomCollectionOwner,
      NFTWrapperFactory,
    };
  };

  it('should create a nft wrapper', async () => {
    const { NFTWrapperFactory, poolFactoryMock, randomCollectionOwner } = await buildTestContext();

    const NFTWrapper = await poolFactoryMock.callStatic.createPool(
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
      .to.emit(NFTWrapperFactory, 'NFTWrapperCreated')
      .withArgs(randomCollectionOwner.address, NFTWrapper);

    const createdWrapper = await NFTWrapperFactory.nftWrappers(randomCollectionOwner.address);

    expect(createdWrapper).to.not.equal(ethers.constants.AddressZero);
  });

  it('should revert if a NFT wrapper already exists for a collection', async () => {
    const { poolFactoryMock, randomCollectionOwner } = await buildTestContext();

    // Create a NFT wrapper for a random collection
    await poolFactoryMock.createPool(
      randomCollectionOwner.address,
      ethers.constants.AddressZero,
      1,
      1,
      1,
      ethers.utils.hexlify(ethers.utils.randomBytes(20)),
      ethers.utils.hexlify(ethers.utils.randomBytes(20)),
    );

    // Try to create another NFT wrapper for the same collection, should revert
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
    ).to.be.revertedWith('NFTWrapper: NFT wrapper already exists');
  });

  it('should only allow the pool factory to deploy a NFT wrapper', async () => {
    const { NFTWrapperFactory, randomCollectionOwner } = await buildTestContext();

    // Try to create a NFT wrapper without the pool factory, should revert
    await expect(
      NFTWrapperFactory.deployNFTWrapper(randomCollectionOwner.address),
    ).to.be.revertedWith('NFTWrapper: Only pool factory can call');
  });
});
