#!/bin/bash
# Creates (or idempotently updates) application-ci and application-cd via
# the Jenkins CLI, running the exact same Job DSL script JCasC already runs
# automatically at controller boot (jobs/seed-job.groovy) - this is the
# "Jenkins CLI/API script... for creating the two jobs" path, useful to
# re-run any time without restarting the controller. Safe to run repeatedly:
# Job DSL updates existing jobs in place rather than erroring.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JENKINS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

kubectl port-forward svc/jenkins 8080:8080 -n jenkins >/tmp/pf.log 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 5

ADMIN_USER=$(kubectl get secret jenkins-admin-secret -n jenkins -o jsonpath='{.data.JENKINS_ADMIN_USER}' | base64 -d)
ADMIN_PASSWORD=$(kubectl get secret jenkins-admin-secret -n jenkins -o jsonpath='{.data.JENKINS_ADMIN_PASSWORD}' | base64 -d)

curl -sS -o /tmp/jenkins-cli.jar http://localhost:8080/jnlpJars/jenkins-cli.jar

# The Job DSL script content is inlined directly into the wrapper's stdin -
# `groovy =` executes on the controller, which has no access to this
# machine's filesystem, so the script text has to travel over the same pipe.
echo "== Running Job DSL via Jenkins CLI (idempotent) =="
{
cat <<'WRAPPER_HEAD'
import javaposse.jobdsl.dsl.DslScriptLoader
import javaposse.jobdsl.plugin.JenkinsJobManagement

def dslScript = '''
WRAPPER_HEAD
cat "$JENKINS_DIR/jobs/seed-job.groovy"
cat <<'WRAPPER_TAIL'
'''
def jobManagement = new JenkinsJobManagement(System.out, [:], new File('.'))
new DslScriptLoader(jobManagement).runScript(dslScript)
println "Job DSL applied."
WRAPPER_TAIL
} | java -jar /tmp/jenkins-cli.jar -s http://localhost:8080/ -auth "$ADMIN_USER:$ADMIN_PASSWORD" groovy =

echo "== Jobs present: =="
java -jar /tmp/jenkins-cli.jar -s http://localhost:8080/ -auth "$ADMIN_USER:$ADMIN_PASSWORD" list-jobs
