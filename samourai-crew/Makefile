.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable build

REMOTE  ?= http://127.0.0.1:26657
CHAINID ?= test
IMAGE   := samourai-crew-tests

list-funding-one-shot:
	@echo "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"

list-funding-repeatable:
	@echo "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"

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
