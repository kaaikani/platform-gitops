# DR Phase 1, Step 5 -- ECR cross-region replication.
#
# ############################################################################
# ⚠️  S3 CRR madhiriye, IDHU UM PUTHU IMAGE AH MATTUM replicate pannum.
#     Ippo ECR la irukkura image automatic ah pogaadhu. Adutha deploy nadandha
#     appo dhaan DR region la oru image varum.
#     Backfill panna: `docker pull` + retag + `docker push`, illa
#     `crane copy`. Illana adutha deploy varaikum wait pannunga.
# ############################################################################
#
# Idhu illama enna aagum? DR time la GitHub la irundhu rebuild panni push
# pannalaam -- GitHub AWS la illa, so safe. Aana adhu RTO ku +45 nimisham.
# $2.34/mo ku antha 45 nimisham vaangikalaam.
#
# Size alandhadhu (2026-07-30): mothham 31.25 GB.
#   vendure-prod       14.76 GB
#   vendure-test        7.85 GB  <- test image, DR ku value illa, EXCLUDE
#   vendure-client      3.42 GB
#   kaaikanistore       2.04 GB
#   southmithai         1.12 GB
#   prabasaaridesigns   1.04 GB
#   swadkerala          1.02 GB
#   client_vendure      0.00 GB  <- காலி, ecr.tf la ye "deletion candidate" nu irukku
#
# vendure-test ah vittadhaala 31.25 -> 23.40 GB, $3.13 -> $2.34/mo.
#
# NOTE: prefix filter ah "vendure" nu vekka koodadhu -- adhu vendure-test ayum
# pudichukkum. Ovvoru repo ku thani filter, adhu dhaan explicit-ah safe.
resource "aws_ecr_replication_configuration" "dr" {
  replication_configuration {
    rule {
      destination {
        region      = var.dr_region
        registry_id = data.aws_caller_identity.current.account_id
      }

      repository_filter {
        filter      = "vendure-prod"
        filter_type = "PREFIX_MATCH"
      }
      repository_filter {
        filter      = "vendure-client"
        filter_type = "PREFIX_MATCH"
      }
      repository_filter {
        filter      = "kaaikanistore"
        filter_type = "PREFIX_MATCH"
      }
      repository_filter {
        filter      = "southmithai"
        filter_type = "PREFIX_MATCH"
      }
      repository_filter {
        filter      = "swadkerala"
        filter_type = "PREFIX_MATCH"
      }
      repository_filter {
        filter      = "prabasaaridesigns"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}
