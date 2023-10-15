import { ethers, network } from 'hardhat';
import { expect } from 'chai';

describe('CollateralWrapper', async () => {
  const buildTestContext = async () => {
    const [wrapperOwner, randomUser, ramdomCollection, pool] = await ethers.getSigners();
    // deploy the pool implementation contract
    const Pool = await ethers.getContractFactory('Pool');
    const poolImplementation = await Pool.deploy();

    // deploy the pool factory mock contract
    const PoolFactoryMock = await ethers.getContractFactory('PoolFactoryMock');
    const poolFactoryMock = await PoolFactoryMock.deploy(poolImplementation.address);

    // deploy collateral factory
    const CollateralFactory = await ethers.getContractFactory('CollateralFactory');
    const collateralFactory = await CollateralFactory.deploy(poolFactoryMock.address);

    await poolFactoryMock.updateCollateralFactory(collateralFactory.address);

    // add the pool to the pool factory mock
    await poolFactoryMock.addPool(poolImplementation.address);

    // Deploy the implementation of the CollateralWrapper contract
    const CollateralWrapper = await ethers.getContractFactory('CollateralWrapper');
    const collateralWrapper = await CollateralWrapper.deploy();
    await collateralWrapper.deployed();

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

    // add the pool to collateral wrapper
    await poolFactoryMock.addPoolToCollateralWrapper(proxyAddress, pool.address);

    // attach the proxy contract to the CollateralWrapper interface
    const proxyCollateralInstance = CollateralWrapper.attach(proxyAddress);

    return {
      wrapperOwner,
      pool,
      randomUser,
      collateralWrapper,
      proxyCollateralInstance,
      poolFactoryMock,
    };
  };

  it('should mint a new NFT', async () => {
    const { proxyCollateralInstance, randomUser, pool } = await buildTestContext();

    const tokenId = 1; // Example tokenId
    await expect(proxyCollateralInstance.connect(pool).mint(tokenId, randomUser.address))
      .to.emit(proxyCollateralInstance, 'NFTMinted')
      .withArgs(tokenId, randomUser.address);
  });

  it('should burn an existing NFT', async () => {
    const { proxyCollateralInstance, pool, randomUser } = await buildTestContext();

    const tokenId = 1; // Example tokenId
    await proxyCollateralInstance.connect(pool).mint(tokenId, randomUser.address);
    await expect(proxyCollateralInstance.connect(pool).burn(tokenId))
      .to.emit(proxyCollateralInstance, 'NFTBurnt')
      .withArgs(tokenId, pool.address);
  });

  it('should revert minting if not called by pool', async () => {
    const { proxyCollateralInstance, randomUser } = await buildTestContext();

    const tokenId = 1; // Example tokenId
    await expect(
      proxyCollateralInstance.connect(randomUser).mint(tokenId, randomUser.address),
    ).to.be.revertedWith('CollateralWrapper: Only pool can call');
  });

  it('should add a pool', async () => {
    const { proxyCollateralInstance, pool, poolFactoryMock } = await buildTestContext();

    await expect(
      poolFactoryMock.addPoolToCollateralWrapper(proxyCollateralInstance.address, pool.address),
    )
      .to.emit(proxyCollateralInstance, 'AddPool')
      .withArgs(pool.address);
  });

  it('should revert adding a pool if not called by pool factory', async () => {
    const { proxyCollateralInstance, randomUser } = await buildTestContext();

    await expect(
      proxyCollateralInstance.connect(randomUser).addPool(randomUser.address),
    ).to.be.revertedWith('CollateralWrapper: Only pool factory can call');
  });

  it('should check if token ID exists', async function () {
    const { proxyCollateralInstance, randomUser, pool } = await buildTestContext();
    const tokenId = 1;
    await proxyCollateralInstance.connect(pool).mint(tokenId, randomUser.address);
    const exists = await proxyCollateralInstance.exists(tokenId);
    expect(exists).to.be.true;
  });
});
