FROM alpine:3 AS downloader

ARG TARGETARCH

ADD https://releases.hashicorp.com/terraform/1.16.5/terraform_1.16.5_linux_${TARGETARCH}.zip /tmp/terraform.zip
RUN unzip /tmp/terraform.zip -d /usr/local/bin && rm /tmp/terraform.zip

RUN rm /usr/local/bin/*.txt



FROM alpine:3

COPY --from=downloader --chmod=775 /usr/local/bin /usr/local/bin/

RUN apk add --no-cache \
    curl \
    ansible \
    openssh-client \
    python3 \
    py3-requests \
    py3-dateutil \
    bash \
    git \
    kubectl \
    jq \
    openssl
