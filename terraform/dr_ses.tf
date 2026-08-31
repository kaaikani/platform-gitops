# DR-readiness: SES identities PRE-VERIFIED in ap-southeast-1 (Singapore).
# SES does not exist in ap-south-2, and user decision 2026-08-03: customer
# email is business-critical during a failover. Verifying identities takes
# DNS DKIM records + up to 72h propagation -- far too slow to do DURING an
# outage, so they are verified NOW and sit ready. $0 standing (SES bills
# per email only).
#
# All 5 prod identities live on Cloudflare zones we manage, so DKIM is fully
# automated here. Config sets (delivery logging) deliberately not mirrored --
# sending works without them; add later if failover observability demands it.
#
# NOTE: the new region starts in SANDBOX mode (200 emails/day, verified
# recipients only). Production access is requested via:
#   aws sesv2 put-account-details --region ap-southeast-1 \
#     --production-access-enabled --mail-type TRANSACTIONAL \
#     --website-url https://kaaikani.co.in ...
# (one-time, ~24h AWS review -- tracked in the runbook.)

provider "aws" {
  alias  = "ses_dr"
  region = "ap-southeast-1"
}

locals {
  ses_dr_identities = {
    "kaaikani.co.in"         = "kaaikani.co.in"
    "kaaikanistore.com"      = "kaaikanistore.com"
    "southmithai.com"        = "southmithai.com"
    "prabhasaaridesigns.com" = "prabhasaaridesigns.com"
    "avsecomhub.com"         = "avsecomhub.com"
  }
}

resource "aws_sesv2_email_identity" "dr" {
  provider = aws.ses_dr
  for_each = local.ses_dr_identities

  email_identity = each.key
  tags           = { Project = var.project, Purpose = "dr" }
}

# 3 DKIM CNAMEs per domain. Token values differ per REGION (unlike ACM), so
# these records are new, no collision with the ap-south-1 DKIM records.
resource "cloudflare_dns_record" "ses_dr_dkim" {
  for_each = {
    for pair in flatten([
      for domain, zone in local.ses_dr_identities : [
        for i in range(3) : {
          key    = "${domain}-${i}"
          domain = domain
          zone   = zone
          token  = aws_sesv2_email_identity.dr[domain].dkim_signing_attributes[0].tokens[i]
        }
      ]
    ]) : pair.key => pair
  }

  zone_id = local.cloudflare_zone_ids[each.value.zone]
  name    = "${each.value.token}._domainkey.${each.value.domain}"
  type    = "CNAME"
  content = "${each.value.token}.dkim.amazonses.com"
  ttl     = 1
  proxied = false
}
