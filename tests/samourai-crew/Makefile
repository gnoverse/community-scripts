.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build help

# REMOTE: single RPC endpoint passed to the container.
REMOTE                 ?=
CHAINID                ?= test
IMAGE                  := $(shell basename $(CURDIR))

# 3 wallets — wallet 1 is both the runner (audit/e2e) and stress_1 (first RPC)
# Each address is derived from its mnemonic: changing one requires updating the other.
ADDR_1 := g1hzlg063fqrq4gltql992ssjc0xzau89t5jp63w
ADDR_2 := g174tsxfpf8zj8h3tyrz4ld690xvhcjnquls6ffc
ADDR_3 := g19xnaenyhe88emmge4726ta43lp3n237vvuzc2n

MNEMONIC_1 := chair require about ask exhaust you already finger shop turn glory spare credit april rose sniff whale news economy birth table trim raccoon grit
MNEMONIC_2 := knock hat consider bicycle kit lion all cover lawn humble picnic win exit never message leader brother reform silk butter private protect tuition draw
MNEMONIC_3 := galaxy fire athlete egg three crane stone borrow thought cover story poem blush scissors pause slice unusual spread jewel visual tail parent bargain occur

## list-funding-one-shot   : print addresses and amounts to fund before one-shot tests
list-funding-one-shot:
	@echo "$(ADDR_1) 150000000ugnot $(ADDR_2) 15000000ugnot $(ADDR_3) 15000000ugnot"

## list-funding-repeatable : print addresses and amounts to fund before repeatable tests
list-funding-repeatable:
	@echo "$(ADDR_1) 10000000ugnot"

## build                   : build the Docker test image
build:
	docker build -t $(IMAGE) .

## tests-one-shot          : run one-shot tests (REMOTE, CHAINID)
tests-one-shot: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		-e STRESS_ADDR_1=$(ADDR_1) \
		-e STRESS_ADDR_2=$(ADDR_2) \
		-e STRESS_ADDR_3=$(ADDR_3) \
		-e RUNNER_ADDR=$(ADDR_1) \
		-e "STRESS_MNEMONIC_1=$(MNEMONIC_1)" \
		-e "STRESS_MNEMONIC_2=$(MNEMONIC_2)" \
		-e "STRESS_MNEMONIC_3=$(MNEMONIC_3)" \
		-e "RUNNER_MNEMONIC=$(MNEMONIC_1)" \
		$(IMAGE) one-shot

## tests-repeatable        : run repeatable tests (REMOTE, CHAINID)
tests-repeatable: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		-e STRESS_ADDR_1=$(ADDR_1) \
		-e STRESS_ADDR_2=$(ADDR_2) \
		-e STRESS_ADDR_3=$(ADDR_3) \
		-e RUNNER_ADDR=$(ADDR_1) \
		-e "STRESS_MNEMONIC_1=$(MNEMONIC_1)" \
		-e "STRESS_MNEMONIC_2=$(MNEMONIC_2)" \
		-e "STRESS_MNEMONIC_3=$(MNEMONIC_3)" \
		-e "RUNNER_MNEMONIC=$(MNEMONIC_1)" \
		$(IMAGE) repeatable

## help                    : show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
