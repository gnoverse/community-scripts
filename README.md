# community-scripts

A collection of community-contributed test suites for [gnoland](https://gno.land) chains.

## Purpose

This repository lets contributors package their own tests and run them against any gnoland network via its RPC endpoint — no local node required. The goal is to provide a shared, extensible testing framework that can be wired into CI and executed against public testnets (e.g. `test-13`) or any custom deployment.

## Structure

```text
community-scripts/
├── Makefile                   # root orchestrator
├── _template/
│   └── Makefile               # copy-paste template for new contributors
└── <contributor>/
    ├── Makefile               # exposes the 4 required rules (see below)
    └── Dockerfile             # self-contained test runner (any language)
```

## Makefile interface

Every contributor subdirectory must expose these four rules:

| Rule                      | Description                                              |
| ------------------------- | -------------------------------------------------------- |
| `list-funding-one-shot`   | Prints the amount of ugnot needed for one-shot tests     |
| `list-funding-repeatable` | Prints the amount of ugnot needed for repeatable tests   |
| `tests-one-shot`          | Runs tests that deploy on-chain state (realm deploys...) |
| `tests-repeatable`        | Runs tests that can be re-executed safely                |

All rules accept `REMOTES` (comma-separated RPC list) and `CHAINID` variables.
`REMOTE` is automatically derived from the first entry in `REMOTES`.

Before each run, a fresh throwaway wallet is automatically generated and funded by the `test1` faucet account. No pre-existing wallet or secret is required.

Run `make help` from any directory to list available targets.

## Running tests

Against test-13 (default):

```sh
make tests-one-shot
make tests-repeatable
```

Against a single custom RPC:

```sh
make tests-one-shot REMOTES=https://rpc.test12.testnets.gno.land CHAINID=test12
```

Against multiple validator nodes (stress tests will hit each one):

```sh
make tests-one-shot \
  REMOTES=https://rpc1.gnoland.network,https://rpc2.gnoland.network,https://rpc3.gnoland.network \
  CHAINID=test-13
```

Directly from a contributor subdirectory:

```sh
cd samourai-crew
make help
make tests-one-shot REMOTES=https://rpc.test12.testnets.gno.land CHAINID=test12
```

## Adding your own tests

### 1. Create your directory

```sh
cp -r _template my-name
```

### 2. Edit the Makefile

Open `my-name/Makefile` and adjust the funding amounts to match your tests' gas needs:

```makefile
FUND_AMOUNT_ONE_SHOT   := 30000000ugnot   # ~30 transactions at 1M ugnot each
FUND_AMOUNT_REPEATABLE := 10000000ugnot
```

**Multiple wallets:** if your tests require several accounts, declare the total
budget in `list-funding-*` and generate the additional wallets inside your
container, funded from the main runner account.

### 3. Write your Dockerfile

Your `Dockerfile` must produce an image that:

- accepts `one-shot` or `repeatable` as a command argument
- reads the env vars listed below
- generates a throwaway wallet, funds it, and runs the tests

The image can use **any language** (shell, Go, Python, etc.). See `samourai-crew/` for a shell-based example.

### 4. What your container receives at runtime

| Variable                | Description                                          |
| ----------------------- | ---------------------------------------------------- |
| `REMOTE`                | Primary RPC endpoint (first entry of `REMOTES`)      |
| `REMOTES`               | Comma-separated list of RPC endpoints                |
| `CHAINID`               | Chain ID                                             |
| `FUNDER_MNEMONIC`       | test1 mnemonic — used to fund the throwaway wallet   |
| `FUND_AMOUNT`           | Amount to fund (from your `list-funding-*`)          |
| `FUND_AMOUNT_PER_WALLET`| Amount per additional wallet (for multi-wallet tests)|

### 5. No secrets needed

A fresh throwaway wallet is generated inside the container at each run, funded by `test1` (a public faucet account on every gnoland testnet), and discarded after the run.

## Current contributors

| Directory       | Description                                                              |
| --------------- | ------------------------------------------------------------------------ |
| `samourai-crew` | GnoVM audit scripts, E2E transaction tests, and sybil stress tests       |
