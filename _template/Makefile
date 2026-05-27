.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build help

# All runtime variables (account addresses, mnemonics, etc.) must be defined in this
# Makefile and injected into the container via `docker run -e`. Do not hardcode them
# in the Dockerfile — the Makefile is the single source of truth for account config.

# REMOTE: single RPC endpoint passed to the container.
REMOTE ?=
CHAINID ?= test
IMAGE   := $(shell basename $(CURDIR))

# Declare your testnet account addresses and mnemonics here (one pair per wallet).
# Each address must match its mnemonic — they are the single source of truth for account config.
# Inject them into the container via docker run -e in tests-one-shot / tests-repeatable below.
# ADDR_1     := g1your_address_here
# MNEMONIC_1 := word1 word2 ... word24

## list-funding-one-shot   : print address/amount pairs to fund before one-shot tests
list-funding-one-shot:
	@# Example: @echo "$(ADDR_1) 30000000ugnot $(ADDR_2) 10000000ugnot"
	@echo "not implemented" >&2 && exit 1

## list-funding-repeatable : print address/amount pairs to fund before repeatable tests
list-funding-repeatable:
	@# Example: @echo "$(ADDR_1) 10000000ugnot"
	@echo "not implemented" >&2 && exit 1

## build                   : build the Docker test image
build:
	docker build -t $(IMAGE) .

## tests-one-shot          : run one-shot tests (REMOTE, CHAINID)
tests-one-shot: build
	@# Add -e MY_ADDR=$(MY_ADDR) and -e MY_MNEMONIC=$(MY_MNEMONIC) as needed.
	@# Define your addresses and mnemonics as Makefile variables above — not in the Dockerfile.
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		$(IMAGE) one-shot

## tests-repeatable        : run repeatable tests (REMOTE, CHAINID)
tests-repeatable: build
	@# Add -e MY_ADDR=$(MY_ADDR) and -e MY_MNEMONIC=$(MY_MNEMONIC) as needed.
	@# Define your addresses and mnemonics as Makefile variables above — not in the Dockerfile.
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		$(IMAGE) repeatable

## help                    : show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
