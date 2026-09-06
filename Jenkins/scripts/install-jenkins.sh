#!/bin/bash
# Installs Jenkins into the vmapp-eks cluster from code, with nothing
# manual required: namespace, RBAC, storage, security group, secrets
# (auto-generated if missing), config-as-code, and the Helm chart itself.
#
# Run from a host with kubectl + helm + aws CLI already pointed at the
# cluster (see README "Prerequisites") - e.g. the build host used
# throughout this project. Idempotent: safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JENKINS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$JENKINS_DIR/.." && pwd)"

CHART_VERSION="5.9.56"
AWS_REGION="il-central-1"
VPC_ID="vpc-078790f7a168052e8"
ALLOWLIST_IP="79.177.139.162/32"   # residential IP for interactive UI access -
                                     # rotates periodically; re-run this script
                                     # (or a single `aws ec2 authorize-security-group-ingress`)
                                     # with the current IP if the UI becomes unreachable

echo "== 1. Namespace =="
kubectl apply -f "$JENKINS_DIR/namespace.yaml"

echo "== 2. RBAC =="
kubectl apply -f "$JENKINS_DIR/rbac/jenkins-controller-rbac.yaml"
kubectl apply -f "$JENKINS_DIR/rbac/ci-agent-rbac.yaml"
kubectl apply -f "$JENKINS_DIR/rbac/cd-agent-rbac.yaml"

echo "== 3. StorageClass =="
kubectl apply -f "$JENKINS_DIR/storageclass.yaml"

echo "== 4. Admin/webhook secret (auto-generated if this is a clean install) =="
SECRET_FILE="$JENKINS_DIR/credentials/secret.yaml"   # real file, gitignored - never committed
if [ ! -f "$SECRET_FILE" ]; then
    echo "No existing secret.yaml found - generating one."
    ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)
    WEBHOOK_SECRET=$(openssl rand -base64 32 | tr -d '=+/' | head -c 32)
    cat > "$SECRET_FILE" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-admin-secret
  namespace: jenkins
type: Opaque
stringData:
  JENKINS_ADMIN_USER: "admin"
  JENKINS_ADMIN_PASSWORD: "${ADMIN_PASSWORD}"
  GITHUB_WEBHOOK_SECRET: "${WEBHOOK_SECRET}"
EOF
    echo ""
    echo "############################################################"
    echo "# Generated Jenkins admin credentials (shown once - also in #"
    echo "# $SECRET_FILE, which is gitignored):                       "
    echo "#   user:     admin"
    echo "#   password: ${ADMIN_PASSWORD}"
    echo "############################################################"
    echo ""
fi
kubectl apply -f "$SECRET_FILE"

echo "== 5. JCasC ConfigMap (rebuilt fresh every run, so edits to jcasc/*, =="
echo "==    agent-pods/*, jobs/* always take effect)                     =="
# The chart's config-reload sidecar (kiwigrid/k8s-sidecar) syncs ConfigMaps
# into /var/jenkins_home/casc_configs by LABEL, not by name - it only picks
# up ConfigMaps carrying the exact label key it was told to watch for
# (chart-generated as "<release>-<chart>-config", i.e. "jenkins-jenkins-config"
# for this release), value "true". Without this label the sidecar's LIST
# query matches nothing and the sync folder stays empty.
#
# render-jcasc.py inlines the `!include` references into a single flat
# jenkins.yaml - the plugin versions resolved for this project reject the
# `!include` custom tag outright (see that script's header comment) - so the
# ConfigMap ends up with exactly one .yaml file, avoiding JCasC's directory
# scan also independently (and incorrectly) trying to parse the raw
# Kubernetes pod-template files as their own top-level config documents.
RENDERED_JCASC=$(mktemp)
python3 "$SCRIPT_DIR/render-jcasc.py" "$JENKINS_DIR/jcasc/jenkins.yaml" > "$RENDERED_JCASC"
kubectl create configmap jenkins-casc-config -n jenkins \
    --from-file=jenkins.yaml="$RENDERED_JCASC" \
    --dry-run=client -o yaml | kubectl label -f - --local -o yaml jenkins-jenkins-config=true | kubectl apply -f -
rm -f "$RENDERED_JCASC"

echo "== 6. Restricted security group for the Jenkins ALB =="
SG_NAME="jenkins-alb-sg"
if [ -n "${JENKINS_ALB_SG_ID:-}" ]; then
    # The runner's IAM role (e.g. the build host, deliberately minimal - see
    # buildhost.tf) may not have ec2:CreateSecurityGroup/DescribeSecurityGroups.
    # In that case, create/refresh the SG once from a role that does have EC2
    # permissions (see README "Network and exposure" for the exact commands),
    # then pass its ID here to skip the AWS calls below entirely.
    SG_ID="$JENKINS_ALB_SG_ID"
    echo "Using pre-created security group $SG_ID (JENKINS_ALB_SG_ID set)"
