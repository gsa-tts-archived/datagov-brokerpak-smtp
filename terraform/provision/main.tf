locals {
  instance_id = "ses-${substr(sha256(var.instance_name), 0, 16)}"
  domain = (var.domain != "" ? var.domain : "${local.instance_id}.${var.default_domain}")
  txt_verification_record = {
    name    = "_amazonses"
    type    = "TXT"
    ttl     = "600"
    records = [aws_ses_domain_identity.identity.verification_token]
  }

  dkim_records = null_resource.dkim_records.*.triggers

  # If no domain was specified, we need to create the records ourselves
  route53_records = (var.domain != "" ? {} : 
    {
      # Old-style (SES v1) TXT verification record
      txt_verification_record = local.txt_verification_record
    }
  )

  instructions = (var.domain != "" ? "Your SMTP service is provisioned, but not verified. To verify the domain, create records in the ${var.domain} zone corresponding to the TXT and CNAME records provided in this output." :
  null)
}

resource "aws_ses_domain_identity" "identity" {
  domain = local.domain
}

resource "aws_ses_domain_dkim" "dkim" {
  domain = aws_ses_domain_identity.identity.domain
}


# We need to tell the caller about the three DKIM DNS records they must create.
# There's no easy way to generate a nested structure in Terraform output, since
# the for, for_each, count, and dynamic expressions don't work there. So we're
# using this workaround:
# https://gist.github.com/brikis98/f3fe2ae06f996b40b55eebcb74ed9a9e
resource "null_resource" "dkim_records" {
  count = 3

  triggers = {
    name     = format(
        "%s._domainkey.%s",
        element(aws_ses_domain_dkim.dkim.dkim_tokens, count.index),
        local.domain
      )
    type = "CNAME"
    ttl  = "600"
    records = "${element(aws_ses_domain_dkim.dkim.dkim_tokens, count.index)}.dkim.amazonses.com"
  }
}
