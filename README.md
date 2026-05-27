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

All rules accept `REMOTE` (single RPC endpoint) and `CHAINID` variables.

Before each run, the root Makefile calls `list-funding-*`, passes the returned
addresses to the funder script (test1), then runs the tests.

Run `make help` from any directory to list available targets.

## Running tests

Against test-13:

```sh
make tests-one-shot \
  REMOTE=https://rpc.test-13-aeddi-1.gnoland.network \
  CHAINID=test-13 \
  FUNDER_SCRIPT=./funders/test-13.sh
```

Against a single custom RPC:

```sh
make tests-one-shot REMOTE=https://rpc.test12.testnets.gno.land CHAINID=test12
```

With a custom funder:

```sh
make tests-one-shot FUNDER_SCRIPT=./funders/test-13.sh REMOTE=... CHAINID=test-13
```

Directly from a contributor subdirectory:

```sh
cd tests/samourai-crew
make help
make tests-one-shot REMOTE=https://rpc.test12.testnets.gno.land CHAINID=test12
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

Declare your testnet account addresses and mnemonics as Makefile variables, then
implement `list-funding-*` to return the `address amount` pairs the funder needs,
and pass your variables to the container via `-e` in `tests-one-shot` / `tests-repeatable`.

```makefile
ADDR_1     := g1your_address_here
MNEMONIC_1 := word1 word2 ... word24   # 24-word mnemonic for ADDR_1

list-funding-one-shot:
    @echo "$(ADDR_1) 30000000ugnot"

list-funding-repeatable:
    @echo "$(ADDR_1) 10000000ugnot"

tests-one-shot: build
    docker run --rm \
        -e REMOTE=$(REMOTE) \
        -e CHAINID=$(CHAINID) \
        -e MY_ADDR=$(ADDR_1) \
        -e MY_MNEMONIC=$(MNEMONIC_1) \
        $(IMAGE) one-shot
```

**Multiple wallets:** list all `address amount` pairs space-separated in `list-funding-*`.
The funder will fund each one. Pass each address and mnemonic as a separate `-e` flag.

**Never put mnemonics in the Dockerfile** — define them in the Makefile and inject them
at runtime via `docker run -e`. This keeps addresses and mnemonics as a single source of
truth: if you rotate a key, you update one place.

### 4. Write your Dockerfile

Your `Dockerfile` must:

- Accept `one-shot` or `repeatable` as a command argument
- Read `REMOTE`, `CHAINID`, and any account variables from env (injected via `docker run -e`)
- Sign the network CLA if required (see `samourai-crew/run_tests.sh` for an example)

**Do not hardcode mnemonics in the Dockerfile.** Define them in your Makefile and pass
them at runtime via `docker run -e` (see step 3). This way addresses and mnemonics stay
in one place and the Dockerfile contains only logic, not secrets.

The image can use **any language** (shell, Go, Python, etc.). See `samourai-crew/` for a shell-based example.

### 5. What your container receives at runtime

| Variable      | Source            | Description                                          |
| ------------- | ----------------- | ---------------------------------------------------- |
| `REMOTE`      | root Makefile     | Single RPC endpoint                                  |
| `CHAINID`     | root Makefile     | Chain ID                                             |
| `MY_ADDR`     | your Makefile     | Your testnet account address (name it as you like)   |
| `MY_MNEMONIC` | your Makefile     | Your testnet mnemonic (name it as you like)          |

`MY_ADDR` and `MY_MNEMONIC` are examples — use whatever variable names match your suite.
All account variables must be declared in your Makefile and passed via `docker run -e`.

**Reading REMOTE inside your container:**
CI passes the RPC endpoint as `REMOTE`. Your container's entrypoint reads it directly.

Example in shell:

```sh
REMOTE="${REMOTE:-http://127.0.0.1:26657}"
```

See `tests/samourai-crew/` for a complete shell-based implementation.

The funding has already been done by the time your container starts.

## Adding a new network to CI

To wire a new chain into CI, you need two files.

### 1. Create a funder script

```sh
cp funders/_template.sh funders/my-chain.sh
```

Edit `funders/my-chain.sh` and set the three defaults:

```sh
REMOTE="${REMOTE:-https://rpc.my-chain.example.com}"
CHAINID="${CHAINID:-my-chain-id}"
FUNDER_MNEMONIC="${FUNDER_MNEMONIC:-source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast}"
```

The last line is the public test1 mnemonic — replace it if your network uses a different funded account.

### 2. Create a workflow file

```sh
cp .github/workflows/test-13.yml .github/workflows/my-chain.yml
```

Edit `.github/workflows/my-chain.yml`:

```yaml
name: my-chain

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:
    inputs:
      test_type:
        description: 'Test type'
        type: choice
        default: both
        options: [one-shot, repeatable, both]

jobs:
  run:
    uses: ./.github/workflows/ci.yml
    with:
      remote: ${{ vars.REMOTE_MY_CHAIN || 'https://rpc.my-chain.example.com' }}
      chain_id: ${{ vars.CHAINID_MY_CHAIN || 'my-chain-id' }}
      funder_script: ./funders/my-chain.sh
      test_type: ${{ inputs.test_type || 'both' }}
```

### 3. (Optional) Override the RPC via repository variable

If the network RPC changes without a code update, set a repository variable in
**GitHub → Settings → Secrets and variables → Actions → Variables**:

| Variable           | Example value                           |
| ------------------ | --------------------------------------- |
| `REMOTE_MY_CHAIN`  | `https://rpc.my-chain.example.com`      |
| `CHAINID_MY_CHAIN` | `my-chain-id`                           |

The workflow reads these at runtime and falls back to the hardcoded defaults if not set.

## Current contributors

| Directory              | Description                                                        |
| ---------------------- | ------------------------------------------------------------------ |
| `tests/samourai-crew`  | GnoVM audit scripts, E2E transaction tests, and sybil stress tests |
