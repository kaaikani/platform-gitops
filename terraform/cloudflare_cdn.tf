# Cloudflare-fronted asset hostname for prabhasaaridesigns.com.
#
# WHY
# The storefront appends resize params to asset URLs (?w=40&h=40&format=webp,
# ?preset=thumb -- see components/header/Header.tsx et al in the prabas-aari
# repo), but the Vendure API handed it RAW S3 URLs, and S3 ignores query
# strings. Every "thumbnail" therefore served the full-size original: a 40x40
# request returned 58 KB instead of 1 KB, a 58x overshoot.
#
# Measured over August 2026 from the S3 server access logs: ~283 GB of egress,
# ~93% of all S3 egress on the account, ~$23/month -- more than the dedicated
# t3a.small running the client's whole Vendure backend.
#
# FIX (three parts, this file is one of them)
#   1. admin-ui-client  src/cdn-aware-s3-storage.ts reads ASSET_CDN_BASE
#   2. platform-gitops  environments/production/vendure-client-values.yaml sets
#                       it to https://cdn.prabhasaaridesigns.com/assets/ and
#                       adds that host to the vendure-client ingress
#   3. here             the DNS record that puts Cloudflare in front of it
# Parts 1+2 make the resize actually happen; part 3 caches the result at the
# edge so the asset server regenerates each variant once, not per request.
#
# SCOPE -- deliberately a dedicated cdn.* hostname, NOT the apex.
# The apex keeps proxied = false (dr_cloudflare.tf), so shop-api, /admin and
# checkout never pass through the edge cache. The ingress only routes /assets
# on this hostname, so the blast radius is images.
#
# No new ACM cert: the ALB already serves the *.prabhasaaridesigns.com wildcard.
# No cache rule: the asset server returns `cache-control: public,
# max-age=15552000`, which Cloudflare honours by default for image extensions.
#
# FAILOVER: tracks the same var.active_alb_dns_name as dr_cloudflare.tf, so a
# regional failover moves this record with the rest.

resource "cloudflare_dns_record" "prabasaari_cdn" {
  zone_id = local.cloudflare_zone_ids["prabhasaaridesigns.com"]
  name    = "cdn.prabhasaaridesigns.com"
  type    = "CNAME"
  content = var.active_alb_dns_name
  ttl     = 1    # 1 = "Auto" (required by Cloudflare while proxied)
  proxied = true # the point of this file: cache resized assets at the edge
  comment = "Vendure asset host, edge-cached. See cloudflare_cdn.tf"
}
