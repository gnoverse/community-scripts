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

# 3 wallets — wallet 1 is both the runner (audit/e2e) and stress_1 (first RPC)
ENV STRESS_MNEMONIC_1="chair require about ask exhaust you already finger shop turn glory spare credit april rose sniff whale news economy birth table trim raccoon grit"
ENV STRESS_MNEMONIC_2="knock hat consider bicycle kit lion all cover lawn humble picnic win exit never message leader brother reform silk butter private protect tuition draw"
ENV STRESS_MNEMONIC_3="galaxy fire athlete egg three crane stone borrow thought cover story poem blush scissors pause slice unusual spread jewel visual tail parent bargain occur"

# runner = wallet 1
ENV RUNNER_MNEMONIC="${STRESS_MNEMONIC_1}"

ENTRYPOINT ["/bin/sh", "/tests/run_tests.sh"]
