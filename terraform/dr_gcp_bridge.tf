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
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
      Resource = [aws_s3_bucket.escape_dumps.arn, "${aws_s3_bucket.escape_dumps.arn}/*"]
    }]
  })
}

# Key is created OUT-OF-BAND deliberately (aws iam create-access-key --user-name
# gcp-storage-transfer) so the secret never enters Terraform state; it is set as
# a variable in terraform/live/gcp-escape/ (marked sensitive there).