else
    SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
        --region "$AWS_REGION" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "None")
    if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
        SG_ID=$(aws ec2 create-security-group --group-name "$SG_NAME" \
            --description "Jenkins ALB - GitHub webhook ranges + allow-listed UI access only" \
            --vpc-id "$VPC_ID" --region "$AWS_REGION" --query "GroupId" --output text)
        echo "Created $SG_ID"
    else
        echo "Reusing existing $SG_ID"
    fi

    # GitHub's published webhook source ranges (IPv4 only - the ALB has no IPv6
    # listener) plus the one allow-listed IP for interactive UI access. Re-fetched
    # every run so this stays current as GitHub's ranges change over time.
    GITHUB_HOOK_CIDRS=$(curl -sS https://api.github.com/meta | python3 -c "
import json, sys
data = json.load(sys.stdin)
for cidr in data.get('hooks', []):
    if ':' not in cidr:
        print(cidr)
" | tr -d '\r')

    for CIDR in $GITHUB_HOOK_CIDRS "$ALLOWLIST_IP"; do
        aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 \
            --cidr "$CIDR" --region "$AWS_REGION" >/dev/null 2>&1 || true   # ok if the rule already exists
    done
    echo "Security group $SG_ID allows port 80 from: $GITHUB_HOOK_CIDRS $ALLOWLIST_IP"
fi

sed "s/SECURITY_GROUP_ID_PLACEHOLDER/$SG_ID/" "$JENKINS_DIR/ingress.yaml" | kubectl apply -f -

# Setting a custom `security-groups` annotation on the Ingress replaces the
# ALB's security groups entirely, which drops the AWS Load Balancer
# Controller's own auto-managed "shared backend" SG that it would otherwise
# attach to let the ALB reach pods on their target port. Without this rule
# the ALB's target-group health check times out (Target.Timeout) and the
# ALB never becomes reachable at all, from GitHub or anyone else. Same
# minimal-IAM-role workaround as the ALB SG itself above (NODE_SG_ID).
NODE_SG_NAME="eks-cluster-sg-vmapp-eks"
if [ -n "${JENKINS_NODE_SG_ID:-}" ]; then
    NODE_SG_ID="$JENKINS_NODE_SG_ID"
else
    NODE_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${NODE_SG_NAME}*" "Name=vpc-id,Values=$VPC_ID" \
        --region "$AWS_REGION" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "None")
fi
if [ "$NODE_SG_ID" != "None" ] && [ -n "$NODE_SG_ID" ]; then
    aws ec2 authorize-security-group-ingress --group-id "$NODE_SG_ID" --protocol tcp --port 8080 \
        --source-group "$SG_ID" --region "$AWS_REGION" >/dev/null 2>&1 || true   # ok if it already exists
    echo "Node security group $NODE_SG_ID allows port 8080 from ALB security group $SG_ID"
else
    echo "WARNING: could not resolve the node security group - add manually:"
    echo "  aws ec2 authorize-security-group-ingress --group-id <node-sg> --protocol tcp --port 8080 --source-group $SG_ID"
fi

echo "== 7. NetworkPolicy =="
kubectl apply -f "$JENKINS_DIR/network-policy.yaml"

echo "== 8. Generating controller.installPlugins from plugins.txt (single source of truth) =="
PLUGINS_VALUES_FILE=$(mktemp)
{
    echo "controller:"
    echo "  installPlugins:"
    grep -v '^#' "$JENKINS_DIR/plugins.txt" | grep -v '^[[:space:]]*$' | while read -r line; do
        echo "    - \"$line\""
    done
} > "$PLUGINS_VALUES_FILE"

echo "== 9. Helm chart (pinned: jenkins/jenkins v$CHART_VERSION, image 2.541.3-lts-jdk17) =="
helm repo add jenkins https://charts.jenkins.io >/dev/null
helm repo update >/dev/null
helm upgrade --install jenkins jenkins/jenkins \
    --version "$CHART_VERSION" \
    --namespace jenkins \
    -f "$JENKINS_DIR/helm-values.yaml" \
    -f "$PLUGINS_VALUES_FILE" \
    --wait --timeout 10m
rm -f "$PLUGINS_VALUES_FILE"

echo ""
echo "Install complete. Run scripts/verify-jenkins.sh to check status, then"
echo "scripts/create-jobs.sh once the controller is Ready."
