.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build

REMOTE  ?= http://127.0.0.1:26657
CHAINID ?= test
IMAGE   := samourai-crew-tests

# Declare the test account address and the funding amount needed per run.
# The root Makefile passes these to the funder script before running tests.
list-funding-one-shot:
	@echo "g1hvl0529gtj4fgtsuaurg4hcruuya2l9nuh04uj 100000000ugnot"

list-funding-repeatable:
	@echo "g1hvl0529gtj4fgtsuaurg4hcruuya2l9nuh04uj 10000000ugnot"

build:
	docker build -t $(IMAGE) .

tests-one-shot: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		$(IMAGE) one-shot

tests-repeatable: build
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		$(IMAGE) repeatable
