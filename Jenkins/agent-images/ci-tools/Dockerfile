# Pinned, purpose-built CI agent image: git for checkout, curl for the smoke
# test/ECR calls, flake8 for lint, pytest for the app's test suite - nothing
# else. Runs as a fixed non-root UID by design (not via a runtime `apt-get`
# under a non-root user, which wouldn't have permission to install anything).
FROM python:3.11-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir flake8==7.1.1 pytest==8.3.3 awscli==1.36.7 \
    && groupadd --system --gid 1000 jenkins \
    && useradd --system --uid 1000 --gid jenkins --create-home --home-dir /home/jenkins jenkins

USER jenkins
WORKDIR /home/jenkins
