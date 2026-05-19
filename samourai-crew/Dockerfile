FROM ghcr.io/gnolang/gno/gnokey:master

RUN apk add --no-cache bash jq

WORKDIR /tests

COPY audit/   audit/
COPY e2e/     e2e/
COPY stress/  stress/
COPY realms/  realms/
COPY run_tests.sh .

RUN chmod +x run_tests.sh \
    && find audit e2e stress -name "*.sh" -exec chmod +x {} +

ENV REMOTE=http://127.0.0.1:26657
ENV CHAINID=test
ENV FUND_AMOUNT=100000000ugnot
ENV FUND_AMOUNT_PER_WALLET=15000000ugnot
ENV REMOTES=

# TODO: replace with your runner mnemonic
ENV RUNNER_MNEMONIC="TODO_REPLACE_RUNNER_MNEMONIC"
ENV RUNNER_ADDR="TODO_REPLACE_RUNNER_ADDR"

# TODO: replace with your stress wallet mnemonics (one per validator RPC)
ENV STRESS_MNEMONIC_1="TODO_REPLACE_STRESS_MNEMONIC_1"
ENV STRESS_ADDR_1="TODO_REPLACE_STRESS_ADDR_1"

ENV STRESS_MNEMONIC_2="TODO_REPLACE_STRESS_MNEMONIC_2"
ENV STRESS_ADDR_2="TODO_REPLACE_STRESS_ADDR_2"

ENV STRESS_MNEMONIC_3="TODO_REPLACE_STRESS_MNEMONIC_3"
ENV STRESS_ADDR_3="TODO_REPLACE_STRESS_ADDR_3"

ENTRYPOINT ["/bin/sh", "/tests/run_tests.sh"]
