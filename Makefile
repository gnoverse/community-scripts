.PHONY: tests-one-shot tests-repeatable

REMOTE  ?= http://127.0.0.1:26657
CHAINID ?= test
FUNDER  ?= ./funders/test-13.sh

# Directories that expose the 4 required Makefile rules.
CONTRIBUTORS := $(wildcard */Makefile)
CONTRIB_DIRS := $(patsubst %/Makefile,%,$(CONTRIBUTORS))

tests-one-shot:
	@for dir in $(CONTRIB_DIRS); do \
		echo ""; \
		echo "==> $$dir — funding (one-shot)"; \
		ADDRS=$$($(MAKE) -C $$dir list-funding-one-shot --no-print-directory REMOTE=$(REMOTE) CHAINID=$(CHAINID)); \
		if [ -n "$$ADDRS" ]; then \
			REMOTE=$(REMOTE) CHAINID=$(CHAINID) $(FUNDER) $$ADDRS || exit 1; \
		fi; \
		echo "==> $$dir — tests (one-shot)"; \
		$(MAKE) -C $$dir tests-one-shot --no-print-directory REMOTE=$(REMOTE) CHAINID=$(CHAINID) || exit 1; \
	done

tests-repeatable:
	@for dir in $(CONTRIB_DIRS); do \
		echo ""; \
		echo "==> $$dir — funding (repeatable)"; \
		ADDRS=$$($(MAKE) -C $$dir list-funding-repeatable --no-print-directory REMOTE=$(REMOTE) CHAINID=$(CHAINID)); \
		if [ -n "$$ADDRS" ]; then \
			REMOTE=$(REMOTE) CHAINID=$(CHAINID) $(FUNDER) $$ADDRS || exit 1; \
		fi; \
		echo "==> $$dir — tests (repeatable)"; \
		$(MAKE) -C $$dir tests-repeatable --no-print-directory REMOTE=$(REMOTE) CHAINID=$(CHAINID) || exit 1; \
	done
