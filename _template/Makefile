.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build

# Override REMOTE and CHAINID to target a live network:
#   make tests-one-shot REMOTE=https://rpc.test12.testnets.gno.land CHAINID=test12
REMOTE  ?= http://127.0.0.1:26657
CHAINID ?= test
IMAGE   := $(shell basename $(CURDIR))

# Amount of ugnot needed to run the tests.
# A fresh throwaway wallet is generated and funded with this amount before each run.
FUND_AMOUNT_ONE_SHOT   := 100000000ugnot
FUND_AMOUNT_REPEATABLE := 10000000ugnot

list-funding-one-shot:
	@echo "$(FUND_AMOUNT_ONE_SHOT)"

list-funding-repeatable:
	@echo "$(FUND_AMOUNT_REPEATABLE)"

build:
	docker build -t $(IMAGE) .

tests-one-shot: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		-e FUNDER_MNEMONIC \
		-e FUND_AMOUNT=$(FUND_AMOUNT_ONE_SHOT) \
		$(IMAGE) one-shot

tests-repeatable: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		-e FUNDER_MNEMONIC \
		-e FUND_AMOUNT=$(FUND_AMOUNT_REPEATABLE) \
		$(IMAGE) repeatable
