# DR-readiness: ACM certificates PRE-ISSUED in ap-south-2 (drill #1 finding #1).
# ACM is regional -- the prod certs are useless in Hyderabad, and issuing certs
# DURING a failover would add 10-30 min of DNS-validation wait to the RTO.
# Certs are free; these sit validated and ready for the DR ALB.
#
# Mirrors the prod cert set (acm.tf) with one exception: swadkerala.com is on
# GoDaddy NS, so we cannot create its validation record from the Cloudflare
# provider -- issuing it would hang the apply waiting for validation. It gets a
# cert only after its DNS moves to Cloudflare (tracked in the runbook).

locals {
  dr_cert_domains = {
    southmithai_wildcard = { domain = "*.southmithai.com", zone = "southmithai.com" }
    southmithai          = { domain = "southmithai.com", zone = "southmithai.com" }
    prabhasaari_wildcard = { domain = "*.prabhasaaridesigns.com", zone = "prabhasaaridesigns.com" }
    kaaikanistore        = { domain = "kaaikanistore.com", zone = "kaaikanistore.com" }
    kaaikani             = { domain = "kaaikani.co.in", zone = "kaaikani.co.in" }
  }
}

resource "aws_acm_certificate" "dr" {
  provider = aws.dr
  for_each = local.dr_cert_domains

  domain_name       = each.value.domain
  validation_method = "DNS"

  tags = { Project = var.project, Purpose = "dr" }

  lifecycle {
    create_before_destroy = true
  }
}

# NO validation records needed (drill #1 finding #14): ACM validation tokens
# are per-account-per-domain, so the CNAMEs that validated the PROD certs
# (already in each Cloudflare zone) validate the DR-region certs too. All 5
# went ISSUED within seconds of creation. Attempting to create "new" records
# 400s with Cloudflare error 81053 (record already exists).

output "dr_certificate_arns" {
  description = "Pre-issued ap-south-2 certs for the DR ALB ingress annotations"
  value       = { for k, c in aws_acm_certificate.dr : k => c.arn }
}
