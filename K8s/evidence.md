# Kubernetes (EKS) Deployment Evidence

Captured against the live `vmapp-eks` cluster, from the build/ops EC2 instance
acting as the kubectl/helm client (see `README.md` -> "Building and pushing
images" for why). All 5 pods (2 frontend, 2 backend, 1 worker) are healthy at
the time of capture.

## `kubectl get nodes`

```
NAME                                           STATUS   ROLES    AGE   VERSION
ip-10-0-33-199.il-central-1.compute.internal   Ready    <none>   16m   v1.36.3-eks-cb19647
ip-10-0-60-182.il-central-1.compute.internal   Ready    <none>   16m   v1.36.3-eks-cb19647
```

## `kubectl get namespaces`

```
NAME              STATUS   AGE
default           Active   88m
devops-app        Active   13m
kube-node-lease   Active   88m
kube-public       Active   88m
kube-system       Active   88m
```

## `kubectl get pods -n devops-app`

```
NAME                             READY   STATUS    RESTARTS        AGE
vmapp-backend-76bb6c58c6-jz68z   1/1     Running   0               12m
vmapp-backend-76bb6c58c6-wrlbj   1/1     Running   0               55s
vmapp-frontend-89777dff5-2429p   1/1     Running   0               12m
vmapp-frontend-89777dff5-mb5md   1/1     Running   0               12m
vmapp-worker-854669f6c9-hf8dw    1/1     Running   1 (2m18s ago)   12m
```

(`vmapp-backend-...-wrlbj` is the pod created by the deliberate pod-restart
test below; the worker's one restart happened during initial rollout, before
a security-group fix - see "Notes" at the end of this file.)

## `kubectl get deployments -n devops-app`

```
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
vmapp-backend    2/2     2            2           12m
vmapp-frontend   2/2     2            2           12m
vmapp-worker     1/1     1            1           12m
```

## `kubectl get services -n devops-app`

```
NAME             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
vmapp-backend    ClusterIP   172.20.51.12     <none>        8000/TCP   12m
vmapp-frontend   ClusterIP   172.20.220.161   <none>        80/TCP     12m
```

Note there is deliberately no `vmapp-worker` Service - it doesn't listen on
any port, matching the EC2 deployment.

## `kubectl get ingress -n devops-app`

```
NAME            CLASS    HOSTS   ADDRESS                                                            PORTS   AGE
vmapp-ingress   <none>   *       k8s-vmappalb-6536a7fd42-358218343.il-central-1.elb.amazonaws.com   80      12m
```

## `kubectl describe pod <pod-name> -n devops-app`

```
Name:             vmapp-backend-76bb6c58c6-jz68z
Namespace:        devops-app
Priority:         0
Service Account:  vmapp-backend
Node:             ip-10-0-60-182.il-central-1.compute.internal/10.0.60.182
Start Time:       Sun, 06 Sep 2026 01:58:26 +0000
Labels:           app.kubernetes.io/name=vmapp-backend
                  app.kubernetes.io/part-of=vmapp
                  pod-template-hash=76bb6c58c6
                  topology.kubernetes.io/region=il-central-1
                  topology.kubernetes.io/zone=il-central-1b
Annotations:      <none>
Status:           Running
IP:               10.0.58.163
IPs:
  IP:           10.0.58.163
Controlled By:  ReplicaSet/vmapp-backend-76bb6c58c6
Containers:
  backend:
    Container ID:   containerd://945d4909b77a906e747df964de88e7e20be6f2aa67e32cc76f2b92f35e2b3120
    Image:          832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-backend:v1.0.0
    Image ID:       832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-backend@sha256:96caae52d322cea884b7c69ef5da4ff7a35d83f183c19769300daae96f0b49ae
    Port:           8000/TCP
    Host Port:      0/TCP
    State:          Running
      Started:      Sun, 06 Sep 2026 01:58:33 +0000
    Ready:          True
    Restart Count:  0
    Limits:
      cpu:     500m
      memory:  256Mi
    Requests:
      cpu:      100m
      memory:   128Mi
    Liveness:   http-get http://:8000/ delay=20s timeout=1s period=20s #success=1 #failure=3
    Readiness:  http-get http://:8000/ delay=10s timeout=1s period=10s #success=1 #failure=3
    Environment Variables from:
      vmapp-config   ConfigMap  Optional: false
      vmapp-secrets  Secret     Optional: false
    Environment:
      AWS_STS_REGIONAL_ENDPOINTS:   regional
      AWS_DEFAULT_REGION:           il-central-1
      AWS_REGION:                   il-central-1
      AWS_ROLE_ARN:                 arn:aws:iam::832767338129:role/vmapp-eks-backend-role
      AWS_WEB_IDENTITY_TOKEN_FILE:  /var/run/secrets/eks.amazonaws.com/serviceaccount/token
    Mounts:
      /var/run/secrets/eks.amazonaws.com/serviceaccount from aws-iam-token (ro)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-69mqt (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   True
  Initialized                 True
  Ready                       True
  ContainersReady             True
  PodScheduled                True
QoS Class:                   Burstable
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  13m   default-scheduler  Successfully assigned devops-app/vmapp-backend-76bb6c58c6-jz68z to ip-10-0-60-182.il-central-1.compute.internal
  Normal  Pulling    13m   kubelet            Pulling image "832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-backend:v1.0.0"
  Normal  Pulled     12m   kubelet            Successfully pulled image "832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-backend:v1.0.0" in 5.302s (5.302s including waiting). Image size: 72594554 bytes.
  Normal  Created    12m   kubelet            Container created
  Normal  Started    12m   kubelet            Container started
```

Note the `AWS_ROLE_ARN` / `AWS_WEB_IDENTITY_TOKEN_FILE` environment variables
and the `aws-iam-token` projected volume - these are injected automatically
by EKS's Pod Identity Webhook because of the ServiceAccount's IRSA
annotation, not by anything in the Helm chart's own env config. This is the
concrete proof IRSA is actually wired up, not just declared.

## `kubectl logs <pod-name> -n devops-app`

```
[2026-09-06 01:58:34 +0000] [1] [INFO] Starting gunicorn 22.0.0
[2026-09-06 01:58:34 +0000] [1] [INFO] Listening at: http://0.0.0.0:8000 (1)
[2026-09-06 01:58:34 +0000] [1] [INFO] Using worker: sync
[2026-09-06 01:58:34 +0000] [7] [INFO] Booting worker with pid: 7
[2026-09-06 01:58:34 +0000] [8] [INFO] Booting worker with pid: 8
[2026-09-06 01:58:34 +0000] [9] [INFO] Booting worker with pid: 9
```

Worker pod logs, current container (successfully polling SQS after the fix
described in "Notes" below):

```
worker started, polling https://sqs.il-central-1.amazonaws.com/832767338129/vmapp-requests-queue
```

## Access to the application via HTTP

```
$ curl -i http://k8s-vmappalb-6536a7fd42-358218343.il-central-1.elb.amazonaws.com/
HTTP/1.1 302 FOUND
Date: Sun, 06 Sep 2026 02:04:52 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 199
Connection: keep-alive
Server: nginx/1.27.5
Location: /login
Vary: Cookie
```

No HTTPS - see README "Ingress Security" for why (no domain/ACM certificate
in this account).

## Communication between frontend and backend

Raw connectivity check, executed from inside a frontend pod against the
backend Service's cluster-internal DNS name:

```
$ kubectl exec -n devops-app vmapp-frontend-89777dff5-2429p -- \
    wget -qO- --server-response http://vmapp-backend.devops-app.svc.cluster.local:8000/

  HTTP/1.1 302 FOUND
  Server: gunicorn
  ...
  HTTP/1.1 200 OK
  Server: gunicorn
  ...
<!doctype html>
<html lang="en">
...
```

This is the direction the app actually uses (nginx proxies to the backend).
The reverse direction (backend calling frontend) is not something the app
ever does, and is in fact **blocked** by design - `networkpolicy.yaml`'s
egress rule for backend/worker does not include a path to frontend, only to
RDS, DNS, and HTTPS/443 for AWS APIs. Attempting it confirms the policy is
actually enforced, not just declared:

```
$ kubectl exec -n devops-app vmapp-backend-76bb6c58c6-jz68z -- \
    python3 -c "import urllib.request; urllib.request.urlopen('http://vmapp-frontend.devops-app.svc.cluster.local', timeout=5)"
...
TimeoutError: timed out
```

## Communication from the application to the database

Raw query executed from inside a running backend pod, using the app's own
`db.py` connection helper against the same RDS instance the EC2 deployment
uses:

```
$ kubectl exec -n devops-app vmapp-backend-76bb6c58c6-jz68z -- python3 -c "
from db import get_connection
conn = get_connection()
with conn.cursor() as cur:
    cur.execute('SELECT id, vm_name, status FROM vm_requests ORDER BY id DESC LIMIT 5')
    for row in cur.fetchall():
        print(row)
conn.close()
"
(5, 'k8s-deployed-vm2', 'COMPLETED')
(4, 'k8s-deployed-vm', 'PENDING')
(3, 'final-check-vm', 'COMPLETED')
(2, 'first-VM', 'COMPLETED')
(1, 'my-test-vm', 'COMPLETED')
```

Rows 1-3 predate this deployment (submitted via the EC2 deployment or by
hand while testing - both deployments share the same database, by design).
Row 4 is the request that hit the SQS/SNS connectivity bug (see Notes);
row 5 is a full submission through the k8s deployment after the fix,
which is exactly the flow demonstrated next.

## Proper use of S3 and SNS - full end-to-end submission through the ALB

```
$ curl -c jar -b jar -d "username=k8sUser2&password=K8sPass123" .../register   -> HTTP 302
$ curl -c jar -b jar -d "username=k8sUser2&password=K8sPass123" .../login      -> HTTP 302
$ curl -c jar -b jar -d "vm_name=k8s-deployed-vm2&architecture=64bit-arm&instance_type=t3-small" .../   -> HTTP 302

$ curl -c jar -b jar .../   (summary table)
  k8sUser2 | k8s-deployed-vm2 | 64bit-arm | t3-small | COMPLETED | 2026-09-06 02:09

$ aws s3 ls s3://nginx-content-832767338129-il-central-1-an/user-choices/
2026-09-05 21:19:39        137 1.json
2026-09-05 21:23:17        131 2.json
2026-09-06 00:34:00        141 3.json
2026-09-06 05:09:34        142 5.json   <- new file, written by the worker pod via IRSA
```

Status reaching `COMPLETED` and a new S3 object both require the worker pod's
IRSA-scoped `s3:PutObject` and `sns:Publish` calls (via `vmapp-eks-worker-role`)
to have actually succeeded - this is the same event chain documented in the
main README (record-created / file-uploaded / status-changed), now running
from pods instead of EC2 instances.

## Restart of a pod and continued proper operation

```
$ kubectl delete pod -n devops-app vmapp-backend-76bb6c58c6-gzh9c
pod "vmapp-backend-76bb6c58c6-gzh9c" deleted

$ kubectl get pods -n devops-app -l app.kubernetes.io/name=vmapp-backend
NAME                             READY   STATUS    RESTARTS   AGE
vmapp-backend-76bb6c58c6-jz68z   1/1     Running   0          11m
vmapp-backend-76bb6c58c6-wrlbj   0/1     Running   0          6s   <- replacement, immediately scheduled

# 15 seconds later:
NAME                             READY   STATUS    RESTARTS   AGE
vmapp-backend-76bb6c58c6-jz68z   1/1     Running   0          12m
vmapp-backend-76bb6c58c6-wrlbj   1/1     Running   0          35s  <- now ready

$ curl -o /dev/null -w "HTTP %{http_code}\n" http://k8s-vmappalb-.../
HTTP 302   <- app never stopped responding (the other backend replica served traffic throughout)
```

## ECR image scan findings (`aws ecr describe-image-scan-findings`)

Real results from ECR's built-in scan-on-push (Amazon Inspector-backed),
for the exact `v1.0.0` images running above:

| Image | CRITICAL | HIGH | MEDIUM | LOW |
|---|---|---|---|---|
| vmapp-frontend | 4 | 31 | 37 | 7 |
| vmapp-backend | 6 | 11 | 3 | 1 |
| vmapp-worker | 6 | 11 | 3 | 1 |

All findings are in OS-level packages from the base images
(`python:3.11-slim`, `nginxinc/nginx-unprivileged:1.27-alpine`), not in this
project's own code. This is real, unfiltered output, not a claim - a
production deployment would act on these (rebuild on a cadence to pick up
base-image patches, consider a smaller/distroless base to shrink the
package surface, and gate deploys on scan results via CI).

## Notes

While first deploying, backend/worker's SQS/SNS calls hung and timed out
(visible above as request id 4 stuck at `PENDING`, and the worker pod's one
restart). Root cause: the **EC2 deployment's** SQS/SNS VPC interface
endpoints have private DNS enabled, which resolves
`sqs./sns.<region>.amazonaws.com` to the endpoint's private IP **VPC-wide** -
including for EKS pods, even though this cluster was meant to reach those
APIs via its own NAT Gateway instead. The endpoint's security group only
allowed the EC2 stack's traffic, so EKS pods' connections were silently
dropped. Fixed with one additional security group rule
(`K8s/terraform/eks.tf`, `aws_security_group_rule.vpc_endpoints_from_eks_nodes`)
allowing the EKS cluster security group into that existing endpoint SG on
443. Everything above reflects the state after that fix.
