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
pnpm install
npx hardhat compile
```
