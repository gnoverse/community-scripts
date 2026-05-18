.PHONY: tests-one-shot tests-repeatable

REMOTE          ?= https://rpc.test12.testnets.gno.land
CHAINID         ?= test12
FUNDER_MNEMONIC ?= source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast

export FUNDER_MNEMONIC

# Contributor subdirectories are detected automatically.
CONTRIB_DIRS := $(filter-out _%, $(patsubst %/Makefile,%,$(wildcard */Makefile)))

tests-one-shot:
	@for dir in $(CONTRIB_DIRS); do \
		echo ""; \
		echo "==> $$dir — tests (one-shot)"; \
		$(MAKE) -C $$dir tests-one-shot --no-print-directory \
			REMOTE=$(REMOTE) CHAINID=$(CHAINID) || exit 1; \
	done

tests-repeatable:
	@for dir in $(CONTRIB_DIRS); do \
		echo ""; \
		echo "==> $$dir — tests (repeatable)"; \
		$(MAKE) -C $$dir tests-repeatable --no-print-directory \
			REMOTE=$(REMOTE) CHAINID=$(CHAINID) || exit 1; \
	done
