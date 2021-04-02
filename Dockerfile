FROM ubuntu:20.04 as builder

WORKDIR /

RUN apt-get update && \
    apt-get install -y \
    curl \
    unzip \
    build-essential \
    autoconf \
    libgnutls28-dev \
    libgnutls28-dev \
    liblzo2-dev \
    libpam0g-dev \
    libtool \
    libssl-dev \
    net-tools

RUN curl -L https://github.com/OpenVPN/openvpn/archive/v2.4.9.zip -o openvpn.zip && \
    unzip openvpn.zip

COPY openvpn-v2.4.9-aws.patch openvpn-2.4.9

RUN cd openvpn-2.4.9 && \
    patch -p1 < openvpn-v2.4.9-aws.patch && \
    autoreconf -i -v -f && \
    ./configure && \
    make

RUN curl -L https://golang.org/dl/go1.15.4.linux-amd64.tar.gz -o go.tar.gz && \
    tar -C /usr/local -xzf go.tar.gz

ENV PATH=$PATH:/usr/local/go/bin

COPY server.go .

RUN go build server.go

FROM ubuntu:20.04

ENV TZ="America/Sao_Paulo"
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update && \
    apt-get install -y \
    dnsutils \
    liblzo2-dev \
    openssl \
    net-tools \
    python

COPY --from=builder /openvpn-2.4.9/src/openvpn/openvpn /openvpn
COPY --from=builder /server /server
COPY entrypoint.sh /
COPY patch-vpn-config.py /

COPY update-resolv-conf /etc/openvpn/scripts/

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
