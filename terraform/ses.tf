# SES domain identities + configuration sets.
# "my-first-configuration-set" (a tutorial/default leftover) intentionally NOT imported as a
# resource, but kaaikani.co.in references it by name (a plain string, no TF dependency needed).

resource "aws_sesv2_email_identity" "southmithai_com" {
  email_identity         = "southmithai.com"
  configuration_set_name = "ses-event-config"
}

resource "aws_sesv2_email_identity" "avsecomhub_com" {
  email_identity         = "avsecomhub.com"
  configuration_set_name = "email-logs-config"
}

resource "aws_sesv2_email_identity" "prabhasaaridesigns_com" {
  email_identity         = "prabhasaaridesigns.com"
  configuration_set_name = "ses-event-config"
  tags = {
    "vendure-client" = "Prabhasaaridesigns"
  }
}

resource "aws_sesv2_email_identity" "kaaikani_co_in" {
  email_identity         = "kaaikani.co.in"
  configuration_set_name = "my-first-configuration-set"
}

resource "aws_sesv2_email_identity" "kaaikanistore_com" {
  email_identity         = "kaaikanistore.com"
  configuration_set_name = "ses-event-config"
  tags = {
    "Prod" = "email-kaaikanistore"
  }
}

resource "aws_sesv2_configuration_set" "email_logs_config" {
  configuration_set_name = "email-logs-config"
  delivery_options {
    tls_policy = "OPTIONAL"
  }
}

resource "aws_sesv2_configuration_set" "ses_event_config" {
  configuration_set_name = "ses-event-config"
  delivery_options {
    tls_policy = "OPTIONAL"
  }
}
