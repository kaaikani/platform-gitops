# Infrastructure as Code & Disaster Recovery — Engineering Report

**Platform:** Vendure multi-tenant e-commerce (4 storefronts + 2 client sites)
**Cloud:** AWS `ap-south-1` (Mumbai) · DR `ap-south-2` (Hyderabad) · Escape hatch GCP `asia-south1`
**Repo:** `kaaikani/platform-gitops`
**Report date:** 2026-08-12
**Audience:** engineering leadership / technical review

---

## Table of contents

1. [Executive summary](#1-executive-summary)
2. [Where we started — the problem statement](#2-where-we-started--the-problem-statement)
3. [Part A — Terraform: bringing AWS under code](#3-part-a--terraform-bringing-aws-under-code)
   - 3.1 [Strategy: import, never create](#31-strategy-import-never-create)
   - 3.2 [Repository & state architecture](#32-repository--state-architecture)
   - 3.3 [Inventory: what is under management](#33-inventory-what-is-under-management)
   - 3.4 [The ten engineering decisions that matter](#34-the-ten-engineering-decisions-that-matter)
   - 3.5 [The CI/CD pipeline](#35-the-cicd-pipeline)
   - 3.6 [What we deliberately do NOT manage](#36-what-we-deliberately-do-not-manage)
   - 3.7 [Production hardening delivered along the way](#37-production-hardening-delivered-along-the-way)
4. [Part B — Disaster Recovery](#4-part-b--disaster-recovery)
   - 4.1 [Threat model: three tiers of failure](#41-threat-model-three-tiers-of-failure)
   - 4.2 [Targets: RTO, RPO, and the cost ceiling](#42-targets-rto-rpo-and-the-cost-ceiling)
   - 4.3 [Tier 2 · Phase 1 — replicate the data](#43-tier-2--phase-1--replicate-the-data-seven-channels)
   - 4.4 [Tier 2 · Phase 2 — the blueprint that builds a region](#44-tier-2--phase-2--the-blueprint-that-builds-a-region)
   - 4.5 [The failover switch: one variable](#45-the-failover-switch-one-variable)
   - 4.6 [Tier 3 — the GCP cold escape hatch](#46-tier-3--the-gcp-cold-escape-hatch)
   - 4.7 [Detection: telling a bad deploy from a dead region](#47-detection-telling-a-bad-deploy-from-a-dead-region)
   - 4.8 [Continuous verification: the four robots](#48-continuous-verification-the-four-robots)
   - 4.9 [Drill history and what each one taught us](#49-drill-history-and-what-each-one-taught-us)
   - 4.10 [Drill isolation — how we test with production data safely](#410-drill-isolation--how-we-test-with-production-data-safely)
   - 4.11 [Fail-back](#411-fail-back)
5. [Cost](#5-cost)
6. [Open risks and roadmap](#6-open-risks-and-roadmap)
7. [Appendix — file map & command reference](#7-appendix--file-map--command-reference)

---

## 1. Executive summary

Over this programme we took a production e-commerce platform that existed **only as
clicks in the AWS console** and turned it into (a) a reproducible Terraform codebase and
(b) a tested, three-tier disaster-recovery capability that has been **proven by four live
drills**, including one that served real production data from a completely different cloud
provider.

**Before**

| | |
|---|---|
| Infrastructure definition | AWS console + `eksctl`, no code |
| Rebuild path if Mumbai is lost | **None.** Total data loss for anything not in an AWS snapshot |
| Copy of the database outside `ap-south-1` | **None** |
| Copy of container images outside `ap-south-1` | **None** |
| Copy of secrets outside `ap-south-1` | **None** |
| Detection of an outage | A human noticing the site is down |
| Detection of console drift | None |

**After**

| | |
|---|---|
| Infrastructure definition | 139 Terraform resource blocks across 3 root modules + 1 reusable module |
| Rebuild path | `terraform apply` rebuilds the entire platform in a second region — **17 minutes, 49 resources, zero errors**, verified 3× |
| Database outside `ap-south-1` | Continuous backup replication to `ap-south-2` (RPO 15–30 min) **and** nightly logical dumps in Google Cloud (RPO ≤ 24 h) |
| Images / secrets outside `ap-south-1` | ECR cross-region replication + Secrets Manager replicas; weekly mirror to GCP Artifact Registry & Secret Manager |
| Detection | Outage detector every 10 min that **classifies** deploy-failure vs regional-event; weekly DR readiness audit; nightly drift detection |
| Proven RTO | ~60–75 min for the full platform in `ap-south-2`; ~60–90 min for a full escape to GCP |
| Standing cost of the whole DR capability | **≈ $25–35 / month** (against a ~$472/mo platform bill) |

**The headline results**

- **Drill #3 (2026-08-03, AWS regional):** full platform rebuilt in Hyderabad in 17 minutes.
  HTTPS with a valid pre-issued certificate, 674 products served, all four storefronts
  rendering real product pages, ArgoCD bootstrapped from Git.
- **Escape drill #1 (2026-08-04, GCP):** 859 MB production dump imported into Cloud SQL in
  13m42s with zero errors — **1,099 products · 48,844 orders · 29,707 customers verified
  inside Google Cloud**, Vendure serving `/health` 200 and live shop-api queries from GKE,
  with AWS in no part of the request path.
- **18 concrete defects** were found and fixed by drilling — including two that were
  silently broken *in production* (Loki's IRSA trusted a deleted cluster; a missing secret
  key was crash-looping storefront replicasets).

---

## 2. Where we started — the problem statement

The platform was healthy and profitable, but every piece of it was a **snowflake**: created
by hand in the console or by one-off `eksctl` commands, with the only record of "how it is
configured" being the console itself.

That produces four specific business risks:

1. **No rebuild path.** If `ap-south-1` becomes unavailable, there is no artefact that
   describes what to build. Recovery means re-deriving the whole platform from memory,
   under pressure, at 3 AM.
2. **No review.** A change to production networking or IAM leaves no diff, no approver, no
   history. It is invisible until it breaks something.
3. **No drift signal.** Somebody deletes a database in the console; nothing notices.
   (This exact scenario nearly bit us — see [§3.4.10](#3410-the-test-db-1-lesson--state-is-not-reality).)
4. **The permission layer was undocumented.** The IRSA roles that let pods talk to S3, the
   ALB controller, Karpenter and Velero existed *only* as console objects. Even with a
   perfect cluster rebuild, nothing would have had permission to run.

Terraform was chosen not to "create infrastructure" — the infrastructure already existed
and was earning money — but to **describe** it, so that it can be reviewed, audited and, at
the worst possible moment, rebuilt.

---

## 3. Part A — Terraform: bringing AWS under code

### 3.1 Strategy: import, never create

The single most important decision of the programme:

> **Every Terraform run against production must be a no-op until we deliberately choose
> otherwise.**

We never wrote code and hoped it matched reality. For each resource the loop was:

```
1. Inspect the live object      aws <service> describe-... / console
2. Write HCL that matches it    byte-for-byte, including odd values
3. terraform import (or an import{} block)
4. terraform plan  →  MUST print "No changes"
5. Only then commit
```

Step 4 is the contract. A plan that shows changes after an import means the code does not
describe reality, and committing it would let CI "correct" production to match our
misunderstanding.

This discipline produced some deliberately ugly code, and that is correct:

```hcl
# terraform/rds_support.tf
description = "Time zone changes "   # trailing space is intentional — matches AWS exactly
```

A cosmetic cleanup there would have produced a real API call against the production
parameter group.

**Import history — the order we worked in** (each was a separate reviewed commit):

| # | Commit | Scope |
|---|---|---|
| 1 | `c131159` | S3 backend bootstrap + Test-vpc |
| 2 | `4fe055f`–`c9660ad` | Production VPC, subnets, route tables, IGW, associations |
| 3 | `69b33f8` | Security groups (bastion, RDS, EKS cluster, EKS node) |
| 4 | `c782103` | `vendure-prod-db` RDS instance |
| 5 | `0eedf8d` | Three EKS managed node groups |
| 6 | `7218d7b` | Standalone production EC2s (Delivery-partner, GK_Construction) |
| 7 | `51a3e53` | **Refactor** node groups into a module — zero downtime |
| 8 | `81f8f17`, `bfd4aef` | 6 S3 buckets, 7 ECR repositories |
| 9 | `4a15a1f` | Secrets Manager, SES, ACM |
| 10 | `4ddea52` | EKS IAM roles, RDS subnet/parameter groups |
| 11 | `5ce390e` | **The permission layer** — IRSA roles, OIDC providers, EKS addons |
| 12 | `4656cfa` | `prevent_destroy` guards, outputs, region variable |

### 3.2 Repository & state architecture

```
terraform/
├── *.tf                        ← ROOT MODULE: production, ap-south-1
│   ├── provider.tf  version.tf  variables.tf  outputs.tf
│   ├── vpc.tf  subnets.tf  igw.tf  route_table.tf  associations.tf
│   ├── security_groups.tf
│   ├── eks.tf  node_groups.tf  eks_addons.tf
│   ├── db.tf  rds_support.tf
│   ├── ec2.tf  ecr.tf  s3.tf  secrets.tf  ses.tf  acm.tf
│   ├── iam.tf  iam_irsa.tf              ← the permission layer
│   └── dr_*.tf                          ← DR replication, applied INTO prod state
│
├── modules/
│   └── node_group/             ← reusable EKS managed node group
│
├── live/
│   ├── aws-dr/                 ← ROOT MODULE: DR region, ap-south-2 (not normally applied)
│   └── gcp-escape/             ← ROOT MODULE: Google Cloud escape hatch
│
└── policies/*.json             ← IAM policy documents, byte-for-byte from IAM
```

**Three separate state files, on purpose:**

| Root module | Backend | Key | Applied |
|---|---|---|---|
| `terraform/` (prod) | S3 `kaaikani-tfstate-149536454380`, ap-south-1 | `prod/terraform.tfstate` | On every merge to `main`, by CI |
| `terraform/live/aws-dr/` | same bucket | `dr/terraform.tfstate` | **Only during a drill or a real failover** |
| `terraform/live/gcp-escape/` | **local, gitignored** | — | By hand |

State is encrypted at rest, uses S3 native locking (`use_lockfile = true` — no DynamoDB
table needed on Terraform ≥ 1.11), and the bucket itself is **cross-region replicated** to
`kaaikani-tfstate-dr-149536454380` in Hyderabad.

> **Why replicate the state bucket?** Without it there is a circular dependency in the
> disaster plan: step 1 of the runbook is `terraform init`, and the state it needs lives in
> the region that just died. The replica breaks the circle.

The GCP state is deliberately local and gitignored because it holds the scoped AWS transfer
key. That is safe because **escape day does not depend on that state**: every resource in
it is name-stable (buckets, registry, transfer jobs), so a fresh machine can re-import or
use them directly.

### 3.3 Inventory: what is under management

139 resource blocks in the production root module (more real objects than that, because
several use `for_each`), plus 3 module instances:

| Domain | Managed | Notes |
|---|---|---|
| **Networking** | 2 VPCs, 10 subnets, 4 route tables, 8 associations, 2 IGWs, 5 security groups | Prod VPC `10.10.0.0/16`, 3 AZs, public node subnets + private DB subnets |
| **Kubernetes** | 1 EKS cluster (v1.35), 3 managed node groups (via module), 5 pinned addons, Karpenter SQS interruption queue | `vendure-prod-cluster` |
| **Database** | 1 RDS MySQL 8.0.45 (`db.t3.medium`, gp3, encrypted), subnet group, parameter group | Deletion-protected, `prevent_destroy` |
| **Compute** | 3 EC2 instances | Two are client production servers with no other rebuild path |
| **Registry** | 7 ECR repositories | Immutable tags, scan-on-push |
| **Storage** | 8 S3 buckets | Bucket *shells* only — see §3.4.6 |
| **Secrets** | 8 Secrets Manager secrets | **Containers only, never values** — see §3.4.7 |
| **Email** | 6 SES identities, 2 configuration sets | Across two regions |
| **Certificates** | 7 ACM certificates | 6 prod (in use by the ALB) + DR set |
| **IAM** | 14 roles, 4 customer policies, 19 attachments, 4 inline policies, 2 OIDC providers, 1 scoped user | Includes the entire IRSA permission layer |
| **DNS** | 6 Cloudflare records | The six that point at the load balancer — the failover switch |
| **DR** | KMS key, backup vaults ×2, backup plan, RDS backup replication, ECR replication, S3 CRR ×4, secret replicas ×7 | See Part B |

The DR root module (`live/aws-dr/`) declares a further 28 blocks — a complete, standalone
region: VPC, 6 subnets, EKS cluster, node group, IRSA roles, OIDC provider, and a
point-in-time-restored RDS instance.

### 3.4 The ten engineering decisions that matter

These are the parts worth defending in a design review.

#### 3.4.1 `prevent_destroy` on everything irreplaceable

```hcl
# terraform/db.tf
resource "aws_db_instance" "prod_db" {
  lifecycle {
    prevent_destroy = true   # Terraform refuses to destroy/replace prod DB
  }
```

Applied to the production VPC, the EKS control plane, the RDS instance, and both client
EC2 servers. This is not paranoia — `prevent_destroy` turns a catastrophic apply into a
**failed plan**. Terraform will not proceed, and a human has to consciously remove the
guard. Combined with RDS `deletion_protection = true`, destroying the production database
requires two deliberate, reviewable code changes.

#### 3.4.2 A module + `moved{}` blocks — refactoring live infrastructure with zero downtime

Three near-identical node group resources became one reusable module:

```hcl
# terraform/node_groups.tf
module "app_ng" {
  source          = "./modules/node_group"
  node_group_name = "vendure-prod-app-ng-x86"
  instance_types  = ["t3a.medium"]
  ...
}
```

A naive refactor here **destroys three production node groups and creates three new ones** —
Terraform sees the old addresses disappear and new ones appear. The fix is a `moved` block,
which tells Terraform "this is the same object, only re-addressed":

```hcl
moved {
  from = aws_eks_node_group.prod_eks_ng
  to   = module.app_ng.aws_eks_node_group.this
}
```

Result: state was rewritten, **no AWS API call was made**, and no node restarted. This is
the technique that makes IaC refactoring safe on a live platform.

#### 3.4.3 `ignore_changes` on `desired_size` — respecting runtime ownership

```hcl
# terraform/modules/node_group/main.tf
lifecycle {
  ignore_changes = [scaling_config[0].desired_size]
}
```

`desired_size` is owned at **runtime** by Karpenter / the autoscaler / HPA, not by
Terraform. Without this, every apply would reset the node count to the number in the code
and terminate nodes the autoscaler had just added — CI fighting the autoscaler, in
production, on every merge.

`min_size` and `max_size` stay managed. Those are the *guardrails*, and guardrails belong
in code; the *current value* belongs to the runtime. This distinction — declare the
envelope, not the instantaneous state — is the general rule for anything autoscaled.

#### 3.4.4 Pinned addon versions

```hcl
# terraform/eks_addons.tf
aws-ebs-csi-driver = { version = "v1.56.0-eksbuild.1", ... }
coredns            = { version = "v1.13.2-eksbuild.3", ... }
```

An unpinned `aws_eks_addon` plans an upgrade to the latest version, and an addon upgrade
**restarts cluster-critical pods** (CNI, DNS, CSI). Pinning makes every version bump a
deliberate, reviewed, scheduled change in this file rather than a surprise inside an
unrelated merge.

Note the contrast with the DR module, which uses `data.aws_eks_addon_version.latest`. That
is correct there for the opposite reason: a DR build is a fresh create with no live
workload to disturb, so fresh defaults are the safer choice.

#### 3.4.5 Loud failure over silent drift

Two security groups on the `GK_Construction` instance are created and owned by the
in-cluster `aws-load-balancer-controller`. Importing them would be wrong — the controller
recreates them whenever the ALB is rebuilt. We reference them as **data sources** instead:

```hcl
# terraform/ec2.tf
data "aws_security_group" "alb_managed" {
  id = "sg-0ba5c7c8f76401d4b"   # k8s-vendureshared — ALB frontend SG
}
```

If the controller recreates the ALB, these IDs go stale and the **plan fails loudly**. That
is the intent: a visible signal beats silent drift. A resource that is owned by another
controller should never be co-owned by Terraform.

#### 3.4.6 S3 buckets as "shells"

Only bucket names and tags are managed. Versioning, policies, website configuration and
lifecycle rules are *separate resources* in the AWS provider, and we deliberately do not
declare them:

```hcl
resource "aws_s3_bucket" "cdn_kaaikani" {
  bucket = "cdn.kaaikani.co.in"
}
```

Terraform therefore cannot touch those settings. Where DR *needs* a sub-resource — bucket
versioning, which is mandatory for cross-region replication — we add exactly that one
resource, and nothing else. This is scope control: manage what you have verified, leave the
rest genuinely unmanaged rather than accidentally reset to defaults.

#### 3.4.7 Secrets: containers in code, values out-of-band

```hcl
# terraform/secrets.tf
resource "aws_secretsmanager_secret" "vendure_prod_database" {
  name = "vendure/prod/database"
  replica { region = var.dr_region }
}
```

We manage `aws_secretsmanager_secret` (the container) and never
`aws_secretsmanager_secret_version` (the value). **No credential ever enters Terraform
state**, which matters because state is a plaintext JSON document.

The elegant consequence: the `replica` block replicates at the *service* level, so AWS
keeps the Hyderabad copy in sync **including values that were updated out-of-band**. We get
DR for secrets we deliberately cannot see. This is the only copy of generated values
(`COOKIE_SECRET`, TOTP salts) outside `ap-south-1`.

`vendure/test/env` is deliberately not replicated — it has no DR value, and replicas cost
~$0.40/secret/month.

#### 3.4.8 Unmanaged by design: the EKS secrets-encryption KMS key

```hcl
data "aws_kms_key" "eks_secrets" {
  key_id = "559f6913-83a0-4d22-8d55-58dd0d60fc1e"
}
```

`encryption_config` is **immutable on a live EKS cluster** — the key can never be replaced.
Importing it would buy nothing and add a destroy-risk to state. We look it up instead. The
DR cluster creates its own key, which is correct because it is a fresh cluster.

#### 3.4.9 `import{}` blocks as reviewable, one-shot instructions

Rather than running `terraform import` from a laptop (invisible, unreviewable), imports are
declared in code and executed by CI:

```hcl
import {
  to = aws_iam_role.ebs_csi
  id = "AmazonEKS_EBS_CSI_DriverRole_VendureProd"
}
```

The import becomes part of the pull request: a reviewer sees exactly which live object is
being adopted. After the apply, the blocks are removed in a follow-up cleanup commit
(`4cb29c9`) — we learned in `0c27e01` that removing them *before* CI had applied them makes
Terraform plan to **create** the resources instead, which for IAM roles means name
collisions and for RDS support resources means a production-affecting change.

#### 3.4.10 The `test-db-1` lesson — state is not reality

The most instructive incident of the programme, preserved as a comment in `db.tf`.

A test database was deleted **in the console**. Terraform state still contained it. On the
next plan, Terraform saw a resource in state and code but not in AWS, and planned to
**recreate it** — a `db.t3.micro` at ~$15/mo, `publicly_accessible = true`, in a security
group with `3306` open to `0.0.0.0/0`.

Because CI auto-applies on merge to `main`, **any unrelated pull request would have
silently re-created a publicly reachable database.**

Two changes came out of it:

1. The resource block was removed from code entirely. With no object in AWS and no block in
   config, Terraform does nothing — no `state rm` needed.
2. **Nightly drift detection** was built (§3.5) so a console-side change is reported within
   24 hours instead of being discovered by an accidental revert.

> The general lesson, and the one worth repeating in review: *Terraform's job is to make
> reality match state. If state is wrong, Terraform confidently makes reality wrong.*

### 3.5 The CI/CD pipeline

Three workflows, all authenticating with **GitHub OIDC** — no long-lived AWS keys exist in
GitHub.

#### `terraform.yml` — plan on PR, apply on merge

```
PR opened      → init → fmt -check → validate → plan            (review the diff)
merged to main → init → fmt -check → validate → plan -out=tfplan → apply tfplan
```

The **saved-plan flow** is deliberate. `terraform apply tfplan` executes exactly the plan
produced seconds earlier in the same job; Terraform refuses a stale plan if anything
changed in between. This closes the classic "review one plan, apply a different one" gap
within a run.

*Known limitation, stated honestly:* the plan shown on the PR is not the plan applied on
merge — carrying a plan artefact across runs requires GitHub Environments, which is on the
roadmap.

#### `drift.yml` — nightly at 02:30 IST

```bash
terraform plan -detailed-exitcode     # 0 = clean, 1 = error, 2 = DRIFT
```

Exit code 2 opens a GitHub issue with the plan tail. This is the direct answer to the
`test-db-1` near-miss, and it also caught 4 of drill #1's findings.

#### `outage-detector.yml` — every 10 minutes

Covered in [§4.7](#47-detection-telling-a-bad-deploy-from-a-dead-region) — it is a DR
component, not a Terraform one.

### 3.6 What we deliberately do NOT manage

Being explicit about scope is part of the design. Currently out of scope, each for a stated
reason:

| Not managed | Why |
|---|---|
| Secret **values** | Would put plaintext credentials in state (§3.4.7) |
| S3 versioning / policies / lifecycle (except where DR needs them) | Verified-scope-only principle (§3.4.6) |
| ECR lifecycle policies | Separate resource; 3 repos currently have none — add deliberately |
| ALB / target groups / listeners | Owned by the in-cluster `aws-load-balancer-controller` |
| Karpenter EventBridge rules | Feed the imported SQS queue; import later |
| ~85 DNS records (DKIM, MX, SPF/DMARC, ACM validation) | Never change during failover; importing them is noise |
| `swadkerala.com` DNS | On GoDaddy nameservers, not reachable from the Cloudflare provider |
| 7 orphan OIDC providers from deleted clusters | Cleanup candidates, not adoption candidates |
| The unused duplicate ACM certs | Deletion candidates pending a decision |

### 3.7 Production hardening delivered along the way

Codifying infrastructure surfaces its defects. These were found by reading production
closely enough to describe it, and fixed as reviewed changes:

| Fix | Problem it solved |
|---|---|
| `backup_retention_period` 1 → 3 days | With 1 day, a Friday-evening data corruption discovered Monday morning has **no restore point**. 42% of deploys happen Fri–Sun. Data is 10 GB against a 20 GB free backup allowance → **cost $0**. |
| `max_allocated_storage = 30` | Storage was at ~50% of 20 GB. A full RDS volume makes the database **read-only** — production down. Autoscaling costs nothing unless it triggers. (Note: RDS storage can only grow, never shrink.) |
| Maintenance window → `tue:21:30–22:30 UTC` | Was Wednesday 08:06 IST — peak e-commerce hours. On a single-AZ instance, maintenance patching means a **reboot**. Moved to 03:00–04:00 IST. |
| Backup window → `20:00–20:30 UTC` | 01:30–02:00 IST, the established low-traffic slot. Must not overlap the maintenance window or AWS rejects it. |
| `log_output = FILE` | `slow_query_log = 1` was set but no slow-query log group existed in CloudWatch, because the default `TABLE` output writes to `mysql.slow_log` — consuming DB storage and exporting nothing. **We had slow-query logging that logged nowhere.** |
| Loki IRSA trust fixed | `LokiS3Role` trusted the OIDC provider of a **deleted** cluster. Loki's S3 log shipping had been silently broken in production. Found while documenting the role→ServiceAccount map. |
| `image_tag_mutability = IMMUTABLE` on ECR | A pushed tag cannot be overwritten — the image a deployment references cannot change under it |
| Kyverno/PodSecurity compliance for the dump CronJob | The first version (public image, root user, no CPU limit) was **blocked by production guardrails** — the guardrails working as designed |

---

## 4. Part B — Disaster Recovery

### 4.1 Threat model: three tiers of failure

The design starts from the observation that "disaster recovery" is three different problems
with three different answers, and conflating them is how organisations end up either
over-spending or unprotected.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ TIER 1 · A bad deploy / crash-looping pod          frequency: ~daily     │
│ Answer: roll back. kubectl rollout undo, git revert.                     │
│ THIS IS NOT DR. Failing over for this would be a self-inflicted outage.  │
├──────────────────────────────────────────────────────────────────────────┤
│ TIER 2 · ap-south-1 regional failure               frequency: rare       │
│ Answer: fail over to ap-south-2 (Hyderabad).                             │
│ Data pre-replicated; the region is rebuilt from code on demand.          │
│ Target RTO 45–90 min · RPO 15–30 min.                                    │
├──────────────────────────────────────────────────────────────────────────┤
│ TIER 3 · The AWS ACCOUNT dies                      frequency: very rare  │
│ (root compromise, billing lockout, org-wide IAM disaster)                │
│ Answer: escape to Google Cloud. Nothing in the recovery path is AWS.     │
│ Target RTO ~half a day · RPO ≤ 24 h.                                     │
└──────────────────────────────────────────────────────────────────────────┘
```

Tier 3 exists because **Tier 2 does not cover it**. Every AWS-internal DR mechanism —
cross-region replication, backup vaults, secret replicas — is worthless if the account
itself is gone. `ap-south-2` is a different region; it is the same account.

### 4.2 Targets: RTO, RPO, and the cost ceiling

| | Tier 2 (regional) | Tier 3 (account) |
|---|---|---|
| **RTO target** | 45–90 min | ~half a day |
| **RTO measured** | 17 min infrastructure; ~60–75 min full platform | ~2 h in drill incl. debugging; 60–90 min clean estimate |
| **RPO** | 15–30 min | ≤ 24 h |
| **Standing cost** | ~$15–25/mo | < $10/mo |
| **Posture** | Cold — code only, applied on demand | Cold — buckets + registry only |

**The explicit cost/RPO trade-offs we made, and why:**

| Rejected | Cost | Chosen | Cost | Reasoning |
|---|---|---|---|---|
| RDS cross-region **read replica** (RPO seconds, promote ~5 min) | ~$55/mo | **Backup replication** (RPO 15–30 min, restore 30–45 min) | ~$1–2/mo | 25–50× cheaper for a business that can absorb a 30-minute data window in a rare regional event |
| Multi-AZ RDS | ~2× instance cost | Single-AZ + 3-day backups | — | Same logic: no money for an idle standby |
| Warm GKE standby | ~$200/mo | Cold escape hatch | < $10/mo | A $200/mo standby contradicts every cost decision this platform runs on. Upgrade only if a client contract demands it. |

These are documented as *decisions with owners and dates*, not defaults. That is what makes
them defensible: we know exactly what we bought and what we chose not to buy.

**Region choice: `ap-south-2` (Hyderabad).** Keeps Indian customer and order data in-country
(DPDP Act), and offers EKS 1.35 + MySQL 8.0.45 on `db.t3.medium`/gp3 — matching production
exactly.

### 4.3 Tier 2 · Phase 1 — replicate the data (seven channels)

Phase 1's principle: **get every irreplaceable byte out of `ap-south-1` before worrying
about compute.** Compute is code; data is not.

| # | Asset | Mechanism | File | RPO | Cost/mo |
|---|---|---|---|---|---|
| 1 | **Database** | RDS automated-backup cross-region replication | `dr_rds.tf` | 15–30 min | ~$1–2 |
| 2 | **Terraform state** | S3 CRR → `kaaikani-tfstate-dr-…` | `dr_s3.tf` | seconds | ~$0 |
| 3 | **Product images** (3.56 GB) | S3 CRR → `cdn-kaaikani-dr-…` | `dr_s3.tf` | seconds | ~$0.11 total |
| 4 | **Client images / backups** | S3 CRR ×2 | `dr_s3.tf` | seconds | (incl. above) |
| 5 | **Container images** (23.4 GB) | ECR cross-region replication | `dr_ecr.tf` | per push | ~$2.34 |
| 6 | **Secrets** (7) | Secrets Manager replicas | `secrets.tf` | seconds | ~$2.80 |
| 7 | **Standalone EC2s** | AWS Backup, monthly + cross-region copy, 35-day retention | `dr_backup.tf` | ≤ 35 days | ~$8–12 |
| — | **Certificates** | Pre-issued ACM certs in `ap-south-2` | `dr_acm.tf` | n/a | $0 |
| — | **Email identities** | Pre-verified SES in `ap-southeast-1` | `dr_ses.tf` | n/a | $0 |

#### The two traps we hit, documented in the code

Both S3 CRR and ECR replication share a property that is easy to miss and fatal to assume
away:

> **They replicate NEW objects only.** Everything already in the bucket or registry stays
> where it is.

The code says so in a banner comment, and the backfill commands are written out at the
bottom of `dr_s3.tf`. **Drill #1 finding #7 proved the point the hard way: the DR container
registry was EMPTY on drill day.** All six repositories were backfilled, and "DR ECR repos
non-empty" is now check #3 in the weekly readiness workflow.

Two more details worth noting:

- **Delete-marker replication is disabled.** If someone deletes an object in production — by
  accident or by ransomware — the DR copy survives. Replication is a disaster copy, not a
  mirror.
- **The ECR filter list is explicit per repository, not a `vendure` prefix.** A prefix would
  also match `vendure-test`, adding 7.85 GB of test images with no DR value ($3.13 → $2.34/mo).

#### Pre-issued certificates and pre-verified email

Two things are regional and *slow to obtain*, so they are obtained now and left waiting:

- **ACM certificates** are regional; production's Mumbai certs are useless in Hyderabad, and
  issuing new ones during a failover adds 10–30 minutes of DNS validation to the RTO. Five
  certs sit pre-issued and validated in `ap-south-2`. Cost: $0.
  *(Finding #14: ACM validation tokens are per-account-per-domain, so the CNAMEs that
  validated the prod certs validated the DR certs too — they went ISSUED within seconds and
  no new DNS records were needed.)*
- **SES does not exist in `ap-south-2` at all.** Identities were pre-verified in
  `ap-southeast-1` (Singapore) with all 15 DKIM records automated through the Cloudflare
  provider. Verification needs DNS propagation of up to 72 hours — impossible to do during
  an outage. Cost: $0 standing; SES bills per email.

### 4.4 Tier 2 · Phase 2 — the blueprint that builds a region

`terraform/live/aws-dr/` is a complete, standalone root module for Hyderabad. It is
**not applied in normal operation** — that is the entire cost model. The code is the
"kitchen blueprint"; Phase 1 already delivered the ingredients.

It builds, in one apply:

- VPC `10.20.0.0/16` (deliberately non-overlapping with prod `10.10/16` and test `10.0/16`,
  so the VPCs could be peered later), 3 public + 3 private subnets across `ap-south-2a/b/c`
- EKS cluster `vendure-dr-cluster` on the same Kubernetes version as prod, with its own KMS
  key for secrets encryption
- One managed node group (2–6 nodes) — **no Karpenter**: an emergency environment wants the
  fewest moving parts
- The five EKS addons, in two ordered waves (see finding #8 below)
- The complete IRSA permission layer: OIDC provider + 5 roles, reusing the same policy
  documents as production from `terraform/policies/*.json`
- **The database, restored point-in-time from the replicated backups**

```hcl
# terraform/live/aws-dr/rds.tf
restore_to_point_in_time {
  source_db_instance_automated_backups_arn = var.replicated_backup_arn
  use_latest_restorable_time               = var.restore_use_latest
  restore_time                             = var.restore_use_latest ? null : var.restore_time
}
```

That second variable matters more than it looks. It is the difference between two very
different disasters:

- **Region loss** → `restore_use_latest = true` — take everything.
- **Data corruption / bad migration** → `restore_use_latest = false` + `restore_time =
  <before the event>` — a point-in-time restore, in a clean region, without touching the
  damaged production instance.

**IAM is global, so DR role names are prefixed** `vendure-dr-*` to avoid collision with
production. The four customer-managed policies (ALB controller, Velero, Loki, Karpenter)
already exist account-wide and are simply attached by ARN — no duplication.

### 4.5 The failover switch: one variable

The discovery that simplified the whole plan: **DNS was already well-structured.** Every
storefront apex resolves through a CNAME chain to the shared ALB (Cloudflare flattens the
apex CNAME, which is why `dig` shows A records). Nothing in DNS references the load
balancer's IP addresses.

So there is no A-record migration to perform. Exactly **six** records point at the ALB, and
everything else chains to one of them. Those six are under Terraform control, all driven by
a single variable:

```hcl
# terraform/dr_cloudflare.tf
variable "active_alb_dns_name" {
  description = "DNS name of the load balancer currently serving production."
  default     = "k8s-vendureshared-e797866abf-762060618.ap-south-1.elb.amazonaws.com"
}

resource "cloudflare_dns_record" "alb" {
  for_each = local.alb_records   # 6 records across 4 zones
  content  = var.active_alb_dns_name
  ttl      = 1                   # Cloudflare "Auto" ≈ 300s
}
```

**The entire customer-facing failover is:**

```bash
terraform apply -var "active_alb_dns_name=<DR ALB hostname>"
```

All five domains follow in one action. Cloudflare-side propagation is seconds; client TTL
is ~300 s.

Manual extras, honestly listed: `swadkerala.com` (GoDaddy nameservers — change by hand) and
the two standalone EC2 sites (restore from the DR backup vault, then update A records).

### 4.6 Tier 3 — the GCP cold escape hatch

**Scope decision (2026-08-03): a cold escape hatch, not a warm standby.**

What stands permanently in GCP `asia-south1` (Mumbai), for under $10/month:

| Piece | Mechanism | RPO |
|---|---|---|
| Database dumps | Nightly `mysqldump` CronJob in the prod cluster → S3 → **GCP Storage Transfer** daily pull → GCS | ≤ 24 h |
| Product images | GCP Storage Transfer, daily, from both image buckets | ≤ 24 h |
| Container images | Artifact Registry; weekly mirror workflow (GitHub Actions runs outside AWS) | ≤ 7 days |
| Secrets | Weekly re-sync into GCP Secret Manager | ≤ 7 days |
| Infrastructure code | This repo is on GitHub — outside AWS — including the GKE/Cloud SQL skeleton | live |

**Why a logical `.sql` dump and not an RDS snapshot:** SQL is the universal format,
restorable *outside* AWS. Snapshots are AWS-locked. On escape day an RDS snapshot is a
paperweight.

**The blast-radius design of the AWS→GCP bridge.** GCP holds exactly one AWS credential: an
IAM user scoped to read the dump bucket and the two image buckets, and nothing else.

```hcl
# terraform/dr_gcp_bridge.tf — the only AWS credential that lives in GCP
resource "aws_iam_user_policy" "gcp_transfer_read_dumps" {
  policy = jsonencode({ Statement = [{
    Effect   = "Allow"
    Action   = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
    Resource = [ /* dumps bucket + 2 image buckets */ ]
  }]})
}
```

If that key leaks, the attacker gets yesterday's database dump — which was already destined
for GCP anyway. The key is created out-of-band so it never enters Terraform state.

**Escape-day resources are a skeleton at `count = 0`:**

```hcl
resource "google_container_cluster" "escape" {
  count            = var.escape_active ? 1 : 0
  enable_autopilot = true      # no node management, fastest bring-up
}
```

One flag — `-var escape_active=true` — builds GKE Autopilot and Cloud SQL. Teardown is the
same flag set false.

The Cloud SQL `escape_db_suffix` variable deserves a mention as an example of applying a
lesson before it costs anything: Cloud SQL **quarantines deleted instance names for about a
week**. Rather than discovering that mid-drill, every drill bumps the suffix (`d1`, `d2`, …)
— a learning transferred proactively from the AWS drills.

#### Escape drill #1 — 2026-08-04 — PASSED

Proven end to end with real production data and **AWS in no part of the request path**:

- Cloud SQL instance built in 4m39s
- **859 MB nightly dump imported in 13m42s, zero errors**
- Data verified inside GCP: **1,099 products · 48,844 orders · 29,707 customers**
- Vendure on GKE Autopilot pulling from Artifact Registry: `/health` 200; shop-api returned
  675 products (Pomegranate, Guava…)
- ~2 hours wall clock including 7 live-debugged findings; clean-run estimate 60–90 min
- Cost: ~₹500 of trial credit

Seven findings were folded straight back into the procedure — the ones with teeth:

| # | Finding | Why it would have hurt |
|---|---|---|
| — | **The `escape_active` apply must include the AWS key variables.** All three transfer jobs are gated on the key being non-empty, so an apply without them reads as *"3 to destroy"* and silently tears down the replication feeding the whole plan | Escape day, one careless `yes` |
| 10 | **Only `wow_vendure` was being dumped** — the client storefront database `client_vendure` had **NO copy outside AWS**. Fixed in `db-dump-cronjob.yaml`; both databases now dump nightly | The client storefront would simply not exist after an escape |
| — | Dumps are single-database (no `CREATE DATABASE`) → target databases must be pre-created | Import fails with "No database selected" |
| — | **Import restores DATA but NOT GRANTS** | App crash-loops with `ER_DBACCESS_DENIED_ERROR 1044` |
| — | Cloud SQL users must be created with **POST, not PUT** (PUT grants only `USAGE`) | A powerless user that looks correct |
| — | GKE node service account needs `roles/artifactregistry.reader` | No pod can pull any image |
| — | **How to run the image was undocumented** — command, port 80, env — and had to be read off the live AWS cluster, *which would not exist on escape day* | The single most dangerous class of finding: a dependency on the thing you are escaping from |

That last one is the most valuable output of the whole drill programme. It is the kind of
gap no amount of design review finds — only actually running the procedure does.

### 4.7 Detection: telling a bad deploy from a dead region

`outage-detector.yml` runs every 10 minutes **from GitHub, outside AWS** — because a
watchman inside the building it guards is useless. Production's Prometheus, Grafana and
Alertmanager all die with the region.

The design point that makes it worth having:

> **A plain "site is down" alarm is worse than nothing.** It fires on every bad deploy
> (more than one a day here), you learn to ignore it, and then you miss the real one — or
> worse, somebody triggers a DR failover for something `git revert` fixes in three minutes.

So the detector checks the application and the infrastructure **separately, and
classifies**:

```
probe app twice, 60s apart (ignore transient blips)
        │
   still down?
        │
        ├── query EKS + RDS + ALB status via the AWS API
        │
        ├── all three answer normally  →  🟡 DEPLOY PROBLEM
        │      Issue: "AWS is FINE. Do NOT fail over. Check pods, roll back."
        │
        └── any unreachable/abnormal   →  🔴 POSSIBLE REGIONAL EVENT
               Issue: "A HUMAN must decide. Check AWS health dashboard.
                       Failover is IRREVERSIBLE. Not on a 10-minute blip."
```

The AWS credential step is marked `continue-on-error: true` — because AWS itself may be the
broken thing, and the detector must survive that to report it.

Cost: ~144 runs/month at ~40 s each ≈ 100 of GitHub's 2,000 free minutes.

**Neither alert auto-triggers anything.** Failover is behind a deliberate human gate
([§4.9](#the-human-gate)), because DB promotion is irreversible and split-brain is worse
than downtime.

### 4.8 Continuous verification: the four robots

The failure mode that kills DR programmes is not a bad design — it is a good design that
**silently rots**. Replication breaks in month three, nobody looks, and the gap is
discovered during the disaster. Drill #1 finding #7 (the empty DR registry) was exactly
this, discovered by luck.

Four scheduled workflows now prevent it:

| Workflow | Cadence | What it guarantees |
|---|---|---|
| `outage-detector.yml` | every 10 min | We learn about an outage, and know which *kind* it is |
| `dr-readiness.yml` | weekly, Mon 04:00 IST | **All nine DR channels are alive** — see below |
| `gcp-mirror.yml` | weekly, Mon 04:30 IST | GCP stays stocked with images + secrets without anyone remembering |
| `drift.yml` | nightly, 02:30 IST | Console-side changes are reported before a merge reverts them |

The readiness check's nine assertions — each one is a real failure mode we have either hit
or can name:

```
1. RDS backup replication status == "replicating"
2. All 7 secret replicas == "InSync"
3. All 6 DR ECR repos non-empty            ← drill #1 finding #7
4. EC2 DR vault has a recovery point < 40 days old
5. All DR ACM certificates == ISSUED
6. SES ap-southeast-1 identities verified for sending
7. Latest GCP S3→GCS transfer run == SUCCESS
8. GCP Artifact Registry non-empty
9. GCP Secret Manager holds ≥ 7 secrets
```

Any failure opens a GitHub issue titled *"🔴 DR readiness FAILED"* with the body: *"If a
real disaster hit today, recovery would be degraded or impossible. Fix before anything
else."*

Both cloud authentications are **keyless**: AWS via OIDC role assumption, GCP via Workload
Identity Federation. No service-account key file exists anywhere (the GCP org policy
forbids them — correctly).

### 4.9 Drill history and what each one taught us

Four drills. Each one was a real build of real infrastructure with real production data,
and each produced findings that no design review would have found.

#### Drill #1 — 2026-08-01 — infrastructure and database

Timeline: 14:30 start → **16:25 serving** → 16:29 teardown → 16:46 gone.

Proven: VPC / EKS / node group / addons / IRSA built in `ap-south-2`; RDS restored from the
replicated backup with **674 products and real order history**; secret replicas working;
drill isolation verified 5/5; Vendure server ×2 + worker + in-cluster Redis; `/health` 200
and live shop-api queries.

**14 findings, all fixed in code the same day.** The ones with the widest lessons:

| # | Finding | The general lesson |
|---|---|---|
| 1 | ACM is regional — prod certs useless in DR | Anything with a *lead time* must be pre-provisioned, not requested during an outage |
| 2 | EKS `CreateCluster` demands `compute` + `blockStorage` **and** `elasticLoadBalancing` together, or it 400s | **Prod never hit this because it was imported** — the third block lives invisibly in state as a computed attribute. Only a real create exposes it. *Imported infrastructure hides create-time requirements.* |
| 3 | An interrupted apply orphaned an in-flight RDS restore | State and reality diverge whenever an apply is killed; the fix needs `import` + `ignore_changes` |
| 5 | **The `t3a` (AMD) family does not exist in `ap-south-2`** — the entire prod fleet is `t3a` and none of it can launch in Hyderabad | *Region parity is an assumption, not a fact.* Verified alternatives: `t3.medium/large`, `m5.large`, `m7g.large`, `c6a.large` |
| 7 | **The DR container registry was EMPTY** | Replication semantics ("new objects only") must be verified, never assumed. Now a weekly automated check |
| 8 | `bootstrap_self_managed_addons = false` + addons after the node group = **CNI deadlock** — no CNI means nodes join NotReady forever, the node group never goes ACTIVE, and the addons waiting on it deadlock the apply | Boot-critical addons (`vpc-cni`, `kube-proxy`) must be created **before** the node group. Encoded as `aws_eks_addon.boot` |
| 12 | Chart bug: `worker.replicaCount | default 1` makes 0 impossible via values | A safety control that cannot be set to "off" is not a safety control |

#### Drill #2 — the edge

ALB ingress with the pre-issued `ap-south-2` certificates; EC2 restore from the DR vault
(Delivery-partner booted, nginx serving); discovered that the default `gp2` StorageClass is
legacy in-tree, so PVCs hang without a CSI StorageClass.

#### Drill #3 — 2026-08-03 — **full platform proven**

- Rebuild: **49 resources, 17 minutes, zero errors** — third consecutive clean build
- HTTPS edge: HTTP 200 through the ALB with a **valid pre-issued certificate**
  (CN=`kaaikani.co.in`), 674 products served over TLS
- **All four storefronts rendering real product pages** (44–200 KB SSR responses)
- ArgoCD installed fresh and synced from Git → Synced/Healthy
- Isolation verified again: MSG91 and SES untouched across all three drills

Four more findings, two of which were **production defects**:

| # | Finding | Impact |
|---|---|---|
| 16 | **Git values files carry STALE image tags.** `argocd-image-updater` writes live tags into the ArgoCD Application object, *not* into Git | In a failover, deploying "what Git says" ships old code. Real tags must be read from the prod cluster or the `deploy(...)` git log — **never trust the values files' tag fields.** A GitOps repo that is not the source of truth for image tags is a trap laid for your future self |
| 18 | **`GOOGLE_MAPS_API_KEY` is referenced by the storefront deployments but MISSING from the `prod/storefronts` secret** | This is the root cause of `CreateContainerConfigError` replicasets **stuck in PRODUCTION since 2026-07-30**. A DR drill diagnosed a live production bug |
| 15 | Storefront charts pin `node-group: storefront`; the DR single pool can't satisfy two selector values | Label one DR node accordingly |
| 17 | Each storefront chart expects its **own** secret name | Create all four at failover time |

#### The human gate

Failover is never automated. Three boxes must be ticked, out loud:

- [ ] `ap-south-1` impact confirmed on the AWS health dashboard — not just our cluster misbehaving
- [ ] Outage ongoing > 30 min with no AWS ETA, or AWS declares multi-hour impact
- [ ] You accept losing writes since the last replicated backup

> *"Say out loud: we are failing over, writes to Mumbai are dead to us from now."*
> Mixed-mode — some traffic in Mumbai, some in Hyderabad — is **forbidden**. Split-brain is
> worse than downtime.

### 4.10 Drill isolation — how we test with production data safely

This is the part of the programme I would most want scrutinised, because it is where a
drill can cause the very outage it is meant to prevent.

**The hazard:** the drill builds a copy of production *with production's data and keys*.
The infrastructure cannot touch production (separate region, separate state) — but a
faithfully-booted Vendure can **reach out** to real systems. The restored database holds
27,000+ real customers. With real keys, the abandoned-cart sweep alone could SMS and email
actual customers from a test environment.

**Four mandatory deviations** (`docs/dr/RUNBOOK.md` → DRILL MODE):

1. **Secrets: throwaway drill copies, never the real replicas.** `vendure/dr-drill/*` with
   `DUMMY-`-prefixed Razorpay / MSG91 / SMTP keys — the prefix means any leak is obvious in
   logs. Never run `PromoteReplicaToPrimary` on a real replica in a drill; it detaches live
   replication.
2. **Redis: in-cluster Helm Redis, never Redis Cloud.** Sharing Redis means the **DR worker
   consumes the production job queue**.
3. **Exclude `argocd-image-updater`** — two ArgoCDs pushing tag commits to one repo fight
   each other.
4. **Expect drill S3 uploads to land in production buckets** (the app policies point at the
   real CDN bucket) — keep test orders imageless, or delete the strays.

**And the rule that makes the rules real:**

> *A rule without a check is a hope.*

Isolation is **verified**, not assumed, at three points:

- **Pre-flight** — deploy with `worker.replicaCount: 0` (the worker is what consumes queues
  and sends messages); scale up only after: synced secrets show `DUMMY-` values and the DR
  DB host; `REDIS_HOST` is not `*.redis.cloud` (if it is → **ABORT**); no image-updater
  deployment exists.
- **During** — watch **production**, not the drill: worker job-processing rate unchanged (a
  drop means a foreign consumer on the queue), ALB 5xx flat, and **MSG91 + SES send metrics
  flat** — the ground truth for "did we message a real customer?"
- **Post-drill** — after teardown: `terraform plan` in prod prints *No changes*; the secret
  replica is still `InSync` (never promoted); RDS backup replication still `replicating`; no
  stray image-updater commits in the git log; no drill uploads in the CDN bucket.

Result across all three AWS drills: **isolation held every time**; MSG91 and SES were never
touched.

### 4.11 Fail-back

**Status: written outline, never drilled.** Stated plainly because that is the honest
status.

The asymmetry is deliberate and worth explaining: fail-back is **less urgent** than failover
(the business is running in Hyderabad; Mumbai's return can wait days) but **more dangerous**
(two databases have now diverged, and choosing wrong loses every order taken during the
outage).

Principles:

1. **No hurry.** Fail back on a quiet weekday night, planned, with the document open.
2. **The DR database is now the truth.** Every order taken during the outage exists *only*
   in Hyderabad. Mumbai's old database is **history, not truth.**
3. One-way traffic switch again — no mixed mode.

The dangerous step is the data return: dump the DR database in a maintenance window,
restore into a **fresh** Mumbai instance (never over the old one — keep it as evidence),
verify row counts and latest orders match, then flip `active_alb_dns_name` back. Afterwards,
RDS backup replication must be **re-created** (it breaks when the source dies); S3 CRR
survives on its own.

Known unknowns to answer in the first fail-back drill: exact cut-over downtime (estimated
15–45 min at current data size), whether the standalone EC2s were ever failed over at all,
and switching SES sending back from Singapore.

---

## 5. Cost

**Standing DR cost, from the figures documented in the code:**

| Item | $/month |
|---|---|
| RDS backup replication to ap-south-2 | 1–2 |
| DR KMS key | ~1 |
| ECR cross-region replication (23.4 GB) | 2.34 |
| S3 cross-region replication (~4.5 GB) | ~0.11 |
| Secrets Manager replicas (7 × ~$0.40) | ~2.80 |
| AWS Backup, 2 EC2s, both regions | 8–12 |
| ACM certificates (DR) | 0 |
| SES second region (standing) | 0 |
| GitHub Actions (all four workflows) | 0 — within the free tier |
| **AWS DR subtotal** | **≈ $15–20** |
| GCP escape hatch (buckets + registry + transfers) | < 10 |
| **Total DR capability** | **≈ $25–30** |

Plus **~$10–15 per drill day**, and $0 for the DR compute that does not exist until it is
needed.

Measured against a ~$472/month platform bill, the entire three-tier DR capability costs
roughly **5–6% of the platform**. The rejected alternatives (read replica + warm GKE
standby) would have cost ~$255/month — **over half the platform bill** — for a better RPO
than the business needs.

An important sizing note on estimating discipline: S3 DR storage was initially estimated at
$5–8/month. Actually measuring the buckets gave 4.5 GB → **$0.11/month**. A 50× error, in
the direction that makes you skip the work. *Measure before you budget.*

---

## 6. Open risks and roadmap

Stated openly — an honest gap list is more useful than a clean one.

### Should be fixed soon

| # | Risk | Detail |
|---|---|---|
| 1 | **`GOOGLE_MAPS_API_KEY` missing from the `prod/storefronts` secret** | Drill #3 finding #18 — actively causing `CreateContainerConfigError` in **production** since 2026-07-30. Adding it to the ap-south-1 secret auto-syncs the replica |
| 2 | **CI role holds `AdministratorAccess`** | `github-actions-terraform` was imported as-is. It should be scoped to the services Terraform actually manages |
| 3 | **`bastion-sg` allows SSH from `0.0.0.0/0`** | Plus an all-ports rule for a single `/32` in the node SG. Both were imported as-found; both deserve a deliberate tightening change |
| 4 | **Redis Cloud region is UNKNOWN** | If it is hosted in `ap-south-1` it shares our failure domain, which would silently invalidate part of the Tier 2 plan. A one-hour investigation |
| 5 | **SES `ap-southeast-1` is in sandbox mode** | 200 emails/day, verified recipients only. Production access is a one-time request with ~24 h AWS review — do it *before* it is needed |

### Planned work

| # | Item | Value |
|---|---|---|
| 6 | **Drill fail-back** | The only major procedure never executed. Everything else in this report has been proven by running it |
| 7 | Cross-run plan artefacts via GitHub Environments | Closes the last review-vs-apply gap in CI |
| 8 | `swadkerala.com` DNS → Cloudflare | Removes the one manual step from the failover switch and unblocks its DR certificate |
| 9 | Clean up 7 orphan OIDC providers + 2 unused ACM certs | Reduces IAM surface and console noise |
| 10 | Retire the `test` VPC / `test_ec2` / `test_sg` | `test_sg` opens 22, 80, 443 and **3306** to `0.0.0.0/0`. It costs money and carries risk for no production value |
| 11 | ECR lifecycle policies on the 3 repos lacking them | Registry storage grows unbounded today |
| 12 | Cloud SQL Private IP / Auth Proxy for the escape path | GKE Autopilot rotates node egress IPs, so a `/32` allowlist breaks mid-run |
| 13 | Monitoring stack in the DR plan | Metric history is currently accepted-loss; the *stack itself* has not been drilled |

### Accepted, with reasons

| Gap | Why it is accepted |
|---|---|
| Monitoring history lost on failover | Fresh PVCs; metric history is not business data |
| Customer email degraded during failover | Mitigated by the pre-verified Singapore region; the last mile is the sandbox exit (#5) |
| RPO 15–30 min for the database | The deliberate $55/mo → $2/mo trade in §4.2 |
| Standalone EC2 RPO up to 35 days | Application code redeploys from GitHub; only the server *setup* (nginx, pm2, TLS) is unrecoverable, and it rarely changes |
| VB.NET desktop tools hardcode the DB endpoint | Manual connection-string update during failover; documented in the runbook |

---

## 7. Appendix — file map & command reference

### File map

| Path | What it is |
|---|---|
| `terraform/*.tf` | Production root module, `ap-south-1` |
| `terraform/dr_*.tf` | Phase-1 DR replication, applied into the **prod** state |
| `terraform/modules/node_group/` | Reusable EKS managed node group |
| `terraform/live/aws-dr/` | DR root module — the ap-south-2 blueprint |
| `terraform/live/gcp-escape/` | GCP escape hatch (local state) |
| `terraform/policies/*.json` | IAM policy documents, byte-for-byte from IAM |
| `docs/dr/RUNBOOK.md` | The failover runbook + drill mode + isolation checks |
| `docs/dr/GCP-ESCAPE.md` | Escape-hatch design and escape-day procedure |
| `docs/dr/FAILBACK.md` | Fail-back outline (not yet drilled) |
| `environments/dr/drill-values.yaml` | Helm overlay that makes a drill inert |
| `environments/production/db-dump-cronjob.yaml` | Nightly logical dump of **both** databases → S3 |
| `.github/workflows/terraform.yml` | Plan on PR, saved-plan apply on merge |
| `.github/workflows/drift.yml` | Nightly drift detection |
| `.github/workflows/dr-readiness.yml` | Weekly 9-point DR channel audit |
| `.github/workflows/gcp-mirror.yml` | Weekly image + secret mirror to GCP |
| `.github/workflows/outage-detector.yml` | 10-minute classified outage detection |

### The five commands that matter

```bash
# 1. Look up the replicated backup ARN (first step of any DR build)
aws rds describe-db-instance-automated-backups --region ap-south-2 \
  --query 'DBInstanceAutomatedBackups[0].DBInstanceAutomatedBackupsArn' --output text

# 2. Build the entire DR region (~25 min; EKS ~12 min and RDS ~15-20 min run in parallel)
cd terraform/live/aws-dr
terraform apply -var "replicated_backup_arn=$BACKUP_ARN"
#   corruption event instead of region loss? add:
#   -var restore_use_latest=false -var restore_time=2026-XX-XXTXX:XX:XXZ

# 3. If Mumbai's S3 is down, init against the replicated state bucket
terraform init -reconfigure \
  -backend-config="bucket=kaaikani-tfstate-dr-149536454380" \
  -backend-config="region=ap-south-2"

# 4. THE FAILOVER SWITCH — all five domains, one action
cd terraform
terraform apply -var "active_alb_dns_name=<DR ALB hostname>"

# 5. Escape to Google Cloud (both AWS key vars are MANDATORY — see §4.6)
cd terraform/live/gcp-escape
terraform apply -var escape_active=true -var escape_db_suffix=dN \
  -var aws_transfer_access_key_id=... -var aws_transfer_secret_key=...
```

---

## Closing note

Two things in this report are worth more than the infrastructure itself.

The first is that **every number here was measured, not estimated.** 17 minutes, 49
resources, 859 MB, 13m42s, 48,844 orders. A DR plan that has never been executed is a
document; one that has been executed four times is a capability.

The second is that **the drills found production bugs.** Loki's log shipping had been
silently broken. Storefront replicasets had been stuck since July. A whole tenant database
had no copy outside AWS. None of these were found by monitoring or by review — they were
found by trying to rebuild the platform somewhere else and watching what failed.

That is the real return on this work: not the DR region, but the fact that we now know what
we actually run.
