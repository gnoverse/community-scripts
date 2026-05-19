.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build help

comma  := ,
REMOTES                ?=
REMOTE                 ?= $(if $(REMOTES),$(firstword $(subst $(comma), ,$(REMOTES))),http://127.0.0.1:26657)
CHAINID                ?= test
IMAGE                  := $(shell basename $(CURDIR))

# TODO: replace with your actual addresses after setting mnemonics in Dockerfile
RUNNER_ADDR   := TODO_REPLACE_RUNNER_ADDR
STRESS_ADDR_1 := TODO_REPLACE_STRESS_ADDR_1
STRESS_ADDR_2 := TODO_REPLACE_STRESS_ADDR_2
STRESS_ADDR_3 := TODO_REPLACE_STRESS_ADDR_3

FUND_AMOUNT_RUNNER     := 30000000ugnot
FUND_AMOUNT_PER_WALLET := 15000000ugnot
FUND_AMOUNT_REPEATABLE := 10000000ugnot

## list-funding-one-shot   : print addresses and amounts to fund before one-shot tests
list-funding-one-shot:
	@echo "$(RUNNER_ADDR) $(FUND_AMOUNT_RUNNER) $(STRESS_ADDR_1) $(FUND_AMOUNT_PER_WALLET) $(STRESS_ADDR_2) $(FUND_AMOUNT_PER_WALLET) $(STRESS_ADDR_3) $(FUND_AMOUNT_PER_WALLET)"

## list-funding-repeatable : print addresses and amounts to fund before repeatable tests
list-funding-repeatable:
	@echo "$(RUNNER_ADDR) $(FUND_AMOUNT_REPEATABLE)"

## build                   : build the Docker test image
build:
	docker build -t $(IMAGE) .

## tests-one-shot          : run one-shot tests (REMOTES, CHAINID)
tests-one-shot: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		-e REMOTES=$(REMOTES) \
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
