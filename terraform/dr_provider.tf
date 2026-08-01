### DR Phase 1 -- data ah ap-south-1 ku VELIYA kondu poradhu.
#
# Ippo indha DR resources ellame idhe root module / state la irukku, oru provider
# alias vechu. Phase 2 la terraform/live/aws-prod + terraform/live/aws-dr nu
# pirippom (appo DR state GCS/vera bucket la irukkanum -- ap-south-1 poidhucha
# state um sethu poga koodadhu).
#
# MUKKIYAM: Phase 1 la ONNUME run aagadhu. Backup, image, secret, state --
# ivai mattum replicate aagum. EKS cluster, RDS instance ellame Phase 2 la,
# adhuvum code ah mattum (apply pannama), so standing cost ~$4/mo dhaan.

provider "aws" {
  alias  = "dr"
  region = var.dr_region
}

data "aws_caller_identity" "current" {}

# Encrypted RDS backup ah vera region ku replicate panna, ANDHA region la oru
# KMS key kandippa venum -- KMS key region-scoped, ap-south-1 key ah ap-south-2
# la use panna mudiyaadhu.
resource "aws_kms_key" "dr_rds" {
  provider = aws.dr

  description             = "Encrypts replicated vendure-prod-db automated backups in ${var.dr_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Project = var.project
    Purpose = "dr-rds-backup"
  }
}

resource "aws_kms_alias" "dr_rds" {
  provider = aws.dr

  name          = "alias/vendure-dr-rds"
  target_key_id = aws_kms_key.dr_rds.key_id
}
