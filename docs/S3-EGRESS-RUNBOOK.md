# S3 Egress Cost Runbook — `avsecomhub-clients-s3-images`

Written 2026-08-22 after the August egress spike ($4.92 on 8/21 alone).

## What happened

A paid Meta ad campaign drove cold-cache traffic to prabhasaaridesigns.com, whose
images are served **direct from S3 with no CDN**. Measured from server access logs:

| day | egress | requests | unique visitor IPs |
|-----|--------|----------|--------------------|
| 8/19 | 15.77 GB | 65,435 | 673 |
| 8/20 | 14.76 GB | 61,862 | 768 |
| 8/21 | **43.64 GB** | 175,268 | **1,826** |

Only **741 unique objects** served 175,268 times. ~24 MB egress per visitor.
72% of the bytes were two 2048x2048 RGBA PNGs named `__preview`.

Cross-check: 44.8 GB x $0.1093/GB = $4.90 vs actual $4.915. Attribution exact.

## Root cause

The storefront requests `?w=40&h=40&format=webp` — that is **Vendure
AssetServerPlugin transform syntax**. But the asset URLs point at **raw S3**,
which ignores query params and returns the original. The asset server is bypassed.
A 40x40 thumbnail was downloading 7.95 MB.

Each distinct query string is billed as a separate full fetch.

## Layer 1 — recompress oversized objects (DONE 2026-08-22)

Both PNGs had an RGBA channel with **no actual transparency**.

| key | before | after |
|-----|--------|-------|
| `preview/d8/pad2604-4__03__preview.png` | 7.95 MB | 368 KB |
| `preview/08/pad26-4__preview.png` | 10.28 MB | 468 KB |
| `casual_images/logo.png` | 1.32 MB | 66 KB |

Downscaled to 800px, alpha dropped, 256-colour quantized, `optimize=True`.
Same key, same `image/png` Content-Type, same Cache-Control. No app change needed.

Bucket versioning is **Enabled**, so the originals are retained. Rollback:

    aws s3api copy-object --bucket avsecomhub-clients-s3-images \
      --key "preview/d8/pad2604-4__03__preview.png" \
      --copy-source "avsecomhub-clients-s3-images/preview/d8/pad2604-4__03__preview.png?versionId=9tQmz6yFsFlu9tuKOwLyZ5c_ZvEcf_Zm" \
      --metadata-directive COPY

    # pad26-4 original versionId: xRkYHp8DsPflxHxMwB2uz1mzLbXhsQn2
    # logo.png original versionId: UsF1aJhJxgIW5dz.0O4RvLONOGWhlKLk

`logo.png` has **real transparency** — keep RGBA, and note Pillow's `quantize()` needs
`method=Image.FASTOCTREE` for RGBA (MEDIANCUT raises). The two previews were RGBA with
**no** transparency in use, so their alpha was dropped outright.

Replayed against the real Aug 21 access log, all three fixes together:

| | egress | cost |
|---|--------|------|
| before | 43.59 GB | $4.76 |
| after  | 11.71 GB | $1.28 |
| cut    | 31.88 GB | **73%** |

The remaining ~10 GB/day is a long tail — the next objects are already 48-350 KB each, so
there is no fourth big single win. Only the Layer 3 app fix shrinks the tail.

## Layer 2 — CDN in front (BLOCKED on Free plan — see below)

`cdn.avsecomhub.com` is a proxied CNAME to the S3 host but returns **404**: S3 receives
`Host: cdn.avsecomhub.com` and cannot match the bucket. (`cdn.kaaikani.co.in` works only
because its bucket is *named* after the hostname.)

**An Origin Rule cannot fix this here.** Verified 2026-08-22: zone `avsecomhub.com` is on
the **Free** plan, and Host header / SNI / DNS-record overrides are **Enterprise-only**.
Free allows 10 origin rules but only the *destination port* override.

Renaming/copying to a bucket named `cdn.avsecomhub.com` would work with zero rules, but
**the user has ruled out creating new buckets** (2026-08-22) — do not re-propose it.

Remaining options, neither yet pursued:

- **Cloudflare Worker** fetching the S3 URL directly (correct Host by construction), with
  `cacheEverything`. Needs **Workers Paid ($5/mo)** — Aug 21 saw 175k req/day against a
  100k/day free limit. Cheap relative to the ~$150/mo run-rate this was heading toward.
- **CloudFront** with an S3 origin — handles Host correctly against the same bucket, but is
  roughly **cost-neutral**: India egress is ~$0.109/GB, about the same as S3 direct. It
  buys caching and lower request cost, not lower egress.

Note the objects already carry `Cache-Control: public, max-age=31536000, immutable`
(backfilled 2026-08-18), so whichever CDN is chosen will cache well without a Cache Rule.

## Layer 3 — point the app at the CDN (TODO — app repo, not this one)

The S3 hostname is hardcoded in the prabhasaaridesigns storefront. Change asset base
URLs from `avsecomhub-clients-s3-images.s3.ap-south-1.amazonaws.com` to
`cdn.avsecomhub.com`.

Better fix: point them at Vendure's asset server so `?w=` / `?format=` actually
resize instead of being silently ignored. That removes this failure mode permanently
rather than caching around it.

## Layer 4 — lock the bucket (TODO — only AFTER Layer 3 is deployed)

The bucket policy is currently wide open:

    {"Sid":"PublicReadImages","Effect":"Allow","Principal":"*",
     "Action":"s3:GetObject","Resource":"arn:aws:s3:::avsecomhub-clients-s3-images/*"}

Restrict anonymous reads to Cloudflare ranges (https://www.cloudflare.com/ips-v4)
with an `aws:SourceIp` condition. This is what makes the fix structural — no bypass
possible. IAM-authenticated access (DR replication, GCP transfer) is unaffected
because it does not rely on the anonymous grant.

**Do not apply before Layer 3** — the storefront still requests the S3 host directly
and will break instantly.

## Layer 5 — guardrail (DONE 2026-08-22)

AWS Budget `S3-Monthly`: $25/mo, filtered to `Amazon Simple Storage Service`,
alerting admin@avsecomhub.com at ACTUAL 50%, ACTUAL 80%, FORECASTED 100%.
At creation it already read actual $18.79 / forecast $35.91 for August.

Previously the only budget was `EKS-Production-Monthly` ($150), which is why this
ran three weeks unnoticed.

## Re-running the attribution

Server access logging (enabled 2026-08-18, 30d expiry) is the only way to attribute
egress per bucket on this account — request metrics are off, and CloudTrail is
management-events only so `GetObject` is unlogged.

    aws s3 sync s3://kaaikani-s3-access-logs-149536454380/ ./s3logs/ \
      --exclude "*" --include "*2026-08-21*"

    # bytes_sent is field 15
    cat ./s3logs/<bucket>/* | awk '{if ($15 ~ /^[0-9]+$/) b+=$15} END {print b/1073741824" GB"}'

    # top objects by bytes
    cat ./s3logs/<bucket>/* | awk '{if ($15 ~ /^[0-9]+$/){b[$9]+=$15;c[$9]++}} END \
      {for (k in b) printf "%.2f GB\t%d hits\t%s\n", b[k]/1073741824, c[k], k}' | sort -rn | head -15
