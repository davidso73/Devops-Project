# VM Chooser - 3-Tier Demo App on AWS (Terraform + Ansible)

A small demo web app: users register/log in, then submit a form choosing a fake
"VM" (name, architecture, instance type). Nothing in the form actually creates
an EC2 instance - it's purely for testing the app's plumbing and collecting
data. Submissions flow through SQS to a worker, land in S3, and trigger email
notifications via SNS at each step. Deployed across 3 EC2 instances
(frontend/backend/worker) with RDS PostgreSQL for storage.

**Terraform provisions the infrastructure; Ansible configures and deploys the
software onto it.** Neither tool does the other's job: Terraform's EC2
resources carry no bootstrap script at all, and Ansible never creates or
deletes an AWS resource.

![Architecture diagram](docs/architecture.svg)

## Architecture

- **Network**: everything runs inside the existing `dev-enviroment-vpc`
  (`10.0.0.0/16`, region `il-central-1`). This project added two **private**
  subnets (`10.0.11.0/24` in `il-central-1a`, `10.0.12.0/24` in `il-central-1b`)
  alongside the VPC's existing public subnets.
- **No NAT Gateway.** Backend and worker have no public IP and no route to
  the internet at all. Outbound access to AWS APIs goes through **VPC
  endpoints** instead: a free S3 Gateway Endpoint (which also happens to serve
  Amazon Linux's S3-backed `dnf` repos) plus Interface Endpoints for SQS and
  SNS - the only two AWS services backend/worker call directly. This is
  cheaper than a NAT Gateway and keeps the private tier fully off the public
  internet.
- **Three EC2 instances**, one per service:
  - `vmapp-frontend` - public subnet, public IP, runs **nginx**.
  - `vmapp-backend` - private subnet A, runs the Flask app behind gunicorn.
  - `vmapp-worker` - private subnet B, long-polls SQS and does the background work.
- **Security groups** enforce the "frontend is the only thing the internet can
  reach" requirement: `dev-enviroment-ec2-sg` (frontend) allows 22/80 from
  anywhere; `vmapp-internal-sg` (backend + worker) only accepts traffic on the
  app port and SSH from the frontend's security group, plus a self-referencing
  rule so backend and worker can reach each other. Neither backend nor worker
  is reachable from the public internet under any circumstances.
- **RDS PostgreSQL** (`db.t3.micro`) sits in a DB subnet group spanning both
  private subnets, not publicly accessible, reachable only from
  `vmapp-internal-sg`.
- **SQS** decouples the web request from the slower work (writing to S3,
  updating status) so the form submission returns immediately.
- **SNS** (`vmapp-notifications`) has an email subscription to
  `david.sosi@gmail.com` and gets a `Publish` call for all three required
  events: a new DB record, a new S3 file, and a status change.
- **S3**: the app reuses the existing `nginx-content-832767338129-il-central-1-an`
  bucket, writing one JSON file per submitted request under the
  `user-choices/` prefix.
- **Ansible control node**: someone has to actually run `ansible-playbook`
  with network access to the private subnet. We use the **frontend instance
  itself** as the control node - it already has real internet access (to
  install packages and build the dependency wheelhouse) and can reach
  backend/worker directly over their private IPs, with no bastion/jump-host
  setup needed. See "How to run Ansible" below.

### Why nginx runs on the frontend

The frontend is the *only* instance with a public IP and the only one meant to
be reachable from the internet, so it's the only place that makes sense to
terminate public HTTP traffic. nginx there reverse-proxies everything to the
backend's private IP on port 8000 - the backend itself is never exposed
directly.

### Connection flow

1. Browser -> `http://<frontend-public-ip>/` (port 80, nginx).
2. nginx -> backend private IP `:8000` (gunicorn/Flask).
3. Backend -> RDS (`psycopg2`, port 5432) to read/write `users` and `vm_requests`.
4. On form submit, backend -> SNS (**"new DB record"** notification) and backend -> SQS (`SendMessage`), both over the private VPC endpoints - no internet involved.
5. Worker long-polls SQS (`ReceiveMessage` over the endpoint), and for each message:
   a. Worker -> S3 (`PutObject` to `user-choices/<id>.json` via the S3 gateway endpoint) -> SNS **"file uploaded to S3"** notification.
   b. Worker -> RDS (`UPDATE ... SET status='COMPLETED'`) -> SNS **"status changed"** notification.
6. SNS emails `david.sosi@gmail.com` for each of the three events above.
7. Separately, and unrelated to the app's own runtime traffic: the Ansible
   control node (frontend) reaches out to backend and worker over SSH to
   configure them and push the app code - see below.

## What Terraform creates

Everything under `terraform/` - the infrastructure shell, nothing about the
software running on it:

| Category | Resources |
|---|---|
| Network | 2 private subnets, a route table, an S3 gateway endpoint, SQS + SNS interface endpoints, a security group for the endpoints |
| Security | `vmapp-internal-sg` (backend/worker), an added ingress rule on the existing RDS security group |
| Compute | 3 bare EC2 instances (`vmapp-frontend`/`backend`/`worker`) - **no `user_data`, no software installed** |
| IAM | `vmapp-backend-role` / `vmapp-worker-role` (+ instance profiles) scoped to exactly the SQS/SNS/S3 actions each service needs |
| Data | RDS PostgreSQL instance + DB subnet group, an SQS queue, an SNS topic + email subscription |
| Secrets | `random_password` for the DB and the Flask session secret |
| Ansible handoff | 3 generated files (see "Handoff to Ansible" below) |

It does **not** install nginx, Python, or the app; does **not** create the
`vmapp` OS user; and does **not** start any service. That's entirely Ansible's job.

## What Ansible does

Everything under `Ansible/`, run against the bare instances Terraform created:

1. **`common` role (all 3 servers):** updates all OS packages, installs base
   packages (`python3.11`, `python3.11-pip`, `unzip`, `tar`, `vim`), creates a
   dedicated **`vmapp` system user/group** to run the application (never
   root), and creates `/opt/app` and `/etc/vmapp`.
2. **`nginx` role (frontend only):** installs nginx, removes the default
   site, templates `/etc/nginx/conf.d/vmapp.conf` as a reverse proxy to the
   backend (its address is read live from the inventory, not hardcoded), and
   enables/starts the service.
3. **`app` role (backend + worker):**
   - builds an offline Python dependency wheelhouse **once**, on the control
     node itself (`delegate_to: localhost`), targeting the exact runtime the
     instances use (`manylinux2014_x86_64`, Python 3.11) regardless of what
     OS the control node happens to be;
   - copies the app source (`app/backend` or `app/worker`) and the wheelhouse
     to the server, owned by `vmapp`;
   - creates a venv and `pip install --no-index --find-links=wheelhouse`s the
     requirements - no internet access needed on backend/worker at all;
   - templates `/etc/vmapp/<service>.env` with the RDS endpoint, DB
     credentials, S3 bucket, SQS queue URL, SNS topic ARN, and region (see
     `group_vars/`) - this is what satisfies "the application receives the
     AWS details it needs to work";
   - templates and enables a systemd unit (`vmapp-backend`/`vmapp-worker`)
     running as the `vmapp` user.

The playbook is idempotent - running it again with nothing changed reports
`changed=0` across every host.

## Handoff between the two tools

Terraform generates three files under `Ansible/` directly from real deployed
values, so there's no manual copy-pasting of IPs/ARNs between the tools:

- `Ansible/inventory.ini` - `[frontend]`/`[backend]`/`[worker]` groups with
  real IPs.
- `Ansible/group_vars/all/vars.yml` - non-secret app config (region, S3
  bucket, SQS URL, SNS ARN, RDS endpoint, DB name/username).
- `Ansible/group_vars/all/secrets.yml` - the DB password and Flask session
  secret (see "Secrets" below).

All three are gitignored - they contain live infrastructure details and,
for the last one, actual secrets.

## Repository layout

```
app/
  backend/             Flask app (auth, form, summary table)
  worker/               SQS consumer -> S3 + SNS + status update
terraform/             provisions bare infrastructure only
  ansible_templates/    templates for the 3 generated Ansible files above
Ansible/
  ansible.cfg
  inventory.ini          generated by Terraform
  playbook.yml            entry point: common -> nginx -> app
  group_vars/
    all/                  generated (vars.yml, secrets.yml)
    backend.yml, worker.yml   committed: which service + how to start it
  roles/
    common/, nginx/, app/  see "What Ansible does" above
docs/
  architecture.svg      diagram embedded above
```

The repo is organized by tool/concern at the top level so future pieces can
slot in alongside `app/`, `terraform/`, and `Ansible/` without reshuffling
anything: `docker/` and `k8s/` (a containerized version of the app) are the
planned next additions.

## How to run Terraform

Prerequisites: Terraform >= 1.5, AWS CLI, and an AWS profile with permissions
on this account (`dev-profile` is used by default, region `il-central-1`).

```bash
cd terraform
terraform init
terraform plan
terraform apply
terraform output
```

`terraform apply` also (re)generates the 3 files under `Ansible/` described
above. Run it again any time you want to refresh them (e.g. after replacing
an instance).

To tear everything down: `terraform destroy` from `terraform/` (this does not
touch the existing VPC, its public subnets, the S3 bucket, or the unrelated
`david-ec2` instance - only the resources this project created).

## How to run Ansible

Ansible's control node must be Linux/macOS/WSL - it does not support running
natively on Windows. This project uses the **frontend EC2 instance** as the
control node, since it already has internet access (for `dnf`/pip) and can
reach backend/worker directly over the private subnet:

```bash
# From your workstation, after `terraform apply`:
scp -i <path-to-david-key.pem> -r Ansible app <path-to-david-key.pem> \
  ec2-user@<frontend_public_ip>:~/                # copy the project + key up
ssh -i <path-to-david-key.pem> ec2-user@<frontend_public_ip>

# On the frontend instance:
chmod 600 ~/david-key.pem && mv ~/david-key.pem ~/.ssh/
sudo dnf install -y python3-pip
pip3 install --user ansible-core
export PATH=$HOME/.local/bin:$PATH

cd ~/Ansible
ansible-playbook -i inventory.ini playbook.yml
```

If you'd rather run it from your own Linux/WSL machine directly (not via
frontend), it works the same way as long as that machine has internet access
and can reach the private subnet - e.g. add a `ProxyJump` through the
frontend's public IP for the `backend`/`worker` groups in `inventory.ini`,
since an external machine can't reach private IPs directly the way an
in-VPC control node can.

