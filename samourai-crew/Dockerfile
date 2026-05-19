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
ENV FUND_AMOUNT=50000000ugnot
ENV FUND_AMOUNT_PER_WALLET=15000000ugnot
ENV REMOTES=

ENTRYPOINT ["/bin/sh", "/tests/run_tests.sh"]
