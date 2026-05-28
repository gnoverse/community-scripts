.PHONY: tests-one-shot tests-repeatable help

REMOTE        ?=
CHAINID       ?=
FUNDER_SCRIPT ?=

# Contributor subdirectories are detected automatically under tests/.
CONTRIB_DIRS := $(patsubst %/Makefile,%,$(wildcard tests/*/Makefile))

## tests-one-shot   : fund accounts then run one-shot tests (REMOTE, CHAINID, FUNDER_SCRIPT)
tests-one-shot:
	@for dir in $(CONTRIB_DIRS); do \
		echo ""; \
		echo "==> $$dir — funding (one-shot)"; \
		ARGS=$$($(MAKE) -C $$dir list-funding-one-shot --no-print-directory \
			REMOTE=$(REMOTE) CHAINID=$(CHAINID)); \
		if [ -n "$$ARGS" ]; then \
			REMOTE=$(REMOTE) CHAINID=$(CHAINID) $(FUNDER_SCRIPT) $$ARGS || exit 1; \
		fi; \
		echo "==> $$dir — tests (one-shot)"; \
		$(MAKE) -C $$dir tests-one-shot --no-print-directory \
			REMOTE=$(REMOTE) CHAINID=$(CHAINID) || exit 1; \
	done

## tests-repeatable : fund accounts then run repeatable tests (REMOTE, CHAINID, FUNDER_SCRIPT)
tests-repeatable:
	@for dir in $(CONTRIB_DIRS); do \
		echo ""; \
		echo "==> $$dir — funding (repeatable)"; \
		ARGS=$$($(MAKE) -C $$dir list-funding-repeatable --no-print-directory \
			REMOTE=$(REMOTE) CHAINID=$(CHAINID)); \
		if [ -n "$$ARGS" ]; then \
			REMOTE=$(REMOTE) CHAINID=$(CHAINID) $(FUNDER_SCRIPT) $$ARGS || exit 1; \
		fi; \
		echo "==> $$dir — tests (repeatable)"; \
		$(MAKE) -C $$dir tests-repeatable --no-print-directory \
			REMOTE=$(REMOTE) CHAINID=$(CHAINID) || exit 1; \
	done

## help             : show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
