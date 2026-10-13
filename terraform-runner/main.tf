terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.69"
    }
  }
  backend "http" {}
}

provider "hcloud" {}

data "hcloud_ssh_key" "group" {
  name = "group1"
}

resource "hcloud_server" "runner" {
  name        = "gitlab-runner"
  image       = "ubuntu-26.04"
  server_type = "cx23"
  location    = "fsn1"
  ssh_keys    = [data.hcloud_ssh_key.group.id]
  labels      = { role = "runner"}
  user_data   = templatefile("./user-data.yml", {
    ssh_public_key = data.hcloud_ssh_key.group.public_key
  })
}


resource "hcloud_firewall" "runner" {
  name = "runner"

  apply_to {
    label_selector = "role=runner"
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

