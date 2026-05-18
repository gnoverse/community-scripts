.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build

REMOTE  ?= http://127.0.0.1:26657
CHAINID ?= test
IMAGE   := samourai-crew-tests

# Funding is handled internally: run_tests.sh generates a fresh account
# and funds it from test1 at startup. Nothing to list here.
list-funding-one-shot:
	@true

list-funding-repeatable:
	@true

build:
	docker build -t $(IMAGE) .

tests-one-shot: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		-e FUNDER_MNEMONIC \
		$(IMAGE) one-shot

tests-repeatable: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		-e FUNDER_MNEMONIC \
		$(IMAGE) repeatable
