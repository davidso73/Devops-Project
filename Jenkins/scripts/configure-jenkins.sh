#!/bin/bash
# Re-applies JCasC config (security realm, cloud/agent templates, jobs) to
# an already-running controller without needing a full pod restart. This
# does NOT install/update plugins - a plugins.txt change needs
# install-jenkins.sh (which does a `helm upgrade`, re-running the chart's
# plugin-installer init container and restarting the pod). Run
# install-jenkins.sh first if Jenkins isn't installed yet.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JENKINS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "== Rebuilding the JCasC ConfigMap from current files =="
# Must carry the jenkins-jenkins-config=true label - the chart's config-reload
# sidecar only syncs ConfigMaps that have it (see install-jenkins.sh comment).
# render-jcasc.py inlines the `!include` references (see that script and
# install-jenkins.sh for why `!include` itself doesn't work here).
RENDERED_JCASC=$(mktemp)
python3 "$SCRIPT_DIR/render-jcasc.py" "$JENKINS_DIR/jcasc/jenkins.yaml" > "$RENDERED_JCASC"
kubectl create configmap jenkins-casc-config -n jenkins \
    --from-file=jenkins.yaml="$RENDERED_JCASC" \
    --dry-run=client -o yaml | kubectl label -f - --local -o yaml jenkins-jenkins-config=true | kubectl apply -f -
rm -f "$RENDERED_JCASC"

echo "== Port-forwarding to the controller =="
kubectl port-forward svc/jenkins 8080:8080 -n jenkins >/tmp/pf.log 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 5

ADMIN_USER=$(kubectl get secret jenkins-admin-secret -n jenkins -o jsonpath='{.data.JENKINS_ADMIN_USER}' | base64 -d)
ADMIN_PASSWORD=$(kubectl get secret jenkins-admin-secret -n jenkins -o jsonpath='{.data.JENKINS_ADMIN_PASSWORD}' | base64 -d)

curl -sS -o /tmp/jenkins-cli.jar http://localhost:8080/jnlpJars/jenkins-cli.jar

echo "== Reloading JCasC configuration =="
java -jar /tmp/jenkins-cli.jar -s http://localhost:8080/ -auth "$ADMIN_USER:$ADMIN_PASSWORD" reload-jcasc-configuration

echo "Configuration reloaded."
