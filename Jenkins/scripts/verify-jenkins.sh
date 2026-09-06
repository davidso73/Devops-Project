#!/bin/bash
# Runs the exact checks used for Jenkins/evidence.md. Safe to run any time
# after install-jenkins.sh + create-jobs.sh.
set -uo pipefail

echo "=== kubectl get namespaces ==="
kubectl get namespaces

echo ""
echo "=== kubectl get pods -n jenkins -o wide ==="
kubectl get pods -n jenkins -o wide

echo ""
echo "=== kubectl get service,ingress,pvc -n jenkins ==="
kubectl get service,ingress,pvc -n jenkins

echo ""
echo "=== kubectl get serviceaccount,role,rolebinding -n jenkins ==="
kubectl get serviceaccount,role,rolebinding -n jenkins

echo ""
echo "=== helm list -n jenkins ==="
helm list -n jenkins

echo ""
echo "=== Controller ready? ==="
kubectl get pods -n jenkins -l app.kubernetes.io/component=jenkins-controller

echo ""
echo "=== Any agent pods currently running (expected: none at rest) ==="
kubectl get pods -n jenkins -l 'role in (ci-agent,cd-agent)' 2>&1

echo ""
echo "Done. See README 'Pipeline CI' / 'Pipeline CD' sections for the"
echo "build-triggered evidence (agent pod lifecycle, image tags/digests,"
echo "rollout status, smoke test) - those are captured while a real build"
echo "is running, not by this static check."
