# Deployment Evidence

Commands run from `terraform/` (Terraform) and from `~/Devops-Project/Ansible`
on the frontend EC2 instance acting as the Ansible control node (see
`README.md` -> "How to run Ansible" for why frontend is used as the control
node). Captured after the Terraform+Ansible split was fully applied - state
matches configuration with zero drift.

## `terraform init`

```
Initializing provider plugins found in the configuration...
- Reusing previous version of hashicorp/aws from the dependency lock file
- Reusing previous version of hashicorp/random from the dependency lock file
- Reusing previous version of hashicorp/local from the dependency lock file
- Using previously-installed hashicorp/aws v5.100.0
- Using previously-installed hashicorp/random v3.9.0
- Using previously-installed hashicorp/local v2.9.0

Initializing the backend...

Initializing provider plugins found in the state...
- Reusing previous version of hashicorp/random
- Reusing previous version of hashicorp/aws
- Reusing previous version of hashicorp/local
- Using previously-installed hashicorp/random v3.9.0
- Using previously-installed hashicorp/aws v5.100.0
- Using previously-installed hashicorp/local v2.9.0


Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

## `terraform plan`

```
random_password.flask_secret: Refreshing state... [id=none]
random_password.db: Refreshing state... [id=none]
local_file.ansible_group_vars_secrets: Refreshing state... [id=5f2049763a0815b9838e44e5db7b602ea8159d7e]
aws_security_group.vmapp_internal: Refreshing state... [id=sg-07a2907893b5c8ff8]
aws_sqs_queue.requests: Refreshing state... [id=https://sqs.il-central-1.amazonaws.com/832767338129/vmapp-requests-queue]
aws_sns_topic.notifications: Refreshing state... [id=arn:aws:sns:il-central-1:832767338129:vmapp-notifications]
data.aws_ssm_parameter.al2023_ami: Reading...
data.aws_iam_policy_document.ec2_assume: Reading...
aws_subnet.private_a: Refreshing state... [id=subnet-0701dc7f4fdc16a99]
data.aws_iam_policy_document.ec2_assume: Read complete after 0s [id=1443847869]
aws_subnet.private_b: Refreshing state... [id=subnet-0b6027b13026ce891]
aws_route_table.private: Refreshing state... [id=rtb-0e9b1967d58431d7f]
aws_iam_role.backend: Refreshing state... [id=vmapp-backend-role]
aws_iam_role.worker: Refreshing state... [id=vmapp-worker-role]
data.aws_ssm_parameter.al2023_ami: Read complete after 0s [id=/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64]
aws_instance.frontend: Refreshing state... [id=i-04e8ac73824c08186]
aws_security_group_rule.rds_from_vmapp_internal: Refreshing state... [id=sgrule-996137474]
aws_security_group.vpc_endpoints: Refreshing state... [id=sg-0de108e1c67290fcd]
aws_vpc_endpoint.s3: Refreshing state... [id=vpce-0cf4114ceb7d268bb]
aws_route_table_association.private_b: Refreshing state... [id=rtbassoc-027cb996185c10af0]
aws_db_subnet_group.vmapp: Refreshing state... [id=vmapp-db-subnet-group]
aws_route_table_association.private_a: Refreshing state... [id=rtbassoc-0204666610a317ce1]
aws_vpc_endpoint.sqs: Refreshing state... [id=vpce-0fed99cb20ed9e1ca]
aws_vpc_endpoint.sns: Refreshing state... [id=vpce-0753a4c0232e2ef22]
aws_db_instance.vmapp: Refreshing state... [id=db-WRBQFMJ7B5S3D2EVHUOTY4367A]
aws_sns_topic_subscription.email: Refreshing state... [id=arn:aws:sns:il-central-1:832767338129:vmapp-notifications:44fd2133-a5a6-42d6-a694-a17cdd8fd025]
local_file.ansible_group_vars_all: Refreshing state... [id=6609c7532a18d7be48aa6d339a4f705d04201f7c]
aws_iam_role_policy.worker: Refreshing state... [id=vmapp-worker-role:vmapp-worker-policy]
aws_iam_instance_profile.worker: Refreshing state... [id=vmapp-worker-profile]
aws_iam_role_policy.backend: Refreshing state... [id=vmapp-backend-role:vmapp-backend-policy]
aws_iam_instance_profile.backend: Refreshing state... [id=vmapp-backend-profile]
aws_instance.worker: Refreshing state... [id=i-012fadbdcda3dbeee]
aws_instance.backend: Refreshing state... [id=i-0221418043e9eadb1]
local_file.ansible_inventory: Refreshing state... [id=f4c9bbbb4ccbb482516e9c627b4d7c3850aefc51]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

## `terraform apply`

```
random_password.db: Refreshing state... [id=none]
random_password.flask_secret: Refreshing state... [id=none]
local_file.ansible_group_vars_secrets: Refreshing state... [id=5f2049763a0815b9838e44e5db7b602ea8159d7e]
data.aws_iam_policy_document.ec2_assume: Reading...
aws_route_table.private: Refreshing state... [id=rtb-0e9b1967d58431d7f]
aws_subnet.private_a: Refreshing state... [id=subnet-0701dc7f4fdc16a99]
aws_subnet.private_b: Refreshing state... [id=subnet-0b6027b13026ce891]
data.aws_ssm_parameter.al2023_ami: Reading...
aws_sqs_queue.requests: Refreshing state... [id=https://sqs.il-central-1.amazonaws.com/832767338129/vmapp-requests-queue]
aws_security_group.vmapp_internal: Refreshing state... [id=sg-07a2907893b5c8ff8]
aws_sns_topic.notifications: Refreshing state... [id=arn:aws:sns:il-central-1:832767338129:vmapp-notifications]
data.aws_iam_policy_document.ec2_assume: Read complete after 0s [id=1443847869]
aws_iam_role.backend: Refreshing state... [id=vmapp-backend-role]
aws_iam_role.worker: Refreshing state... [id=vmapp-worker-role]
data.aws_ssm_parameter.al2023_ami: Read complete after 1s [id=/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64]
aws_instance.frontend: Refreshing state... [id=i-04e8ac73824c08186]
aws_vpc_endpoint.s3: Refreshing state... [id=vpce-0cf4114ceb7d268bb]
aws_route_table_association.private_b: Refreshing state... [id=rtbassoc-027cb996185c10af0]
aws_route_table_association.private_a: Refreshing state... [id=rtbassoc-0204666610a317ce1]
aws_db_subnet_group.vmapp: Refreshing state... [id=vmapp-db-subnet-group]
aws_security_group_rule.rds_from_vmapp_internal: Refreshing state... [id=sgrule-996137474]
aws_security_group.vpc_endpoints: Refreshing state... [id=sg-0de108e1c67290fcd]
aws_vpc_endpoint.sqs: Refreshing state... [id=vpce-0fed99cb20ed9e1ca]
aws_vpc_endpoint.sns: Refreshing state... [id=vpce-0753a4c0232e2ef22]
aws_iam_instance_profile.backend: Refreshing state... [id=vmapp-backend-profile]
aws_iam_instance_profile.worker: Refreshing state... [id=vmapp-worker-profile]
aws_db_instance.vmapp: Refreshing state... [id=db-WRBQFMJ7B5S3D2EVHUOTY4367A]
aws_instance.worker: Refreshing state... [id=i-012fadbdcda3dbeee]
aws_instance.backend: Refreshing state... [id=i-0221418043e9eadb1]
local_file.ansible_inventory: Refreshing state... [id=f4c9bbbb4ccbb482516e9c627b4d7c3850aefc51]
aws_iam_role_policy.backend: Refreshing state... [id=vmapp-backend-role:vmapp-backend-policy]
aws_iam_role_policy.worker: Refreshing state... [id=vmapp-worker-role:vmapp-worker-policy]
aws_sns_topic_subscription.email: Refreshing state... [id=arn:aws:sns:il-central-1:832767338129:vmapp-notifications:44fd2133-a5a6-42d6-a694-a17cdd8fd025]
local_file.ansible_group_vars_all: Refreshing state... [id=6609c7532a18d7be48aa6d339a4f705d04201f7c]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

backend_private_ip = "10.0.11.97"
db_password = <sensitive>
frontend_public_ip = "51.16.38.147"
rds_endpoint = "vmapp-db.crwyuessaqej.il-central-1.rds.amazonaws.com"
s3_bucket = "nginx-content-832767338129-il-central-1-an"
sns_topic_arn = "arn:aws:sns:il-central-1:832767338129:vmapp-notifications"
sqs_queue_url = "https://sqs.il-central-1.amazonaws.com/832767338129/vmapp-requests-queue"
worker_private_ip = "10.0.12.231"
```

## `terraform output`

```
backend_private_ip = "10.0.11.97"
db_password = <sensitive>
frontend_public_ip = "51.16.38.147"
rds_endpoint = "vmapp-db.crwyuessaqej.il-central-1.rds.amazonaws.com"
s3_bucket = "nginx-content-832767338129-il-central-1-an"
sns_topic_arn = "arn:aws:sns:il-central-1:832767338129:vmapp-notifications"
sqs_queue_url = "https://sqs.il-central-1.amazonaws.com/832767338129/vmapp-requests-queue"
worker_private_ip = "10.0.12.231"
```

## `ansible-playbook -i inventory.ini playbook.yml`

Clean idempotent run - nothing left to converge, `changed=0` on every host:

```
PLAY [Basic setup on every server] *********************************************

TASK [Gathering Facts] *********************************************************
ok: [vmapp-worker]
ok: [vmapp-backend]
ok: [vmapp-frontend]

TASK [common : Update all packages] ********************************************
ok: [vmapp-backend]
ok: [vmapp-worker]
ok: [vmapp-frontend]

TASK [common : Install basic packages] *****************************************
ok: [vmapp-backend]
ok: [vmapp-worker]
ok: [vmapp-frontend]

TASK [common : Create dedicated group to run the application] ******************
ok: [vmapp-backend]
ok: [vmapp-worker]
ok: [vmapp-frontend]

TASK [common : Create dedicated user to run the application] *******************
ok: [vmapp-backend]
ok: [vmapp-worker]
ok: [vmapp-frontend]

TASK [common : Create the application directory] *******************************
ok: [vmapp-backend]
ok: [vmapp-worker]
ok: [vmapp-frontend]

TASK [common : Create the app configuration directory (env files)] *************
ok: [vmapp-backend]
ok: [vmapp-frontend]
ok: [vmapp-worker]

PLAY [Install and configure nginx on the frontend] *****************************

TASK [Gathering Facts] *********************************************************
ok: [vmapp-frontend]

TASK [nginx : Install nginx] ***************************************************
ok: [vmapp-frontend]

TASK [nginx : Remove the default nginx site] ***********************************
ok: [vmapp-frontend]

TASK [nginx : Template the reverse-proxy config for the backend] ***************
ok: [vmapp-frontend]

TASK [nginx : Enable and start nginx] ******************************************
ok: [vmapp-frontend]

PLAY [Deploy the backend and worker services] **********************************

TASK [Gathering Facts] *********************************************************
ok: [vmapp-backend]
ok: [vmapp-worker]

TASK [app : Build the offline dependency wheelhouse on the control node (once)] ***
ok: [vmapp-backend -> localhost]

TASK [app : Mark the wheelhouse build as done] *********************************
ok: [vmapp-backend -> localhost]

TASK [app : Copy the application code to the server] ***************************
ok: [vmapp-worker]
ok: [vmapp-backend]

TASK [app : Copy the offline dependency wheelhouse to the server] **************
ok: [vmapp-backend]
ok: [vmapp-worker]

TASK [app : Create the venv and install dependencies (offline, no PyPI access needed)] ***
ok: [vmapp-worker]
ok: [vmapp-backend]

TASK [app : Template the environment file (RDS endpoint, DB creds, S3/SQS/SNS, region)] ***
ok: [vmapp-backend]
ok: [vmapp-worker]

TASK [app : Template the systemd unit] *****************************************
ok: [vmapp-backend]
ok: [vmapp-worker]

TASK [app : Enable and start the service] **************************************
ok: [vmapp-backend]
ok: [vmapp-worker]

PLAY RECAP *********************************************************************
vmapp-backend              : ok=16   changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
vmapp-frontend             : ok=12   changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
vmapp-worker               : ok=14   changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```
