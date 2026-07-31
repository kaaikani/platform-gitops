# DR Phase 1, Steps 3 + 4 -- S3 cross-region replication (CRR).
#
# ############################################################################
# ⚠️  CRR PUTHU OBJECT AH MATTUM REPLICATE PANNUM.
#     Ippo bucket la irukkura object ellame ap-south-1 la ye irukkum -- automatic
#     ah pogaadhu. Adha kondu poga S3 Batch Replication job (one-time) run
#     pannanum. Adhu illama "namma images DR la safe" nu nenaikradhu THAPPU.
#     Command indha file oda kadaisila comment la irukku.
# ############################################################################
#
# Size alandhu paathadhu (2026-07-30): mothham ~4.5 GB, so DR storage ~11 cents/mo.
# Mudhalla $5-8 nu estimate panninom -- 50x thappu. Alandhu paathadhu nalladhu.

locals {
  # source bucket -> DR bucket + storage class. Explicit ah vechirukom (compute
  # panna la) -- rename aana silent ah thappu destination ku point aaga koodadhu.
  #
  # 0 GB bucket (wow-vendure, daily-order-sales-reports) and prabhasaaridesigns
  # (0.02 GB) skip -- replicate panna edhuvum illa.
  dr_replicated_buckets = {
    # State bucket. Idhu replicate pannala na, ap-south-1 poidhucha DR runbook
    # oda MUDHAL step ("terraform apply") ye block -- state antha region la
    # dhaan irukku. Circular dependency.
    "kaaikani-tfstate-149536454380" = {
      dr_bucket = "kaaikani-tfstate-dr-149536454380"
      # STANDARD, IA illa: file chinnadhu aana adikkadi maarum. STANDARD_IA la
      # object ku 30-naal minimum billing irukku, so adhu inkum cost aagum.
      storage_class = "STANDARD"
    }

    # 3.56 GB -- customer-facing product images. Idhu illama failover pannina
    # storefront la images ellame broken ah varum.
    "cdn.kaaikani.co.in" = {
      dr_bucket     = "cdn-kaaikani-dr-149536454380"
      storage_class = "STANDARD_IA" # DR copy, failover time la mattum padikkum
    }

    "vendure-images-backup" = {
      dr_bucket     = "vendure-images-backup-dr-149536454380"
      storage_class = "STANDARD_IA"
    }

    "avsecomhub-clients-s3-images" = {
      dr_bucket     = "avsecomhub-clients-images-dr-149536454380"
      storage_class = "STANDARD_IA"
    }
  }
}

# --- Source side: versioning. CRR ku idhu MANDATORY, illama rule create aagaadhu.
# Note: s3.tf la bucket "shells" mattum manage pannurom; versioning thani
# resource, so bucket ah import pannaama ye idha add panna mudiyum. Adhaan
# tfstate bucket (Terraform la manage pannaadha adhu) kooda indha list la varum.
resource "aws_s3_bucket_versioning" "source" {
  for_each = local.dr_replicated_buckets

  bucket = each.key
  versioning_configuration {
    status = "Enabled"
  }
}

# --- Destination side: DR region buckets + versioning.
resource "aws_s3_bucket" "dr" {
  provider = aws.dr
  for_each = local.dr_replicated_buckets

  bucket = each.value.dr_bucket

  tags = {
    Project = var.project
    Purpose = "dr-replica-of-${each.key}"
  }
}

resource "aws_s3_bucket_versioning" "dr" {
  provider = aws.dr
  for_each = local.dr_replicated_buckets

  bucket = aws_s3_bucket.dr[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

# DR copy ku public access kandippa vendam.
resource "aws_s3_bucket_public_access_block" "dr" {
  provider = aws.dr
  for_each = local.dr_replicated_buckets

  bucket                  = aws_s3_bucket.dr[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Replication IAM role. S3 service idha assume panni object ah copy pannum.
resource "aws_iam_role" "s3_replication" {
  name        = "vendure-s3-crr-role"
  description = "Assumed by S3 to replicate prod buckets into ${var.dr_region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = var.project
    Purpose = "dr"
  }
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "vendure-s3-crr"
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = [for b in keys(local.dr_replicated_buckets) : "arn:aws:s3:::${b}"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
        ]
        Resource = [for b in keys(local.dr_replicated_buckets) : "arn:aws:s3:::${b}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
        ]
        Resource = [for b in local.dr_replicated_buckets : "arn:aws:s3:::${b.dr_bucket}/*"]
      },
    ]
  })
}

# --- Replication rules.
resource "aws_s3_bucket_replication_configuration" "source" {
  for_each = local.dr_replicated_buckets

  # Versioning rendu pakkathilum ON aanadhukku appuram dhaan rule create aaganum.
  depends_on = [
    aws_s3_bucket_versioning.source,
    aws_s3_bucket_versioning.dr,
  ]

  role   = aws_iam_role.s3_replication.arn
  bucket = each.key

  rule {
    id     = "dr-${var.dr_region}"
    status = "Enabled"

    filter {} # bucket la irukkura ellame

    # Disabled: source la delete marker vandha DR la um delete aaga koodadhu.
    # Thappa delete pannina, illa ransomware vandha, DR copy thaan kaappaathum.
    delete_marker_replication {
      status = "Disabled"
    }

    destination {
      bucket        = aws_s3_bucket.dr[each.key].arn
      storage_class = each.value.storage_class
    }
  }
}

# ############################################################################
# APPLY AANADHUKKU APPURAM -- pazhaya object ah backfill pannunga (one-time).
# Idhu pannaadha varaikum DR bucket la puthu object mattum irukkum.
#
#   aws s3 sync s3://cdn.kaaikani.co.in \
#               s3://cdn-kaaikani-dr-149536454380 \
#               --source-region ap-south-1 --region ap-south-2
#
#   aws s3 sync s3://vendure-images-backup \
#               s3://vendure-images-backup-dr-149536454380 \
#               --source-region ap-south-1 --region ap-south-2
#
#   aws s3 sync s3://avsecomhub-clients-s3-images \
#               s3://avsecomhub-clients-images-dr-149536454380 \
#               --source-region ap-south-1 --region ap-south-2
#
# 4.5 GB dhaan, so `aws s3 sync` podhum -- S3 Batch Replication job thevai illa.
# tfstate bucket ku sync vendam: adutha `terraform apply` la puthu version
# ezhudhum, adhu automatic ah replicate aagum.
# ############################################################################
