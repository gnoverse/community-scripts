.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build help

# Override REMOTES and CHAINID to target a live network:
#   make tests-one-shot REMOTES=https://rpc.test-13-aeddi-1.gnoland.network CHAINID=test-13
comma  := ,
REMOTES ?=
REMOTE  ?= $(if $(REMOTES),$(firstword $(subst $(comma), ,$(REMOTES))),http://127.0.0.1:26657)
CHAINID ?= test
IMAGE   := $(shell basename $(CURDIR))

# TODO: replace with your testnet account address(es)
ADDR_1 := TODO_REPLACE_ADDR_1

# Funding amounts — adjust to match your tests' gas needs (~1M ugnot per tx)
FUND_AMOUNT_ONE_SHOT   := 30000000ugnot
FUND_AMOUNT_REPEATABLE := 10000000ugnot

## list-funding-one-shot   : print address/amount pairs to fund before one-shot tests
list-funding-one-shot:
	@echo "$(ADDR_1) $(FUND_AMOUNT_ONE_SHOT)"

## list-funding-repeatable : print address/amount pairs to fund before repeatable tests
list-funding-repeatable:
	@echo "$(ADDR_1) $(FUND_AMOUNT_REPEATABLE)"

## build                   : build the Docker test image
build:
	docker build -t $(IMAGE) .

## tests-one-shot          : run one-shot tests (REMOTES, CHAINID)
tests-one-shot: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e REMOTES=$(REMOTES) \
		-e CHAINID=$(CHAINID) \
		$(IMAGE) one-shot

## tests-repeatable        : run repeatable tests (REMOTES, CHAINID)
tests-repeatable: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		$(IMAGE) repeatable

## help                    : show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
