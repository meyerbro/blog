## GITHUB
provider "github" {
  # token and organization will be read from $GITHUB_USER and $GITHUB_TOKEN, respectively
  organization = "${var.github_organization}"
}

resource "github_repository" "blog" {
  name        = "${var.github_repo}"
  description = "${var.github_repo_desc}"

  private = false
}

## CLOUDFLARE
provider "cloudflare" {
  # email and token will be read from $CLOUDFLARE_EMAIL and $CLOUDFLARE_TOKEN, respectively
}

resource "cloudflare_zone_settings_override" "zone-settings" {
  name = "${var.domain}"

  settings {
    tls_1_3                  = "on"
    automatic_https_rewrites = "on"
    ssl                      = "strict"
  }
}

resource "cloudflare_record" "blog" {
  domain = "${var.domain}"

  name  = "${var.hostname}"
  type  = "CNAME"
  value = "${var.github_organization}.github.io"

  proxied = "true"
}

# alias the apex and www record to blog
resource "cloudflare_record" "apex" {
  domain = "${var.domain}"

  name  = "${var.domain}"
  type  = "CNAME"
  value = "${var.hostname}"

  proxied = "true"
}

resource "cloudflare_page_rule" "redirect-apex" {
  zone   = "${var.domain}"
  target = "${var.domain}"

  actions = {
    forwarding_url {
      url         = "https://${var.hostname}"
      status_code = 301
    }
  }
}

resource "cloudflare_record" "www" {
  domain = "${var.domain}"

  name  = "www.${var.domain}"
  type  = "CNAME"
  value = "${var.hostname}"

  proxied = "true"
}

resource "cloudflare_page_rule" "redirect-www" {
  zone   = "${var.domain}"
  target = "www.${var.domain}"

  actions = {
    forwarding_url {
      url         = "https://${var.hostname}"
      status_code = 301
    }
  }
}
