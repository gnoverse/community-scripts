.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build help

# All runtime variables (account addresses, mnemonics, etc.) must be defined in this
# Makefile and injected into the container via `docker run -e`. Do not hardcode them
# in the Dockerfile — the Makefile is the single source of truth for account config.

# REMOTES: comma-separated list of RPC endpoints passed as-is to your container.
# CI always passes the full list. Your container's entrypoint is responsible for parsing:
#   - for standard tests: extract the first entry and use it as the single RPC
#   - for stress/sybil scenarios: consume the full list (one entry per validator)
# How you parse depends on your language. Shell example: REMOTE="${REMOTES%%,*}"
#   Single RPC:  make tests-one-shot REMOTES=https://rpc.test-13-aeddi-1.gnoland.network CHAINID=test-13
#   Multi  RPC:  make tests-one-shot REMOTES=rpc1,rpc2,rpc3 CHAINID=test-13
REMOTES ?=
CHAINID ?= test
IMAGE   := $(shell basename $(CURDIR))

## list-funding-one-shot   : print address/amount pairs to fund before one-shot tests
list-funding-one-shot:
	@echo "not implemented" >&2 && exit 1

## list-funding-repeatable : print address/amount pairs to fund before repeatable tests
list-funding-repeatable:
	@echo "not implemented" >&2 && exit 1

## build                   : build the Docker test image
build:
	docker build -t $(IMAGE) .

## tests-one-shot          : run one-shot tests (REMOTES, CHAINID)
tests-one-shot: build
	@# Add -e MY_ADDR=$(MY_ADDR) and -e MY_MNEMONIC=$(MY_MNEMONIC) as needed.
	@# Define your addresses and mnemonics as Makefile variables above — not in the Dockerfile.
	docker run --rm \
		-e REMOTES=$(REMOTES) \
		-e CHAINID=$(CHAINID) \
		$(IMAGE) one-shot

## tests-repeatable        : run repeatable tests (REMOTES, CHAINID)
tests-repeatable: build
	@# Add -e MY_ADDR=$(MY_ADDR) and -e MY_MNEMONIC=$(MY_MNEMONIC) as needed.
	@# Define your addresses and mnemonics as Makefile variables above — not in the Dockerfile.
	docker run --rm \
		-e REMOTES=$(REMOTES) \
		-e CHAINID=$(CHAINID) \
		$(IMAGE) repeatable

## help                    : show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