## What variables need to be defined for each tool

**Terraform** (`terraform/variables.tf`, all have sensible defaults - override
with `-var`, a `.tfvars` file, or `TF_VAR_*`):

| Variable | Default | Notes |
|---|---|---|
| `aws_region` | `il-central-1` | |
| `instance_type` | `t3.micro` | frontend, backend, and worker |
| `ami_id` | `""` (empty) | empty resolves to the latest Amazon Linux 2023 AMI via SSM |
| `key_name` | `david-key` | must already exist in the account |
| `db_name` / `db_username` | `vmappdb` / `vmappadmin` | |
| `notification_email` | `david.sosi@gmail.com` | SNS subscription target |

**Ansible** - all variables are supplied via `group_vars/`, none need to be
passed on the command line:

| Variable | Where it comes from |
|---|---|
| `aws_region`, `s3_bucket`, `sqs_queue_url`, `sns_topic_arn`, `rds_endpoint`, `db_name`, `db_username`, `app_user`, `app_group`, `app_dir` | generated by Terraform into `group_vars/all/vars.yml` |
| `db_password`, `flask_secret_key` | generated by Terraform into `group_vars/all/secrets.yml` (secret) |
| `service_name`, `app_exec` | committed statically in `group_vars/backend.yml` / `group_vars/worker.yml` - what to deploy and how to start it |

