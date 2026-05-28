.PHONY: list-funding-one-shot list-funding-repeatable tests-one-shot tests-repeatable help

REMOTE ?=
CHAINID ?=

## list-funding-one-shot   : print address/amount pairs to fund before one-shot tests
list-funding-one-shot:
	@# Example: @echo "g1_addr1 30000000ugnot g1_addr2 10000000ugnot"
	@echo "not implemented" >&2 && exit 1

## list-funding-repeatable : print address/amount pairs to fund before repeatable tests
list-funding-repeatable:
	@# Example: @echo "g1_addr1 10000000ugnot"
	@echo "not implemented" >&2 && exit 1

## tests-one-shot          : run one-shot tests (REMOTE, CHAINID)
tests-one-shot:
	@# Run one-shot tests (only bash and Docker allowed as deps) or no-op if none exist.
	@echo "not implemented" >&2 && exit 1

## tests-repeatable        : run repeatable tests (REMOTE, CHAINID)
tests-repeatable:
	@# Run repeatable tests (only bash and Docker allowed as deps) or no-op if none exist.
	@echo "not implemented" >&2 && exit 1

## help                    : show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
