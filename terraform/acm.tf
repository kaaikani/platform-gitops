# ACM certificates (Amazon-issued, DNS-validated — no private keys, safe to manage).
# Only the 6 certs IN USE by the production ALB are imported here.
# NOT imported (unused — cleanup candidates, decide keep vs delete):
#   - kaaikani.co.in    cert cd633af5-490d-4175-96fe-6912c2225c3c  (duplicate, InUse=false)
#   - *.avsecomhub.com  cert 84533554-2d28-4551-8ede-dee89b2ad15c  (InUse=false)

resource "aws_acm_certificate" "southmithai_wildcard" {
  domain_name       = "*.southmithai.com"
  validation_method = "DNS"
}

resource "aws_acm_certificate" "southmithai" {
  domain_name       = "southmithai.com"
  validation_method = "DNS"
}

resource "aws_acm_certificate" "swadkerala" {
  domain_name       = "swadkerala.com"
  validation_method = "DNS"
}

resource "aws_acm_certificate" "prabhasaaridesigns_wildcard" {
  domain_name       = "*.prabhasaaridesigns.com"
  validation_method = "DNS"
  tags = {
    "vendure-client" = "prabhasaaridesigns.com"
  }
}

resource "aws_acm_certificate" "kaaikanistore" {
  domain_name       = "kaaikanistore.com"
  validation_method = "DNS"
}

resource "aws_acm_certificate" "kaaikani" {
  domain_name       = "kaaikani.co.in"
  validation_method = "DNS"
}