## How to handle and manage secrets

Two secrets exist: the **RDS master password** and the **Flask session
secret key** (needed so all 3 gunicorn worker processes sign session cookies
identically - without it, logins would randomly "not stick" depending on
which worker handled a given request). Both are generated once by Terraform
(`random_password`) and flow the same way:

- Terraform state (`terraform/terraform.tfstate`) has them in plain text -
  gitignored, never committed.
- Terraform writes them into `Ansible/group_vars/all/secrets.yml` (also
  gitignored) so Ansible can template them into each service's `/etc/vmapp/*.env`
  file on the server (mode `0600`, owned by the `vmapp` user only).
- The SSH private key (`david-key.pem`) additionally gets copied onto the
  frontend instance so it can act as the Ansible control node for
  backend/worker. That's a demo-time tradeoff worth being explicit about: a
  real deployment would prefer SSH agent forwarding (never landing the key on
  a remote host) or running Ansible from a proper bastion/CI runner instead.
- **For real use beyond this demo**, all of the above should move to a
  secrets manager: AWS Secrets Manager or SSM Parameter Store (SecureString)
  for the DB password/Flask key, fetched by the app or by Ansible at
  deploy time instead of living in a plaintext file, and `ansible-vault` to
  encrypt `secrets.yml` itself if it must stay file-based.

