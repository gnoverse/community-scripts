.PHONY: tests-one-shot tests-repeatable help

comma  := ,
REMOTES         ?=
REMOTE          ?= $(if $(REMOTES),$(firstword $(subst $(comma), ,$(REMOTES))),https://rpc.test-13-aeddi-1.gnoland.network)
CHAINID         ?= test-13
FUNDER_SCRIPT   ?= ./funders/gnoland.sh
FUNDER_MNEMONIC ?= source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast
GNOKEY_IMAGE    ?= ghcr.io/gnolang/gno/gnokey:master

export FUNDER_MNEMONIC

# Contributor subdirectories are detected automatically.
CONTRIB_DIRS := $(filter-out _%, $(patsubst %/Makefile,%,$(wildcard */Makefile)))

# Run the funder script inside a gnokey Docker container.
# No local gnokey installation required — compatible with GitHub Actions.
define run-funder
	docker run --rm \
		-e REMOTE=$(REMOTE) \
		-e CHAINID=$(CHAINID) \
		-e FUNDER_MNEMONIC \
		-v "$(CURDIR)/funders:/funders:ro" \
		--entrypoint /bin/sh \
		$(GNOKEY_IMAGE) \
		/funders/$(notdir $(FUNDER_SCRIPT)) $(1)
endef

## tests-one-shot   : fund accounts then run one-shot tests (REMOTES, CHAINID)
tests-one-shot:
	@for dir in $(CONTRIB_DIRS); do \
		echo ""; \
		echo "==> $$dir — funding (one-shot)"; \
		ARGS=$$($(MAKE) -C $$dir list-funding-one-shot --no-print-directory \
			REMOTE=$(REMOTE) REMOTES=$(REMOTES) CHAINID=$(CHAINID)); \
		if [ -n "$$ARGS" ]; then \
			$(call run-funder,$$ARGS) || exit 1; \
		fi; \
		echo "==> $$dir — tests (one-shot)"; \
		$(MAKE) -C $$dir tests-one-shot --no-print-directory \
			REMOTE=$(REMOTE) REMOTES=$(REMOTES) CHAINID=$(CHAINID) || exit 1; \
	done

## tests-repeatable : fund accounts then run repeatable tests (REMOTES, CHAINID)
tests-repeatable:
	@for dir in $(CONTRIB_DIRS); do \
		echo ""; \
		echo "==> $$dir — funding (repeatable)"; \
		ARGS=$$($(MAKE) -C $$dir list-funding-repeatable --no-print-directory \
			REMOTE=$(REMOTE) CHAINID=$(CHAINID)); \
		if [ -n "$$ARGS" ]; then \
			$(call run-funder,$$ARGS) || exit 1; \
		fi; \
		echo "==> $$dir — tests (repeatable)"; \
		$(MAKE) -C $$dir tests-repeatable --no-print-directory \
			REMOTE=$(REMOTE) CHAINID=$(CHAINID) || exit 1; \
	done

## help             : show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
