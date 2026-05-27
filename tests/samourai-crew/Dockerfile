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

ENV REMOTES=http://127.0.0.1:26657
ENV CHAINID=test

# Mnemonics are injected at runtime via docker run -e (see tests/samourai-crew/Makefile)
ENV STRESS_MNEMONIC_1=""
ENV STRESS_MNEMONIC_2=""
ENV STRESS_MNEMONIC_3=""
ENV RUNNER_MNEMONIC=""

ENTRYPOINT ["/bin/sh", "/tests/run_tests.sh"]
