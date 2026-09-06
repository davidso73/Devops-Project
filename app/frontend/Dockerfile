# Rebuilt into our own ECR repo (pinned digest, no Docker Hub rate-limit
# dependency at pod-start time) rather than pulling nginxinc's image directly
# at deploy time. Runs on 8080 as a non-root user out of the box - avoids the
# usual "nginx needs root to bind port 80" problem entirely.
FROM nginxinc/nginx-unprivileged:1.27-alpine

# The real reverse-proxy config is supplied at runtime via a ConfigMap
# (see K8s/helm/my-app/templates/configmap.yaml) mounted over this file -
# this default is only what a container run standalone (outside k8s) would see.
COPY default.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080
