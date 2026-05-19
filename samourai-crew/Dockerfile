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

# 3 wallets — wallet 1 is both the runner (audit/e2e) and stress_1 (first RPC)
# TODO: replace all values below with your actual mnemonics and addresses

ENV STRESS_MNEMONIC_1="chair require about ask exhaust you already finger shop turn glory spare credit april rose sniff whale news economy birth table trim raccoon grit"
ENV STRESS_ADDR_1="g1hzlg063fqrq4gltql992ssjc0xzau89t5jp63w"

ENV STRESS_MNEMONIC_2="knock hat consider bicycle kit lion all cover lawn humble picnic win exit never message leader brother reform silk butter private protect tuition draw"
ENV STRESS_ADDR_2="g174tsxfpf8zj8h3tyrz4ld690xvhcjnquls6ffc"

ENV STRESS_MNEMONIC_3="galaxy fire athlete egg three crane stone borrow thought cover story poem blush scissors pause slice unusual spread jewel visual tail parent bargain occur"
ENV STRESS_ADDR_3="g19xnaenyhe88emmge4726ta43lp3n237vvuzc2n"

# runner = wallet 1
ENV RUNNER_MNEMONIC="${STRESS_MNEMONIC_1}"
ENV RUNNER_ADDR="${STRESS_ADDR_1}"

ENTRYPOINT ["/bin/sh", "/tests/run_tests.sh"]
