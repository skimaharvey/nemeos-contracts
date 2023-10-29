# Nemeos Smart Contracts

## Install

Download the project and its submodules

```bash
git clone --recurse-submodules git@github.com:nemeos/contracts.git
```

If you already cloned but forgot to load the submodules, you can load them with

```bash
git submodule update --init --recursive
```

## Build

```bash
cd lib/seaport
npm install -D
npm run build

cd ../../
npm install -D
npx hardhat compile
```
