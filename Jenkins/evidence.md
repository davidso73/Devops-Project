# Jenkins CI/CD - Evidence

All commands run against the live `vmapp-eks` cluster from the build host
(`51.84.243.252`), captured 2026-09-06. See the root `README.md` "Jenkins
CI/CD" section for the full architecture, install/configure/verify
instructions, and security write-up - this file is the raw proof that it
actually runs.

## 1. Static state (`scripts/verify-jenkins.sh`)

```
=== kubectl get namespaces ===
NAME              STATUS   AGE
default           Active   7h34m
devops-app        Active   6h19m
jenkins           Active   3h30m
kube-node-lease   Active   7h34m
kube-public       Active   7h34m
kube-system       Active   7h34m

=== kubectl get pods -n jenkins -o wide ===
NAME        READY   STATUS    RESTARTS   AGE    IP            NODE                                           NOMINATED NODE   READINESS GATES
jenkins-0   2/2     Running   0          146m   10.0.57.229   ip-10-0-60-182.il-central-1.compute.internal   <none>           <none>

=== kubectl get service,ingress,pvc -n jenkins ===
NAME                    TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)     AGE
service/jenkins         ClusterIP   172.20.201.246   <none>        8080/TCP    146m
service/jenkins-agent   ClusterIP   172.20.52.90     <none>        50000/TCP   146m

NAME                                        CLASS    HOSTS   ADDRESS                                                              PORTS   AGE
ingress.networking.k8s.io/jenkins-ingress   <none>   *       k8s-jenkinsalb-548b518b15-496779108.il-central-1.elb.amazonaws.com   80      3h25m

NAME                            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/jenkins   Bound    pvc-1e6c5e25-6416-4b4f-b03a-f25dfe738afa   10Gi       RWO            gp3-jenkins    <unset>                 146m

=== kubectl get serviceaccount,role,rolebinding -n jenkins ===
NAME                                AGE
serviceaccount/default              3h30m
serviceaccount/jenkins-cd-agent     3h30m
serviceaccount/jenkins-ci-agent     3h30m
serviceaccount/jenkins-controller   3h30m

NAME                                                     CREATED AT
role.rbac.authorization.k8s.io/jenkins-casc-reload       2026-09-06T05:50:43Z
role.rbac.authorization.k8s.io/jenkins-controller-role   2026-09-06T04:46:49Z
role.rbac.authorization.k8s.io/jenkins-schedule-agents   2026-09-06T05:50:43Z

NAME                                                                   ROLE                           AGE
rolebinding.rbac.authorization.k8s.io/jenkins-controller-rolebinding   Role/jenkins-controller-role   3h30m
rolebinding.rbac.authorization.k8s.io/jenkins-schedule-agents          Role/jenkins-schedule-agents   146m
rolebinding.rbac.authorization.k8s.io/jenkins-watch-configmaps         Role/jenkins-casc-reload       146m

=== helm list -n jenkins ===
NAME   	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART         	APP VERSION
jenkins	jenkins  	1       	2026-09-06 05:50:43.260590819 +0000 UTC	deployed	jenkins-5.9.56	2.568.3

=== Controller ready? ===
NAME        READY   STATUS    RESTARTS   AGE
jenkins-0   2/2     Running   0          146m

=== Any agent pods currently running (expected: none at rest) ===
No resources found in jenkins namespace.
```

`jenkins-0` is `2/2 Ready` with **0 restarts** across the whole session
(clean `install-jenkins.sh` run, no crash-loops). `numExecutors: 0` in JCasC
means the controller itself is structurally unable to run a build - every
build below ran on a dynamic agent pod, never here.

## 2. Jobs created entirely from committed code

`application-ci` and `application-cd` were created by JCasC's `jobs:` block
(`jcasc/jenkins.yaml` -> `jobs/seed-job.groovy`, applied automatically at
controller boot/reload - no manual UI clicking), with `scripts/create-jobs.sh`
(Jenkins CLI, same underlying script) as an idempotent, independently
re-runnable path to the same result:

```
$ curl -u admin:*** http://localhost:8080/api/json | jq '.jobs[].name'
"application-cd"
"application-ci"
```

## 3. Live CI evidence (build #18, webhook-triggered)

Real push -> webhook delivery -> Jenkins build, no manual trigger:

```
$ gh api repos/davidso73/Devops-Project/hooks/675211939/deliveries --jq '.[0]'
{"event":"push","status":"OK","status_code":200}
```

