<<<<<<< HEAD
# 🦄 Uniswap v4 Hook Incubator — Atrium Academy

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Built with Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange.svg)](https://book.getfoundry.sh/)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.25-lightgrey)](https://soliditylang.org/)
[![Atrium Academy](https://img.shields.io/badge/Atrium-Academy-6E56CF)](https://atrium.academy/uniswap)

This repository contains all of my research, experiments, and projects from **The Atrium Academy’s Uniswap v4 Hook Incubator** — a deep technical program focused on mastering Uniswap v4 Core and building advanced Hooks in Solidity.

---

## 📘 Overview

**Uniswap v4 Hooks** introduce programmable logic that extends AMM behavior — allowing developers to modify pool creation, swaps, and liquidity operations in new ways.  

This repo serves as both a **technical archive** and **project portfolio**, mapping my progress through the incubator’s curriculum and culminating in my **capstone project**.

---

## 🧠 Repository Structure

| Week       | Topic                         | Description                                           |
|:-----------:|:------------------------------|:------------------------------------------------------|
| Weeks 3–4   | Dynamic Fees                   | Volatility-based and adaptive fee models              |
| Week 5      | Return Delta & Derivative Hooks | Non-linear curve logic, async swaps, derivatives      |
| Week 6+     | Periphery Hooks & Bridging      | Multi-chain liquidity and routing logic               |
| Capstone    | Custom Hook Project             | End-to-end design, build, deploy, and present         |

---

## ⚙️ Tech Stack

- **Solidity** (Uniswap v4 Core + Hooks)
- **Foundry** (Forge + Anvil for testing and simulation)
- **Hardhat / TypeScript** (scripts and deployments)
- **Docker + GitHub Actions** (CI/CD setup)

---

## 🧩 Key Projects

### 🧮 Volatility Fee Hook
> Dynamically adjusts swap fees based on short-term volatility — discouraging toxic order flow while rewarding stable LPs.  
📁 [`/hooks/volatility_fee_hook/`](./hooks/volatility_fee_hook)

### ⚖️ Liquidity Rebalancer Hook
> Automates LP position adjustments when price ranges drift — maintaining optimal utilization and passive income.  
📁 [`/hooks/liquidity_rebalancer_hook/`](./hooks/liquidity_rebalancer_hook)

### 🚀 Capstone Project — *[XXX]*
> My final project for the incubator, presented at Demo Day.  
> **Goal:** [XXX]  
📁 [`/hooks/capstone_project/`](./hooks/capstone_project)

---

## 📚 Learning Outcomes

- Deep understanding of **Uniswap v4 architecture**, including transient storage and the singleton pool manager.  
- Practical experience designing **on-chain market mechanisms** with dynamic, composable hooks.  
- Robust development and testing workflow with **Foundry**.  
- Exposure to **MEV-resistant**, **oracle-aware**, and **gas-optimized** design patterns.  
- Completion of a **capstone hook** deployed and presented during Demo Day.

---

## 🧾 License

This repository is released under the [MIT License](LICENSE).  
Use and reference freely with attribution.

---

## 🔗 References

- [Atrium Academy – Uniswap Hook Incubator](https://atrium.academy/uniswap)
- [Uniswap v4 Core Docs](https://docs.uniswap.org/contracts/v4/overview)
- [Zuhaib’s Technical Introduction to Hooks](https://zuhaibmd.medium.com/uniswap-hook-incubator-technical-introduction-1-70c1b07d5814)
- [Uniswap Blog: Announcing v4](https://blog.uniswap.org/uniswap-v4)
- [Foundry Book](https://book.getfoundry.sh/)
=======
## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
>>>>>>> f05c278 (init)
