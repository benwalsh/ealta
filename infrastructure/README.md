# infrastructure/ — the optional cloud mirror

OpenTofu template for a station's **public web mirror**: the same Rails+React app the
device runs, on **ECS Express Mode** (Fargate + a managed ALB) behind **CloudFront**,
mirroring the device's detections into **RDS MySQL**. The device stays the source of
truth; the cloud is a lazy, read-mostly copy. Entirely **optional** — a station without
it is complete on its own hardware.

This directory ships with ealta as a **template**. You use it from your **fork**: your
station profile, your tfvars, your AWS account. Nothing here runs for the public repo.

```
 device ──push (to the ECS /ingest)──▶ ECS Express (Fargate) ──▶ RDS MySQL
                                              ▲
 public ──▶ your domain ──▶ CloudFront ───────┘   (cached, anonymous)
```

> **Runtime = ECS Express Mode**, AWS's successor to App Runner (closed to new customers
> 2026-04-30). Express Mode gives a Fargate service, a shared ALB, and a
> `*.ecs.<region>.on.aws` endpoint from one module — CloudFront fronts it for the custom
> domain. See `ecs.tf`. Requires the **AWS provider ≥ 6.34**; managed with **OpenTofu**.

## What it creates

- **ECR** repo for the image (the `Dockerfile` at the repo root builds it).
- **RDS MySQL** `db.t4g.micro`, private (only the ECS service can reach it), utf8mb4.
- **ECS Express Mode** service (`terraform-aws-modules/ecs//modules/express-service`)
  running the image on Fargate with a managed ALB; secrets from SSM; RDS reachable via
  the `<station>-ecs-tasks` security group.
- **CloudFront** + **ACM** (us-east-1) + **Route53** zone for your domain.
- **S3 + CloudFront** for the bird illustrations (`illustrations.tf`) — art served from
  a bucket, not baked into the image.
- **SES** for alert/digest email (`ses.tf`).
- **SSM SecureString** params — DB password, `SECRET_KEY_BASE`, ingest token (generated).
- **GitHub OIDC deploy role** (`github_oidc.tf`) — push-to-main deploys, no stored keys.

## Setup (from your fork)

```bash
cd infrastructure
cp terraform.tfvars.example terraform.tfvars   # station_name, domain_name, your repo
cp backend.hcl.example backend.hcl             # your state bucket + lock table names
```

Bootstrap the state bucket + lock table once (chicken-and-egg: the backend can't create
its own). Using the names you put in `backend.hcl`:

```bash
aws s3api create-bucket --bucket <yourstation>-tfstate --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1
aws s3api put-bucket-versioning --bucket <yourstation>-tfstate \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket <yourstation>-tfstate --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket <yourstation>-tfstate --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws dynamodb create-table --table-name <yourstation>-tflock --region eu-west-1 \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH

tofu init -backend-config=backend.hcl
```

## First deploy

Two ordering rules, both learned the hard way:

1. **Delegate DNS first**, or ACM cert validation hangs (the cert is DNS-validated
   against the Route53 zone this creates; until your registrar points at that zone's
   nameservers, ACM can't see the records — validation blocks, capped at 10m).
2. **Push the image to ECR before the full apply**, or the ECS service can't pull it
   and never goes healthy.

```bash
# 1. Create just the zone (for delegation) and ECR (to receive the image).
tofu apply -target=aws_route53_zone.main -target=aws_ecr_repository.app
tofu output route53_nameservers

# 2a. At your registrar, set those nameservers, then wait for propagation:
dig +short NS <your domain>        # should return the awsdns.* servers

# 2b. Build + push the FIRST image (linux/amd64 — Fargate is x86_64). Your committed
#     station profile rides along in the build context:
REPO=$(tofu output -raw ecr_repository_url)
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin "$REPO"
docker build --platform linux/amd64 -t "$REPO:latest" ..    # repo root is the context
docker push "$REPO:latest"

# 3. Full apply — cert validates (~1-2m) and the ECS service pulls the image + boots.
tofu apply

# On the device's .env (values from tofu outputs):
#   CLOUD_INGEST_URL   = $(tofu output -raw ingest_url)
#   CLOUD_INGEST_TOKEN = $(tofu output -raw cloud_ingest_token)
```

Then wire up **push-to-main deploys**: in your fork's GitHub settings
(Settings → Secrets and variables → Actions → **Variables**) set

| variable | value |
|---|---|
| `STATION_NAME` | your `station_name` |
| `AWS_REGION` | e.g. `eu-west-1` |
| `DEPLOY_ROLE_ARN` | `tofu output github_deploy_role_arn` |
| `ECR_REPO` | `tofu output ecr_repository_url` |

`.github/workflows/deploy.yml` is inert until `STATION_NAME` is set, so the public repo
never deploys; your fork deploys on every push to `main`.

## Alert emails (SES)

`ses.tf` sets up the alert path: a DKIM-verified domain identity, a custom MAIL FROM
(SPF), a DMARC record, and `ses:SendEmail` on the ECS task role. Two manual steps
`tofu apply` can't do:

1. **Wait for DKIM verification** (minutes to a few hours) — SES console → Identities.
2. **Request production access** — SES starts in the sandbox (verified addresses only).
   SES console → Account dashboard → Request production access (~1–2 days).

## Notes

- **Migrations** run on container boot via `bin/docker-entrypoint` (`db:prepare` is
  idempotent). RDS is private, so there's no local `rails db:migrate` path.
- **Illustrations**: sync your art to the bucket and set `illustrations.base_url` in
  your station.yml (or `ILLUSTRATIONS_BASE_URL` on the task) to the CloudFront domain —
  see `tofu output illustrations_base_url`.
- **Auth on the public mirror**: CloudFront strips cookies for cache hits, so the cloud
  site is effectively anonymous. Admin stays on the device.
