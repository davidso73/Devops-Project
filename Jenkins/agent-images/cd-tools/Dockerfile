# Pinned, purpose-built CD agent image: kubectl + helm + git only - no
# Docker, no BuildKit, nothing capable of building an image. This is a
# structural guarantee that the CD pipeline cannot rebuild what CI already
# built, not just a policy statement.
FROM debian:12-slim

ARG KUBECTL_VERSION=v1.31.0
ARG HELM_VERSION=v3.15.4

RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl ca-certificates \
    && curl -sSL -o /usr/local/bin/kubectl "https://s3.us-west-2.amazonaws.com/amazon-eks/${KUBECTL_VERSION}/2024-09-12/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && curl -sSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tar.gz \
    && tar -xzf /tmp/helm.tar.gz -C /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/helm.tar.gz /tmp/linux-amd64 \
    && apt-get remove -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1000 jenkins \
    && useradd --system --uid 1000 --gid jenkins --create-home --home-dir /home/jenkins jenkins

USER jenkins
WORKDIR /home/jenkins
