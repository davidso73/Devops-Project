#!/bin/bash
# Full teardown of the Jenkins install. Does NOT touch devops-app, RDS, S3,
# SQS, SNS, or the EKS cluster itself - only what this folder created.
set -uo pipefail

echo "== Uninstalling the Helm release =="
helm uninstall jenkins -n jenkins

echo "== Deleting RBAC, Ingress, NetworkPolicy, ConfigMaps, Secret =="
kubectl delete -f "$(dirname "$0")/../rbac/" --ignore-not-found
kubectl delete ingress jenkins-ingress -n jenkins --ignore-not-found
kubectl delete -f "$(dirname "$0")/../network-policy.yaml" --ignore-not-found
kubectl delete configmap jenkins-casc-config jenkins-plugins-txt -n jenkins --ignore-not-found
kubectl delete secret jenkins-admin-secret -n jenkins --ignore-not-found

echo "== Deleting the PVC (StorageClass has reclaimPolicy: Retain, so the"
echo "   underlying EBS volume survives this - delete it manually in the"
echo "   AWS console/CLI if you also want the JENKINS_HOME data gone) =="
kubectl delete pvc --all -n jenkins --ignore-not-found

echo "== Deleting the namespace =="
kubectl delete -f "$(dirname "$0")/../namespace.yaml" --ignore-not-found

echo "== Leaving the jenkins-alb-sg security group and StorageClass in place"
echo "   (cheap to keep, and needed again on the next install-jenkins.sh run)."
echo "   Delete manually with: aws ec2 delete-security-group --group-name jenkins-alb-sg"

echo "Uninstall complete."
