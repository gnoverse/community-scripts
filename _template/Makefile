.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build help

REMOTE ?=
CHAINID ?= test
IMAGE   := $(shell basename $(CURDIR))


## list-funding-one-shot   : print address/amount pairs to fund before one-shot tests
list-funding-one-shot:
	@# Example: @echo "g1_addr1 30000000ugnot g1_addr2 10000000ugnot"
	@echo "not implemented" >&2 && exit 1

## list-funding-repeatable : print address/amount pairs to fund before repeatable tests
list-funding-repeatable:
	@# Example: @echo "g1_addr1 10000000ugnot"
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
