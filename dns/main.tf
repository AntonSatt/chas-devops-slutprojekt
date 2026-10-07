# DNS har en egen state (init: ../terraform/setup.sh dns), skild från klustrens.
# Posten pekar på workern, som inte rivs, och ska finnas en gång för hela
# gruppen — inte en gång per persons kluster.
terraform {
  required_providers {
    dns = {
      source  = "hashicorp/dns"
      version = "~> 3.6"
    }
  }
  backend "http" {}
}

# Uppdateringar via RFC 2136, signerade med gruppens TSIG-nyckel. Nyckeln får
# bara skriva poster under group-1.
provider "dns" {
  update {
    server        = "ns1.chas-lab.dev" # primär namnserver enligt zonens SOA
    key_name      = "doe25-group-1."
    key_algorithm = "hmac-sha256"
    key_secret    = var.tsig_secret # från TF_VAR_tsig_secret
  }
}

# --- Wildcard-post ----------------------------------------------------------

# Alla namn under group-1 pekar på workern. Traefik kan bara köras där,
# eftersom control planes har NoSchedule-taint, så ingen app behöver en egen post.
resource "dns_a_record_set" "wildcard" {
  # group-1 är ingen egen zon, posterna ligger i doe25.chas-lab.dev
  zone = "doe25.chas-lab.dev."
  name = "*.group-1"
  # Workerns publika IP. Samma adress står i terraform/variables.tf (worker_ip)
  # och ansible/inventory/worker.ini.
  addresses = [
    "203.0.113.10"
  ]
  ttl = 300

  # Posten skapades av läraren och importerades hit. Prods HTTPS hänger på den,
  # så en destroy ska stoppas. Ändrad IP eller TTL går igenom som vanligt.
  lifecycle {
    prevent_destroy = true
  }
}
