import { ethers, network } from 'hardhat';
import { expect } from 'chai';

describe('NFTWrapper', async () => {
  const buildTestContext = async () => {
    const [wrapperOwner, randomUser, ramdomCollection, pool] = await ethers.getSigners();
    // deploy the pool implementation contract
    const Pool = await ethers.getContractFactory('Pool');
    const poolImplementation = await Pool.deploy();

    // deploy the pool factory mock contract
    const PoolFactoryMock = await ethers.getContractFactory('PoolFactoryMock');
    const poolFactoryMock = await PoolFactoryMock.deploy(poolImplementation.address);

    // deploy NFT factory
    const NFTWrapperFactoryFactory = await ethers.getContractFactory('NFTWrapperFactory');
    const NFTWrapperFactory = await NFTWrapperFactoryFactory.deploy(poolFactoryMock.address);

    await poolFactoryMock.updateNFTWrapperFactory(NFTWrapperFactory.address);

    // add the pool to the pool factory mock
    await poolFactoryMock.addPool(poolImplementation.address);

    // Deploy the implementation of the NFTWrapper contract
    const NFTWrapperFactorie = await ethers.getContractFactory('NFTWrapper');
    const NFTWrapper = await NFTWrapperFactorie.deploy();
    await NFTWrapper.deployed();

    // deploy proxy contract
    const [, proxyAddress] = await poolFactoryMock.callStatic.createPool(
      ramdomCollection.address,
      ethers.constants.AddressZero,
      1,
      1,
      1,
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
    );

    await poolFactoryMock.createPool(
      ramdomCollection.address,
      ethers.constants.AddressZero,
      1,
      1,
      1,
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
    );

    // add the pool to NFT wrapper
    await poolFactoryMock.addPoolToNFTWrapperFactory(proxyAddress, pool.address);

    // attach the proxy contract to the NFTWrapper interface
    const proxyNFTInstance = NFTWrapper.attach(proxyAddress);

    return {
      wrapperOwner,
      pool,
      randomUser,
      NFTWrapper,
      proxyNFTInstance,
      poolFactoryMock,
    };
  };

  it('should mint a new NFT', async () => {
    const { proxyNFTInstance, randomUser, pool } = await buildTestContext();

    const tokenId = 1; // Example tokenId
    await expect(proxyNFTInstance.connect(pool).mint(tokenId, randomUser.address))
      .to.emit(proxyNFTInstance, 'NFTMinted')
      .withArgs(tokenId, randomUser.address);
  });

  it('should burn an existing NFT', async () => {
    const { proxyNFTInstance, pool, randomUser } = await buildTestContext();

    const tokenId = 1; // Example tokenId
    await proxyNFTInstance.connect(pool).mint(tokenId, randomUser.address);
    await expect(proxyNFTInstance.connect(pool).burn(tokenId))
      .to.emit(proxyNFTInstance, 'NFTBurnt')
      .withArgs(tokenId, pool.address);
  });

  it('should revert minting if not called by pool', async () => {
    const { proxyNFTInstance, randomUser } = await buildTestContext();

    const tokenId = 1; // Example tokenId
    await expect(
      proxyNFTInstance.connect(randomUser).mint(tokenId, randomUser.address),
    ).to.be.revertedWith('NFTWrapper: Only pool can call');
  });

  it('should add a pool', async () => {
    const { proxyNFTInstance, pool, poolFactoryMock } = await buildTestContext();

    await expect(poolFactoryMock.addPoolToNFTWrapperFactory(proxyNFTInstance.address, pool.address))
      .to.emit(proxyNFTInstance, 'AddPool')
      .withArgs(pool.address);
  });

  it('should revert adding a pool if not called by pool factory', async () => {
    const { proxyNFTInstance, randomUser } = await buildTestContext();

    await expect(
      proxyNFTInstance.connect(randomUser).addPool(randomUser.address),
    ).to.be.revertedWith('NFTWrapper: Only pool factory can call');
  });

  it('should check if token ID exists', async function () {
    const { proxyNFTInstance, randomUser, pool } = await buildTestContext();
    const tokenId = 1;
    await proxyNFTInstance.connect(pool).mint(tokenId, randomUser.address);
    const exists = await proxyNFTInstance.exists(tokenId);
    expect(exists).to.be.true;
  });
});
