# S3 bucket shells (name + tags only). Versioning, policies, website config, and
# lifecycle rules are SEPARATE resources in the AWS provider and are intentionally
# left unmanaged here — Terraform will not touch them. Add aws_s3_bucket_versioning /
# _policy / _website_configuration later if you want Terraform to manage those too.

resource "aws_s3_bucket" "avsecomhub_clients_images" {
  bucket = "avsecomhub-clients-s3-images"
  tags = {
    bucket = "avecomhub-clients"
  }
}

resource "aws_s3_bucket" "cdn_kaaikani" {
  bucket = "cdn.kaaikani.co.in"
}

resource "aws_s3_bucket" "daily_order_sales_reports" {
  bucket = "daily-order-sales-reports"
}

resource "aws_s3_bucket" "prabhasaaridesigns" {
  bucket = "prabhasaaridesigns"
  tags = {
    client = "Prabhas_Aaridesigns"
  }
}

resource "aws_s3_bucket" "vendure_images_backup" {
  bucket = "vendure-images-backup"
}

resource "aws_s3_bucket" "wow_vendure" {
  bucket = "wow-vendure"
}
