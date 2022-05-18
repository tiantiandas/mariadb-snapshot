FROM debian:buster-slim as builder
RUN apt update \
    && apt install -yq --no-install-recommends ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*
RUN wget -q -d \
    -O- \
    --user-agent="Mozilla/5.0 (Windows NT x.y; rv:10.0) Gecko/20100101 Firefox/10.0" \
    http://www.quicklz.com/qpress-11-linux-x64.tar |\
    tar -x -C /srv/


FROM debian:buster-slim
LABEL maintainer="Zhe Gao<me@zhegao.me>"

RUN apt update \
    && apt install -yq --no-install-recommends mariadb-backup mariadb-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /etc/ca-certificates /etc/
COPY --from=builder /srv/qpress /usr/local/bin/
COPY snapshot.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
