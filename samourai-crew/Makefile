.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build help

comma  := ,
REMOTES                ?=
REMOTE                 ?= $(if $(REMOTES),$(firstword $(subst $(comma), ,$(REMOTES))),http://127.0.0.1:26657)
CHAINID                ?= test
IMAGE                  := $(shell basename $(CURDIR))

# 3 wallets — wallet 1 is both the runner (audit/e2e) and stress_1 (first RPC)
ADDR_1 := g1hzlg063fqrq4gltql992ssjc0xzau89t5jp63w
ADDR_2 := g174tsxfpf8zj8h3tyrz4ld690xvhcjnquls6ffc
ADDR_3 := g19xnaenyhe88emmge4726ta43lp3n237vvuzc2n

# wallet 1 gets more funds: covers audit/e2e + stress role
FUND_AMOUNT_WALLET_1   := 50000000ugnot
FUND_AMOUNT_PER_WALLET := 15000000ugnot
FUND_AMOUNT_REPEATABLE := 10000000ugnot

## list-funding-one-shot   : print addresses and amounts to fund before one-shot tests
list-funding-one-shot:
	@echo "$(ADDR_1) $(FUND_AMOUNT_WALLET_1) $(ADDR_2) $(FUND_AMOUNT_PER_WALLET) $(ADDR_3) $(FUND_AMOUNT_PER_WALLET)"

## list-funding-repeatable : print addresses and amounts to fund before repeatable tests
list-funding-repeatable:
	@echo "$(ADDR_1) $(FUND_AMOUNT_REPEATABLE)"

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
