# community-scripts

A collection of community-contributed test suites for [gnoland](https://gno.land) chains.

## Purpose

This repository lets contributors package their own tests and run them against any gnoland network via its RPC endpoint — no local node required. The goal is to provide a shared, extensible testing framework that can be wired into CI and executed against public testnets (e.g. `test-13`) or any custom deployment.

## Structure

```text
community-scripts/
├── Makefile                   # root orchestrator
├── funders/
│   ├── gnokey-send.sh         # generic gnokey bank-send (no defaults)
│   ├── _template.sh           # copy this to add a new network
│   ├── test-12.sh             # wrapper for test12
│   └── test-13.sh             # wrapper for test-13
├── _template/
│   └── Makefile               # copy-paste template for new contributors
└── tests/
    └── <contributor>/
        ├── Makefile           # exposes the 4 required rules (see below)
        └── Dockerfile         # self-contained test runner (any language)
```

## Makefile interface

Every contributor subdirectory must expose these four rules:

| Rule                      | Description                                                         |
| ------------------------- | ------------------------------------------------------------------- |
| `list-funding-one-shot`   | Prints `address amount` pairs to fund before one-shot tests         |
| `list-funding-repeatable` | Prints `address amount` pairs to fund before repeatable tests       |
| `tests-one-shot`          | Runs tests that deploy on-chain state (realm deploys...)            |
| `tests-repeatable`        | Runs tests that can be re-executed safely                           |

All rules accept `REMOTES` (comma-separated RPC list) and `CHAINID` variables.

Before each run, the root Makefile calls `list-funding-*`, passes the returned
addresses to the funder script (test1), then runs the tests.

Run `make help` from any directory to list available targets.

## Running tests

Against test-13 with 3 validator nodes:

```sh
make tests-one-shot \
  REMOTES=https://rpc.test-13-aeddi-1.gnoland.network,https://rpc.test-13-gfanton-1.gnoland.network,https://rpc.test-13-moul-1.gnoland.network \
  CHAINID=test-13 \
  FUNDER_SCRIPT=./funders/test-13.sh
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

With a custom funder script:

```sh
make tests-one-shot FUNDER_SCRIPT=./funders/test-13.sh REMOTES=... CHAINID=test-13
```

Directly from a contributor subdirectory:

```sh
cd tests/samourai-crew
make help
make tests-one-shot REMOTES=https://rpc.test12.testnets.gno.land CHAINID=test12
```

## Adding your own tests

### 1. Create your directory

```sh
cp -r _template tests/my-name
```

### 2. Generate a testnet keypair

Generate a dedicated testnet account for your tests (no real value):

```sh
gnokey generate   # save the mnemonic
gnokey add my-test-account -recover
```

### 3. Edit the Makefile

Declare your test account address and funding amounts:

```makefile
ADDR_1 := g1your_address_here

FUND_AMOUNT_ONE_SHOT   := 30000000ugnot   # ~30 transactions at 1M ugnot each
FUND_AMOUNT_REPEATABLE := 10000000ugnot

list-funding-one-shot:
    @echo "$(ADDR_1) $(FUND_AMOUNT_ONE_SHOT)"

list-funding-repeatable:
    @echo "$(ADDR_1) $(FUND_AMOUNT_REPEATABLE)"
```

**Multiple wallets:** declare all addresses in `list-funding-*` as space-separated
`address amount` pairs. The funder will fund each one before the tests run.

### 4. Write your Dockerfile

Your `Dockerfile` must:

- Accept `one-shot` or `repeatable` as a command argument
- Contain your test account mnemonic (testnet key, no real value)
- Read `REMOTES` and `CHAINID` from env
- Sign the network CLA if required (see `samourai-crew/run_tests.sh` for an example)

The image can use **any language** (shell, Go, Python, etc.). See `samourai-crew/` for a shell-based example.

### 5. What your container receives at runtime

| Variable  | Description                                         |
| --------- | --------------------------------------------------- |
| `REMOTES` | Comma-separated list of RPC endpoints               |
| `CHAINID` | Chain ID                                            |

The funding has already been done by the time your container starts.

## Current contributors

| Directory              | Description                                                        |
| ---------------------- | ------------------------------------------------------------------ |
| `tests/samourai-crew`  | GnoVM audit scripts, E2E transaction tests, and sybil stress tests |
