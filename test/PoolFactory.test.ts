import { ethers } from 'hardhat';
import { expect } from 'chai';
import '@openzeppelin/hardhat-upgrades';

describe('PoolFactory', async () => {
  const buildTestContext = async () => {
    const [poolFactoryOwner, proxyAdmin] = await ethers.getSigners();

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
    console.log('PoolFactoryProxy address: ', poolFactoryProxy.address);
    await poolFactoryProxy.initialize(poolFactoryOwner.address);

    // deploy Pool implementation
    const Pool = await ethers.getContractFactory('Pool');
    const poolImpl = await Pool.deploy();

    return { poolFactoryImpl, poolFactoryProxy, poolFactoryOwner };
  };
  it('should deploy PoolFactory', async () => {
    const { poolFactoryImpl } = await buildTestContext();
    expect(poolFactoryImpl.address).to.not.equal(0);
  });
  it('should be initialized', async () => {
    const { poolFactoryProxy, poolFactoryOwner } = await buildTestContext();

    expect(await poolFactoryProxy.owner()).to.equal(poolFactoryOwner.address);
  });
});
