# community-scripts

A collection of community-contributed test suites for [gnoland](https://gno.land) chains.

## Purpose

This repository lets contributors package their own tests and run them against any gnoland network via its RPC endpoint — no local node required. The goal is to provide a shared, extensible testing framework that can be wired into CI and executed against public testnets (e.g. `test-13`) or any custom deployment.

## Structure

```text
community-scripts/
├── Makefile                   # root orchestrator
├── funders/
│   └── <network>.sh           # scripts that fund test accounts before a run
└── <contributor>/
    ├── Makefile               # exposes the 4 required rules (see below)
    └── Dockerfile             # self-contained test runner (gnokey + scripts)
```

Each contributor lives in their own subdirectory and is fully autonomous. The only shared contract is a **Makefile interface**.

## Makefile interface

Every contributor subdirectory must expose these four rules:

| Rule                      | Description                                                |
| ------------------------- | ---------------------------------------------------------- |
| `list-funding-one-shot`   | Prints addresses that need funding before one-shot tests   |
| `list-funding-repeatable` | Prints addresses that need funding before repeatable tests |
| `tests-one-shot`          | Runs tests that are not idempotent (e.g. realm deploys)    |
| `tests-repeatable`        | Runs tests that can be re-executed safely                  |

All rules accept a `REMOTE` variable (default: `http://127.0.0.1:26657`) and a `CHAINID` variable.

Contributors may add any extra rules on top of these four.

## Running tests

From the root, using the orchestrator:

```sh
# One-shot tests against test-13
make tests-one-shot \
  FUNDER=./funders/test-13.sh \
  REMOTE=https://rpc.test.gno.land:443 \
  CHAINID=test-13

# Repeatable tests against test-13
make tests-repeatable \
  FUNDER=./funders/test-13.sh \
  REMOTE=https://rpc.test.gno.land:443 \
  CHAINID=test-13
```

Or directly from a contributor subdirectory:

```sh
cd samourai-crew
make tests-one-shot REMOTE=https://rpc.test.gno.land:443 CHAINID=test-13
```

## Contributing

1. Create a subdirectory with your name or team name
2. Add a `Makefile` exposing the four required rules and a `Dockerfile` containing your test runner
3. No dependencies outside of `make` and `docker`

## Current contributors

| Directory         | Description                                    |
| ----------------- | ---------------------------------------------- |
| `samourai-crew`   | GnoVM audit scripts and E2E transaction tests  |
