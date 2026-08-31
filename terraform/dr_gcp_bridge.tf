# AWS side of the GCP escape hatch (docs/dr/GCP-ESCAPE.md): the dump landing
# zone GCP pulls from, and the ONLY AWS credential GCP ever holds -- an IAM
# user that can read the dump bucket and nothing else. If this key leaks, the
# blast radius is yesterday's database dump (already destined for GCP anyway).

resource "aws_s3_bucket" "escape_dumps" {
  bucket = "kaaikani-escape-dumps"
  tags   = { Project = var.project, Purpose = "gcp-escape" }
}

resource "aws_s3_bucket_lifecycle_configuration" "escape_dumps" {
  bucket = aws_s3_bucket.escape_dumps.id
  rule {
    id     = "expire-7d"
    status = "Enabled"
    filter {}
    expiration {
      days = 7 # GCS keeps 30d; S3 is just the hop
    }
  }
}

resource "aws_s3_bucket_public_access_block" "escape_dumps" {
  bucket                  = aws_s3_bucket.escape_dumps.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_user" "gcp_transfer" {
  name = "gcp-storage-transfer"
  tags = { Project = var.project, Purpose = "gcp-escape" }
}

resource "aws_iam_user_policy" "gcp_transfer_read_dumps" {
  name = "read-escape-dumps-only"
  user = aws_iam_user.gcp_transfer.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
      # dumps + the product-image buckets: without the images in GCP, an
      # account-death escape resurrects storefronts with empty photo frames
      # 2026-08-13: extended from 3 buckets to ALL production buckets. The
      # earlier list covered only what the app's s3.bucket values pointed at,
      # which silently left four production buckets with no copy outside AWS:
      # the image backup set (5,682 objects), the prabhasaaridesigns bucket,
      # the order-report exports and wow-vendure. Regional DR replicates them
      # via S3 CRR to ap-south-2; account-level DR did not replicate them at
      # all, so an account loss took them permanently.
      # Still read-only, still one bucket list, still no write anywhere.
      Resource = [
        aws_s3_bucket.escape_dumps.arn, "${aws_s3_bucket.escape_dumps.arn}/*",
        "arn:aws:s3:::cdn.kaaikani.co.in", "arn:aws:s3:::cdn.kaaikani.co.in/*",
        "arn:aws:s3:::avsecomhub-clients-s3-images", "arn:aws:s3:::avsecomhub-clients-s3-images/*",
        "arn:aws:s3:::vendure-images-backup", "arn:aws:s3:::vendure-images-backup/*",
        "arn:aws:s3:::prabhasaaridesigns", "arn:aws:s3:::prabhasaaridesigns/*",
        "arn:aws:s3:::daily-order-sales-reports", "arn:aws:s3:::daily-order-sales-reports/*",
        "arn:aws:s3:::wow-vendure", "arn:aws:s3:::wow-vendure/*",
        # Terraform state. ap-south-2 replicates it to break a circular
        # dependency (state lives in the region you need it to rebuild). GCP
        # does not have that problem -- the escape hatch keeps its own state --
        # but the file is the only record of what the AWS platform WAS, and the
        # .tf code on GitHub does not carry resource ids or imported settings.
        # ⚠ This state contains PLAINTEXT SECRETS. Its GCS copy is private with
        # uniform bucket-level access and must stay that way.
        "arn:aws:s3:::kaaikani-tfstate-149536454380", "arn:aws:s3:::kaaikani-tfstate-149536454380/*",
      ]
    }]
  })
}

# Key is created OUT-OF-BAND deliberately (aws iam create-access-key --user-name
# gcp-storage-transfer) so the secret never enters Terraform state; it is set as
# a variable in terraform/live/gcp-escape/ (marked sensitive there).
