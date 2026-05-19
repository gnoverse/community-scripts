.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build help

comma  := ,
REMOTES                ?=
REMOTE                 ?= $(if $(REMOTES),$(firstword $(subst $(comma), ,$(REMOTES))),http://127.0.0.1:26657)
CHAINID                ?= test
IMAGE                  := $(shell basename $(CURDIR))

FUND_AMOUNT_ONE_SHOT   := 100000000ugnot
FUND_AMOUNT_REPEATABLE := 10000000ugnot
FUND_AMOUNT_PER_WALLET ?= 15000000ugnot

## list-funding-one-shot   : print ugnot amount needed for one-shot tests
list-funding-one-shot:
	@echo "$(FUND_AMOUNT_ONE_SHOT)"

## list-funding-repeatable : print ugnot amount needed for repeatable tests
list-funding-repeatable:
	@echo "$(FUND_AMOUNT_REPEATABLE)"

## build                   : build the Docker test image
build:
	docker build -t $(IMAGE) .

## tests-one-shot          : run one-shot tests (REMOTES, CHAINID)
tests-one-shot: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		-e FUNDER_MNEMONIC \
		-e FUND_AMOUNT=$(FUND_AMOUNT_ONE_SHOT) \
		-e REMOTES=$(REMOTES) \
		-e FUND_AMOUNT_PER_WALLET=$(FUND_AMOUNT_PER_WALLET) \
		$(IMAGE) one-shot

## tests-repeatable        : run repeatable tests (REMOTES, CHAINID)
tests-repeatable: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		-e FUNDER_MNEMONIC \
		-e FUND_AMOUNT=$(FUND_AMOUNT_REPEATABLE) \
		$(IMAGE) repeatable

## help                    : show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
