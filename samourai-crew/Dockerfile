FROM ghcr.io/gnolang/gno/gnokey:master

WORKDIR /tests

COPY audit/ audit/
COPY e2e/   e2e/
COPY run_tests.sh .

RUN chmod +x run_tests.sh \
    && find audit e2e -name "*.sh" -exec chmod +x {} +

ENV REMOTE=http://127.0.0.1:26657
ENV CHAINID=test

ENTRYPOINT ["/bin/sh", "/tests/run_tests.sh"]
