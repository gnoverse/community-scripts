.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build help

REMOTES                ?=
CHAINID                ?= test
IMAGE                  := $(shell basename $(CURDIR))

# 3 wallets — wallet 1 is both the runner (audit/e2e) and stress_1 (first RPC)
ADDR_1 := g1hzlg063fqrq4gltql992ssjc0xzau89t5jp63w
ADDR_2 := g174tsxfpf8zj8h3tyrz4ld690xvhcjnquls6ffc
ADDR_3 := g19xnaenyhe88emmge4726ta43lp3n237vvuzc2n

## list-funding-one-shot   : print addresses and amounts to fund before one-shot tests
list-funding-one-shot:
	@echo "$(ADDR_1) 50000000ugnot $(ADDR_2) 15000000ugnot $(ADDR_3) 15000000ugnot"

## list-funding-repeatable : print addresses and amounts to fund before repeatable tests
list-funding-repeatable:
	@echo "$(ADDR_1) 10000000ugnot"

## build                   : build the Docker test image
build:
	docker build -t $(IMAGE) .

## tests-one-shot          : run one-shot tests (REMOTES, CHAINID)
tests-one-shot: build
	docker run --rm \
		-e REMOTES=$(REMOTES) \
		-e CHAINID=$(CHAINID) \
		-e STRESS_ADDR_1=$(ADDR_1) \
		-e STRESS_ADDR_2=$(ADDR_2) \
		-e STRESS_ADDR_3=$(ADDR_3) \
		-e RUNNER_ADDR=$(ADDR_1) \
		$(IMAGE) one-shot

## tests-repeatable        : run repeatable tests (REMOTES, CHAINID)
tests-repeatable: build
	docker run --rm \
		-e REMOTES=$(REMOTES) \
		-e CHAINID=$(CHAINID) \
		-e STRESS_ADDR_1=$(ADDR_1) \
		-e STRESS_ADDR_2=$(ADDR_2) \
		-e STRESS_ADDR_3=$(ADDR_3) \
		-e RUNNER_ADDR=$(ADDR_1) \
		$(IMAGE) repeatable

## help                    : show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
