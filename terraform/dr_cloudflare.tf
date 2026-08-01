# DR Phase 1, Step 7 -- Cloudflare DNS: the failover switch.
#
# Discovery (2026-07-31): DNS was already well-structured -- every storefront
# apex resolves through a CNAME chain to the shared ALB (Cloudflare flattens
# the apex CNAME, which is why dig shows A records). Nothing in DNS references
# the ALB's EIPs. So there is no A-record migration to do; we only bring the
# SIX records that point at the ALB under Terraform control.
#
# Deliberately NOT managed here: DKIM/SES, MX, SPF/DMARC, ACM-validation and
# GoDaddy-email records (~85 of them). They never change during a failover and
# importing them would be noise. swadkerala.com is still on GoDaddy NS -- not
# manageable from Cloudflare at all (runbook item).
#
# FAILOVER = change var.active_alb_dns_name to the DR ALB's DNS name -> apply.
# All six records flip in one action. Cloudflare-side propagation is seconds;
# client TTL is Cloudflare "Auto" (300s for DNS-only records).
#
# Auth: CLOUDFLARE_API_TOKEN env var (DNS:Edit + Zone:Read on the 5 zones,
# expires 2027-08-03 -- rotate mid-July 2027). Never hardcode it here.

variable "active_alb_dns_name" {
  description = "DNS name of the load balancer currently serving production. In a regional failover, point this at the DR ALB and apply."
  type        = string
  default     = "k8s-vendureshared-e797866abf-762060618.ap-south-1.elb.amazonaws.com"
}

locals {
  cloudflare_zone_ids = {
    "kaaikani.co.in"         = "554147339202adfc53f2a1f28c9a72ab"
    "kaaikanistore.com"      = "6f5d76473990830d68e2936b10184478"
    "southmithai.com"        = "116f967a6e0509579ccf9a0fb49b35c8"
    "prabhasaaridesigns.com" = "02d1da48831cf14f7bb91874d9b446c5"
    "avsecomhub.com"         = "78f87bf40a4e46bcf856f8cb3dc84428" # no ALB records yet; id kept for later
  }

  # The six ALB-pointing records. Everything else in these zones chains to one
  # of these (apex -> eks.<zone> -> ALB), so flipping these flips every domain.
  alb_records = {
    "eks.kaaikani.co.in"     = local.cloudflare_zone_ids["kaaikani.co.in"]
    "ven.kaaikani.co.in"     = local.cloudflare_zone_ids["kaaikani.co.in"]
    "eks.kaaikanistore.com"  = local.cloudflare_zone_ids["kaaikanistore.com"]
    "eks.southmithai.com"    = local.cloudflare_zone_ids["southmithai.com"]
    "web.southmithai.com"    = local.cloudflare_zone_ids["southmithai.com"]
    "prabhasaaridesigns.com" = local.cloudflare_zone_ids["prabhasaaridesigns.com"]
  }
}

resource "cloudflare_dns_record" "alb" {
  for_each = local.alb_records

  zone_id = each.value
  name    = each.key
  type    = "CNAME"
  content = var.active_alb_dns_name
  ttl     = 1     # 1 = "Auto" in Cloudflare
  proxied = false # matches current state; flipping to proxied is a separate decision
}

# One-shot imports: adopt the existing live records instead of recreating them.
# Import ID format is <zone_id>/<record_id>. Safe to leave in place after the
# import apply -- Terraform ignores import blocks whose targets are in state --
# but follow repo convention and drop them in a cleanup commit afterwards.
import {
  to = cloudflare_dns_record.alb["eks.kaaikani.co.in"]
  id = "554147339202adfc53f2a1f28c9a72ab/41e9a94800184ad0f244d4ca436f390e"
}
import {
  to = cloudflare_dns_record.alb["ven.kaaikani.co.in"]
  id = "554147339202adfc53f2a1f28c9a72ab/4785cf34b6e1200b1a493e874cd1df64"
}
import {
  to = cloudflare_dns_record.alb["eks.kaaikanistore.com"]
  id = "6f5d76473990830d68e2936b10184478/a6f0be140896f853bce8d66325905443"
}
import {
  to = cloudflare_dns_record.alb["eks.southmithai.com"]
  id = "116f967a6e0509579ccf9a0fb49b35c8/93daf23875a58351fb2e60e25f6db996"
}
import {
  to = cloudflare_dns_record.alb["web.southmithai.com"]
  id = "116f967a6e0509579ccf9a0fb49b35c8/4f22170694623ca5a17d9ba469f1d660"
}
import {
  to = cloudflare_dns_record.alb["prabhasaaridesigns.com"]
  id = "02d1da48831cf14f7bb91874d9b446c5/8c49c27749fb16805ea7cfbe0996f143"
}