Build console (`application-ci` #18):

```
Started by GitHub push by davidso73
...
Commit:      fc74b1591319caaf19c9fe6f3886de0cdf085a52
Branch:      origin/main
Build:       #18
Image tag:   fc74b1591319
...
tests/test_app.py::test_architectures_and_instance_types_are_stable PASSED [ 25%]
tests/test_app.py::test_login_page_loads PASSED                          [ 50%]
tests/test_app.py::test_register_page_loads PASSED                       [ 75%]
tests/test_app.py::test_index_requires_login PASSED                      [100%]
============================== 4 passed in 0.72s ===============================
...
=== Building app/frontend -> 832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-frontend:fc74b1591319 ===
#7 pushing manifest for .../vmapp-frontend:fc74b1591319@sha256:941ff70f55de80cbc89b50d83c23bd2cdf73a09a43e47bfad98a1851ada4133e
=== Building app/backend -> 832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-backend:fc74b1591319 ===
#11 pushing manifest for .../vmapp-backend:fc74b1591319@sha256:5cd928a5a0e31605eceecabe901f6c5b3ed3128caa5a2601dc964e078af4698d
=== Building app/worker -> 832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-worker:fc74b1591319 ===
#11 pushing manifest for .../vmapp-worker:fc74b1591319@sha256:914e57750d1b9ed133c14118ea25042a8de74881d2b907d143617113c3e1f58f
```

Single, monovalent commit-SHA tag (`fc74b1591319`) across all 3 services -
`latest` is never produced. ECR scan results, confirmed complete for the
exact digests above:

```
$ aws ecr describe-image-scan-findings --repository-name vmapp-frontend --image-id imageTag=fc74b1591319 --query imageScanStatus
{"status": "COMPLETE", "description": "The scan was completed successfully."}
$ aws ecr describe-image-scan-findings --repository-name vmapp-backend --image-id imageTag=fc74b1591319 --query imageScanStatus
{"status": "COMPLETE", "description": "The scan was completed successfully."}
$ aws ecr describe-image-scan-findings --repository-name vmapp-worker --image-id imageTag=fc74b1591319 --query imageScanStatus
{"status": "COMPLETE", "description": "The scan was completed successfully."}
```

Agent pod lifecycle during this build (created for the build, gone
immediately after - `podRetention: never`):

```
$ kubectl get pods -n jenkins
NAME             READY   STATUS    RESTARTS   AGE
ci-agent-87178   3/3     Running   0          70s
jenkins-0        2/2     Running   0          117m
...
(after the build finished)
$ kubectl get pods -n jenkins
NAME        READY   STATUS    RESTARTS   AGE
jenkins-0   2/2     Running   0          124m
```

No build ever ran on the controller: `jenkins-0`'s own pod never changes
status during a build (still `2/2 Running`, 0 restarts throughout this
entire session) - all work above happened inside the ephemeral `ci-agent-*`
pod, under the `jenkins-ci-agent` ServiceAccount (IRSA-bound to ECR push
only, no Kubernetes RBAC at all).

## 4. Deliberately failed test - CI fails, CD never invoked

`app/backend/tests/test_app.py::test_login_page_loads` was changed to
assert an impossible status code, committed, and pushed (commit `fb03a90`):

```
tests/test_app.py::test_architectures_and_instance_types_are_stable PASSED [ 25%]
tests/test_app.py::test_login_page_loads FAILED                          [ 50%]
tests/test_app.py::test_register_page_loads PASSED                       [ 75%]
tests/test_app.py::test_index_requires_login PASSED                      [100%]

=================================== FAILURES ===================================
____________________________ test_login_page_loads _____________________________
    def test_login_page_loads(client):
        resp = client.get("/login")
>       assert resp.status_code == 999  # deliberately wrong - CI failure-mode evidence
E       assert 200 == 999
FAILED tests/test_app.py::test_login_page_loads - assert 200 == 999
========================= 1 failed, 3 passed in 0.81s ==========================
...
Stage "Determine changed services" skipped due to earlier failure(s)
```

`application-ci` build #16: **FAILURE**. No image was built or pushed (the
Build stage never ran). Confirmed CD was never triggered - `application-cd`'s
last build was still #4 (from before this push), unchanged:

```
$ curl -u admin:*** http://localhost:8080/job/application-cd/lastBuild/api/json
{"number": 4, "result": "SUCCESS", ...}
```

The test was reverted in the very next commit (`75d7651`) and confirmed
passing again in build #17.

## 5. Live CD evidence (build #6, auto-triggered by CI #18)

```
$ kubectl get deployments,pods,services,ingress -n devops-app
NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/vmapp-backend    2/2     2            2           6h19m
deployment.apps/vmapp-frontend   2/2     2            2           6h19m
deployment.apps/vmapp-worker     1/1     1            1           6h19m

NAME                                  READY   STATUS    RESTARTS   AGE
pod/vmapp-backend-74449b9fd8-75qxc    1/1     Running   0          4m14s
pod/vmapp-backend-74449b9fd8-vfgbd    1/1     Running   0          4m27s
pod/vmapp-frontend-6dfb7b5d99-fnmgg   1/1     Running   0          4m3s
pod/vmapp-frontend-6dfb7b5d99-xgvrf   1/1     Running   0          4m27s
pod/vmapp-worker-67b447c655-k5xqc     1/1     Running   0          4m27s

NAME                     TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
service/vmapp-backend    ClusterIP   172.20.51.12     <none>        8000/TCP   6h19m
service/vmapp-frontend   ClusterIP   172.20.220.161   <none>        80/TCP     6h19m

NAME                                      CLASS    HOSTS   ADDRESS                                                            PORTS   AGE
ingress.networking.k8s.io/vmapp-ingress   <none>   *       k8s-vmappalb-6536a7fd42-358218343.il-central-1.elb.amazonaws.com   80      6h19m

$ kubectl rollout status deployment/vmapp-frontend -n devops-app
deployment "vmapp-frontend" successfully rolled out
$ kubectl rollout status deployment/vmapp-backend -n devops-app
deployment "vmapp-backend" successfully rolled out
$ kubectl rollout status deployment/vmapp-worker -n devops-app
deployment "vmapp-worker" successfully rolled out

$ kubectl get pods -n devops-app -o jsonpath='{..image}' | tr ' ' '\n' | sort -u
832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-backend:fc74b1591319
832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-frontend:fc74b1591319
832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-worker:fc74b1591319
```