## How to check that the system is working

1. `terraform output frontend_public_ip`, then browse to `http://<that-ip>/`.
2. Register a user, log in, submit the form - a row should appear in the
   summary table immediately (status `PENDING`), then flip to `COMPLETED`
   within a few seconds once the worker processes it.
3. `aws s3 ls s3://nginx-content-832767338129-il-central-1-an/user-choices/`
   should show a new `<id>.json` file matching your submission.
4. Check `david.sosi@gmail.com` for 3 notification emails per submission (the
   SNS subscription needs a one-time manual confirmation - AWS emails a
   confirm link; Terraform can't click it for you).
5. From the frontend (the Ansible control node, which has the SSH key and can
   reach the private subnet), use Ansible itself rather than a manual SSH hop,
   from inside `~/Ansible`:
   `ansible backend -i inventory.ini -a "systemctl status vmapp-backend" --become`
   and the equivalent for `worker`/`vmapp-worker` - both should show
   `active (running)` under the `vmapp` user.
6. Re-running `ansible-playbook -i inventory.ini playbook.yml` should report
   `changed=0` for every host if nothing has actually changed - that's the
   idempotency check.

## How to delete the environment when finished

```bash
cd terraform
terraform destroy
```

This removes every resource this project created (both EC2 instances, RDS,
SQS, SNS, the private subnets/endpoints/security groups) without touching the
pre-existing VPC/subnets, the S3 bucket, or unrelated resources in the
account. Ansible has no separate teardown step - once the instances are gone,
there's nothing left for it to manage.

## Estimated running cost

Roughly $50-55/month if left running continuously: RDS `db.t3.micro`
(~$12-15), 3x EC2 `t3.micro` (~$22 combined), two interface endpoints
(~$14.60), plus negligible SQS/SNS/S3 usage. `terraform destroy` removes it
all when you're done testing.

## Component reference

| Component | Purpose |
|---|---|
| `vmapp-frontend` (EC2, public) | nginx reverse proxy; the only internet-facing service; also the Ansible control node |
| `vmapp-backend` (EC2, private) | Flask/gunicorn app: auth, form, summary table, enqueues work |
| `vmapp-worker` (EC2, private) | Consumes SQS, writes to S3, updates DB status, publishes SNS |
| RDS PostgreSQL | `users` and `vm_requests` tables |
| S3 (`nginx-content-...` bucket) | Stores one JSON file per submitted request (`user-choices/`) |
| SQS (`vmapp-requests-queue`) | Queues each submitted request for the worker |
| SNS (`vmapp-notifications`) | Emails `david.sosi@gmail.com` on record-created / file-uploaded / status-changed |
| S3 Gateway + SQS/SNS Interface Endpoints | Give backend/worker AWS API access with no NAT Gateway and no public IP |

## Terraform state

This project uses Terraform's default **local backend** - no `backend` block
is configured, so state lives on disk rather than in S3/Terraform Cloud/etc.

- **Location:** `terraform/terraform.tfstate`, with the previous version kept
  alongside it as `terraform/terraform.tfstate.backup`. Both are the ground
  truth Terraform uses to map its config to real AWS resource IDs - deleting
  or losing this file doesn't delete the AWS resources, but it does make
  Terraform "forget" it manages them.
- **Never committed:** both files are excluded via `.gitignore` - the state
  file contains the RDS password and Flask secret in plain text (see
  "Secrets" above), plus every resource's live attributes.
- **Solo/local only, by design, for this project:** a local backend has no
  locking, so two `terraform apply`/`destroy` runs at the same time (from two
  terminals, or two people) can corrupt it. That's an acceptable tradeoff for
  a single-person demo project; a team or long-lived setup should move to a
  remote backend (e.g. an `s3` backend plus a DynamoDB lock table) so state is
  shared and locked instead of living on one machine's disk.
- **Inspecting it** without changing anything: `terraform show` (the full
  state), `terraform state list` (just resource addresses), or
  `terraform output` (the outputs above). Every `plan`/`apply` also refreshes
  state by re-reading real AWS resources first (the `Refreshing state...`
  lines), so it self-corrects if something drifts.

## Notes from standing this up

- Modifying `user_data` on a running EC2 instance does **not** make
  cloud-init re-run it (it's cached per instance ID) - when we removed
  `user_data` entirely in favor of Ansible, we deliberately replaced all
  three instances (`terraform apply -replace=...`) rather than relying on an
  in-place update, so Ansible would be configuring genuinely bare servers.
- Each gunicorn worker process signs session cookies with its own random key
  unless `FLASK_SECRET_KEY` is set - this caused logins to intermittently
  "not stick" depending on which of the 3 workers handled a given request,
  until a shared secret (generated by Terraform, templated by Ansible) was
  added.

---

# Kubernetes (EKS) Deployment

The same app, containerized and run on EKS via Helm, in a separate top-level
`K8s/` folder. This is an **additional, independent deployment of the same
app** - not a replacement. The 3 EC2 instances above keep running exactly as
described; the k8s pods run alongside them and connect to the **same** RDS
database, S3 bucket, SQS queue, and SNS topic. Both are just separate
front-doors onto shared state - a real request through either one shows up
in the same `vm_requests` table.

![Kubernetes architecture diagram](K8s/docs/k8s-architecture.svg)

## Architecture

- **EKS cluster** (`vmapp-eks`) with a **managed node group** (2x `t3.medium`)
  in 2 new, dedicated private subnets inside the same `dev-enviroment-vpc`
  used everywhere else in this project. Kept separate from the EC2 stack's
  own private subnets because the VPC CNI hands every pod a real VPC IP -
  reusing the small `/24`s from the EC2 phase would risk running out of
  addresses.
- A **NAT Gateway** dedicated to those subnets - EKS nodes need broad AWS API
  reachability (ECR, EKS, STS, CloudWatch, ELB), enough distinct services
  that a NAT Gateway ends up simpler and similarly priced to replicating the
  "VPC endpoints only" pattern used for the simpler 3-tier app.
- All app pods run in a dedicated **`devops-app`** namespace - never `default`.
- **3 Deployments** (frontend/backend/worker), each with its own
  **ServiceAccount**, **Service** (except worker, which listens on nothing),
  fixed-tag container images from **ECR**, resource requests/limits, and
  readiness/liveness probes.
- **AWS Load Balancer Controller** (installed via Helm into `kube-system`,
  itself using IRSA) watches the **Ingress** and provisions a public **ALB**.
- **ConfigMap** (`vmapp-config`) holds all non-secret configuration
  (region, S3 bucket, SQS URL, SNS ARN, RDS endpoint, DB name/user) plus the
  frontend's nginx config. A **Secret** (`vmapp-secrets`, created manually -
  see below) holds the DB password and Flask session key.
- **IRSA** (IAM Roles for Service Accounts) gives backend and worker pods
  their AWS permissions directly - no static access keys anywhere. Frontend
  gets no AWS role at all.
- **NetworkPolicies** enforce (not just document) who can talk to whom, using
  the VPC CNI's native NetworkPolicy support enabled on the cluster.

## What runs inside the cluster vs. stays outside

| Inside EKS | Outside EKS (shared with the EC2 deployment) |
|---|---|
| frontend, backend, worker pods | RDS PostgreSQL |
| AWS Load Balancer Controller | S3 bucket |
| ConfigMap / Secret / ServiceAccounts | SQS queue |
| | SNS topic |
| | ECR (images live here, pulled by nodes) |

## Building and pushing images

Same constraint as Ansible earlier: this Windows machine can't run Docker
natively, so a small **build/ops EC2 instance** (`K8s/terraform/buildhost.tf`)
does it instead - Docker, kubectl, helm, and awscli, with an IAM role that
can push to ECR and administer the EKS cluster (via an EKS *access entry*,
the modern replacement for hand-editing `aws-auth`).

```bash
# From the build host, after scp-ing the repo up:
aws ecr get-login-password --region il-central-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.il-central-1.amazonaws.com

for svc in frontend backend worker; do
  docker build -t <account-id>.dkr.ecr.il-central-1.amazonaws.com/vmapp-$svc:v1.0.0 app/$svc
  docker push <account-id>.dkr.ecr.il-central-1.amazonaws.com/vmapp-$svc:v1.0.0
done
```

## Creating the namespace

The Helm chart creates it (`K8s/helm/my-app/templates/namespace.yaml`) - no
separate step needed. Verify with `kubectl get namespaces`.

## Creating secrets

`K8s/helm/my-app/secret.example.yaml` shows the shape of the Secret the app
expects - it's deliberately kept **outside** `templates/` so `helm install`
never actually applies it with those placeholder values. The real one is
created manually, sourcing the same credentials already used by the EC2
deployment (`random_password.db` / `random_password.flask_secret` in the
*original* `terraform/` stack - both deployments share the same DB):

```bash
cd terraform   # the original stack, not K8s/terraform
DB_PASSWORD=$(terraform output -raw db_password)
FLASK_SECRET=$(terraform output -raw flask_secret_key 2>/dev/null || echo "<from Ansible/group_vars/all/secrets.yml>")

kubectl create secret generic vmapp-secrets -n devops-app \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --from-literal=FLASK_SECRET_KEY="$FLASK_SECRET"
```

**Order matters here**: run `helm install` *before* this command, not after -
the chart's `namespace.yaml` template is what creates `devops-app` in the
first place, and Helm expects to "own" every resource in its release. If you
create the namespace yourself first (e.g. because you need it to exist to
create the secret in it), `helm install` will refuse it with an ownership
error. See "How to run the application" below for the actual working order,
learned the hard way while standing this up.

## How to run the application

```bash
cd K8s/terraform
terraform init && terraform plan && terraform apply

# build + push images (see above), then update K8s/helm/my-app/values.yaml
# with the real ECR repo URLs and IRSA role ARNs from `terraform output`

helm upgrade --install vmapp-app ./K8s/helm/my-app   # creates the devops-app namespace itself

# only now does the namespace exist, so the secret can be created in it:
kubectl create secret generic vmapp-secrets -n devops-app --from-literal=... # see above

# the app pods reference the secret via envFrom but don't restart on their own when
# it changes/first appears - do one rollout after creating it the first time:
kubectl rollout restart deployment/vmapp-backend deployment/vmapp-worker -n devops-app
```

## How to check the system works

See `K8s/evidence.md` for the full, literal output of every command below,
captured against the live cluster.

```bash
kubectl get nodes
kubectl get namespaces
kubectl get pods -n devops-app
kubectl get deployments -n devops-app
kubectl get services -n devops-app
kubectl get ingress -n devops-app
kubectl describe pod <pod-name> -n devops-app
kubectl logs <pod-name> -n devops-app
```

Plus: browsing to the ALB's address over HTTP; a raw `kubectl exec` check
between backend and frontend pods; a full register/login/submit run
producing the same `COMPLETED` row + S3 object + SNS activity as the EC2
deployment; and deleting a pod to confirm the Deployment replaces it and the
app keeps working immediately after.

## How to delete the environment

```bash
helm uninstall vmapp-app -n devops-app
kubectl delete namespace devops-app
cd K8s/terraform && terraform destroy
```

This only removes the k8s phase - the EC2 stack, RDS, S3, SQS, and SNS are
untouched (they're shared, and still serve the EC2 deployment).

## Kubernetes Security

### Separation of privileges (ServiceAccounts)

Three ServiceAccounts, one per service, each with a different (or no) IAM
role - not a single shared identity:

| Service | ServiceAccount | AWS permissions |
|---|---|---|
| frontend | `vmapp-frontend` | **none** - no IRSA role attached at all |
| backend | `vmapp-backend` | `sqs:SendMessage`, `sns:Publish` only |
| worker | `vmapp-worker` | `sqs:Receive/Delete/GetAttrs/ChangeVisibility`, `s3:PutObject` (scoped to `user-choices/*` only), `sns:Publish` |

They do **not** have the same permissions, deliberately. Running every
service with the same broad role (or worse, one shared admin-ish role) means
a compromise of the *least* trusted component (frontend, the only one
directly internet-facing) would hand an attacker the *most* powerful
credentials in the system. Splitting them means a compromised frontend pod
has zero AWS API access - it can't read S3, can't touch SQS/SNS, can't do
anything but proxy HTTP to the backend Service.

### Secrets Management

- Non-secret config -> ConfigMap (`vmapp-config`): region, bucket name, queue
  URL, topic ARN, RDS endpoint, DB name/user. None of this is sensitive.
- Secrets -> a real Kubernetes `Secret` (`vmapp-secrets`): DB password, Flask
  session key. **Created manually via `kubectl create secret`**, never
  templated with real values in the Helm chart or committed to git -
  `secret.example.yaml` shows only the shape, with placeholder strings, and
  lives outside `templates/` specifically so it's never accidentally applied.
- Kubernetes Secrets are base64-encoded, not encrypted, by default. Anyone
  with `get secrets` RBAC in the namespace can read them in plaintext. For
  real use beyond this demo, the next step up is enabling **envelope
  encryption at rest** (KMS-backed, an EKS cluster option) and/or moving to
  **AWS Secrets Manager** via the Secrets Store CSI Driver instead of native
  Secrets.
- The AWS credentials backing the app's actual permissions never live in a
  Secret at all - IRSA vends short-lived, automatically-rotated credentials
  to the pod via its ServiceAccount token, so there's no long-lived AWS
  access key to leak in the first place.

### Network Security

Enforced by `K8s/helm/my-app/templates/networkpolicy.yaml` (see that file for
the exact rules), not just described:

| Who can talk to... | Allowed from |
|---|---|
| frontend | the ALB (arrives as a VPC IP, not a pod - allowed from the VPC CIDR) |
| backend | **only** frontend pods, on port 8000 |
| worker | **nothing** - no ingress rule matches it at all (default-deny) |
| database (RDS) | backend/worker pods, over the VPC network on 5432 (enforced at the security-group level, same as the EC2 deployment's `vmapp-internal-sg` pattern) |

What's exposed to the outside: **only the ALB**, on port 80. Nothing else -
not the pods, not the Services, not the nodes - has a public IP or a route
from the internet.

### Container Security

Every container's `securityContext` sets:
- `runAsNonRoot: true` with a fixed, non-zero UID (backend/worker run as
  UID 1000, set explicitly in their Dockerfiles; frontend uses
  `nginxinc/nginx-unprivileged`'s built-in UID 101 - chosen specifically so
  nginx doesn't need root to bind its port)
- `allowPrivilegeEscalation: false` - a compromised process can't `setuid`
  its way to more privilege than it started with
- `capabilities.drop: ["ALL"]` - none of these services need any Linux
  capability (raw sockets, binding privileged ports, etc.)
- `readOnlyRootFilesystem: true` on frontend (with `emptyDir` volumes for the
  few paths nginx needs to write - cache, pid, tmp); backend/worker keep a
  writable root filesystem for now, a stated trade-off (see below) rather
  than a security decision.

### Image Security

- Images are built from this repo's `app/{frontend,backend,worker}/Dockerfile`
  and pushed to **private ECR repositories** created by Terraform
  (`K8s/terraform/ecr.tf`) - not pulled from a public registry at deploy
  time.
- **Fixed tags only** (`v1.0.0`), never `latest` - `values.yaml`'s
  `image.tag` and the ECR repos' `image_tag_mutability = "IMMUTABLE"` both
  enforce this: an immutable repo physically refuses to let a tag be
  overwritten once pushed, so `v1.0.0` always means the same bytes.
- **Scanned**: ECR's built-in vulnerability scanning (`scan_on_push = true`,
  Amazon Inspector-backed, free) runs automatically on every push. Real
  findings for these images are in `K8s/evidence.md`.

### Ingress Security

- Exposed via a public **ALB** (AWS Load Balancer Controller), HTTP only, on
  port 80.
- **No HTTPS** - there's no domain name or ACM certificate in this AWS
  account, and ACM can't issue a certificate without one. This is a real,
  stated trade-off: a production deployment would register a domain, request
  an ACM certificate, and add an HTTPS listener (443) with an HTTP->HTTPS
  redirect - all the Helm chart infrastructure (`ingress.yaml`) is already
  ALB-based and would need only the certificate ARN annotation added.
- **Access restriction**: none beyond the app's own login - the ALB accepts
  connections from anywhere on port 80. This matches the EC2 deployment's
  posture (nginx also accepts 80 from `0.0.0.0/0`).
- **Public vs. internal separation**: only the ALB is public. The Ingress
  routes exclusively to the frontend Service - backend has no Ingress rule
  and is only reachable from inside the cluster (enforced by NetworkPolicy,
  not just by omission from the Ingress).

## Trade-offs and compromises made

- **HTTP-only Ingress** - no domain/certificate available (see above).
- **Both deployments left running** (EC2 + EKS) sharing one RDS/S3/SQS/SNS,
  per an explicit choice to avoid doubling infrastructure cost while still
  proving the k8s version works end-to-end against real data.
- **NAT Gateway over VPC endpoints** for this phase specifically - EKS's
  broader AWS API surface (EKS/STS/ECR/CloudWatch/ELB, not just S3/SQS/SNS)
  makes the endpoint-only approach used for the EC2 stack less clearly
  cheaper here.
- **Kubernetes Secrets, not Secrets Manager/Vault** - simpler for a course
  project; documented as the natural next step rather than implemented.
- **Backend/worker keep a writable root filesystem** - only frontend got the
  full `readOnlyRootFilesystem: true` treatment; extending it to the Python
  services would need more `emptyDir` mounts for `pip`/temp paths than the
  scope of this phase justified.
- **A dedicated build/ops EC2 instance** just to run Docker/kubectl/helm,
  since none of that tooling runs natively on the Windows machine driving
  this project - the same fix pattern used for Ansible earlier in this
  project, applied again here.
