# Pinned, purpose-built CD agent image: kubectl + helm + git + curl only -
# no Docker, no BuildKit, nothing capable of building an image. This is a
# structural guarantee that the CD pipeline cannot rebuild what CI already
# built, not just a policy statement. curl stays installed (an earlier
# version removed it right after the kubectl/helm downloads to shrink the
# image) - Jenkinsfile-cd's own smoke test needs it to probe the app's ALB,
# confirmed live: the first real deploy actually succeeded end to end and
# still reported FAILURE purely because "curl: not found" in that stage.
FROM debian:12-slim

ARG KUBECTL_VERSION=v1.31.0
ARG HELM_VERSION=v3.15.4

# -f (--fail) on every download below is load-bearing, not stylistic: the
# original EKS-specific S3 URL for kubectl pointed at a build date that
# doesn't exist for this version, and a bare `curl -sSL` (no -f) silently
# saved the resulting S3 "NoSuchKey" XML error page AS the kubectl binary
# with exit code 0 - confirmed live, the CD pipeline's first real deploy got
# all the way to actually invoking that "kubectl" before failing with
# "exec format error" (it's XML, not an ELF binary). dl.k8s.io is the
# canonical, version-stable release URL - no build-date guessing.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl ca-certificates \
    && curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tar.gz \
    && tar -xzf /tmp/helm.tar.gz -C /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/helm.tar.gz /tmp/linux-amd64 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1000 jenkins \
    && useradd --system --uid 1000 --gid jenkins --create-home --home-dir /home/jenkins jenkins

USER jenkins
WORKDIR /home/jenkins