Every running pod's image tag matches exactly the tag CI build #18 built and
pushed (`fc74b1591319`) - the image CD deployed is the exact image CI built,
never rebuilt. CD's own console confirms it never invoked BuildKit or
`buildctl` anywhere - only `helm`/`kubectl` (the `cd-tools` image is
structurally incapable of building an image at all - no BuildKit, no
`docker.sock`).

```
$ kubectl get events -n devops-app --sort-by=.lastTimestamp | tail -8
... Normal   Pulled     pod/vmapp-worker-67b447c655-k5xqc   Successfully pulled image ".../vmapp-worker:fc74b1591319"
... Normal   Killing    pod/vmapp-worker-8dbd56896-6fzkj    Stopping container worker
... Normal   ScalingReplicaSet deployment/vmapp-worker      Scaled down replica set vmapp-worker-8dbd56896 from 1 to 0
... Normal   Pulled     pod/vmapp-backend-74449b9fd8-75qxc  Successfully pulled image ".../vmapp-backend:fc74b1591319"
... Normal   Started    pod/vmapp-backend-74449b9fd8-75qxc  Container started
... Normal   SuccessfulDelete replicaset/vmapp-backend-56db7b9685  Deleted pod: vmapp-backend-56db7b9685-sv8lz

$ curl -s -o /dev/null -w '%{http_code}' http://k8s-vmappalb-6536a7fd42-358218343.il-central-1.elb.amazonaws.com/
302
```

`currentBuild.description` in the CD job records who/what-version/where for
this deploy (visible in the Jenkins UI build list): tag `fc74b1591319`,
namespace `devops-app`, triggered by CI build #18 - see Jenkinsfile-cd's
"Validate input" stage.

Smoke test passed with `HTTP 302` (the app correctly redirects
unauthenticated requests to `/login` - the expected behavior, not an error).

## 6. Rollback - real, not simulated

Immediately before build #6 above, an earlier CD run genuinely failed and
was rolled back for real (not staged): a commit that only touched
`app/backend/tests/` triggered CI's now-fixed "only build changed services"
logic (since removed - see README "Trade-offs"), producing a tag with a
real `vmapp-backend` image but **no** `vmapp-frontend`/`vmapp-worker` image.
CD's `helm upgrade --install` for that tag hit real `ImagePullBackOff`:

```
Warning  Failed  kubelet  Failed to pull image ".../vmapp-frontend:75d7651154f6": ... not found
Warning  Failed  kubelet  Failed to pull image ".../vmapp-worker:75d7651154f6": ... not found
```

`application-cd` build #5: **FAILURE** (`helm upgrade --wait --timeout 5m`
hit `context deadline exceeded` waiting on pods that could never become
ready). Rolled back to the last known-good revision:

```
$ helm rollback vmapp-app 2 -n devops-app
Rollback was a success! Happy Helming!

$ helm history vmapp-app -n devops-app
REVISION	UPDATED                 	STATUS    	CHART       	APP VERSION	DESCRIPTION
1       	Sun Sep  6 07:40:03 2026	superseded	my-app-0.1.0	v1.0.0     	Install complete
2       	Sun Sep  6 07:52:03 2026	superseded	my-app-0.1.0	v1.0.0     	Upgrade complete
3       	Sun Sep  6 08:02:29 2026	failed    	my-app-0.1.0	v1.0.0     	Upgrade "vmapp-app" failed: context deadline exceeded
4       	Sun Sep  6 08:07:57 2026	superseded	my-app-0.1.0	v1.0.0     	Rollback to 2
5       	Sun Sep  6 08:13:53 2026	deployed  	my-app-0.1.0	v1.0.0     	Upgrade complete
```

(Revision 5 above is the later, fully-fixed deploy from section 5 - the
rollback itself is revision 4.) Confirmed all pods converged back to the
pre-failure image and the app was reachable again before the fix was even
pushed:

```
$ kubectl get pods -n devops-app -o jsonpath='{..image}' | tr ' ' '\n' | sort -u
832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-backend:f90eeb81e43b
832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-frontend:f90eeb81e43b
832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-worker:f90eeb81e43b
$ curl -s -o /dev/null -w '%{http_code}' http://.../
302
```

Root cause (CI's per-service build optimization producing an incomplete,
undeployable tag) was then fixed in `Jenkinsfile-ci` (commit `fc74b15`) -
see README "Trade-offs" - and section 5 above is that fix's own first
successful run.
