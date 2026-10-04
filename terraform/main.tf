terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.69"
    }
  }
  backend "http" {}
}

# Token läses från miljövariabeln HCLOUD_TOKEN
provider "hcloud" {}

# --- SSH-nyckel -------------------------------------------------------------

data "hcloud_ssh_key" "group" {
  name = "group1"
}

# --- Tre control plane-noder ------------------------------------------------

resource "hcloud_server" "nodes" {
  for_each = {
    for i in range(0, var.node_count) :
    "${var.cluster_name}-node-${i < var.control_plane_count ? "cp" : "wk"}-${i < var.control_plane_count ? i : i - var.control_plane_count}" => {
      control_plane = i < var.control_plane_count
    }
  }

  name        = each.key
  image       = "ubuntu-26.04"
  server_type = "cx23"
  location    = "fsn1"
  ssh_keys    = [data.hcloud_ssh_key.group.id]
  labels      = { role = each.value.control_plane ? "control_plane" : "worker", cluster = var.cluster_name }
}

# --- Brandvägg för control plane --------------------------------------------

locals {
  cp_ips   = [for s in hcloud_server.nodes : "${s.ipv4_address}/32"]
  node_ips = concat(local.cp_ips, ["${var.worker_ip}/32"])
}

resource "hcloud_firewall" "cp" {
  name = "${var.cluster_name}-k3s-control-plane"

  # Kopplas via label, inte via firewall_ids på servern — annars blir det ett
  # beroendecirkel, eftersom reglerna nedan behöver serverns IP.
  apply_to {
    label_selector = "role=control_plane,cluster=${var.cluster_name}"
  }

  # SSH — skolan kontrollerar åtkomsten automatiskt från okända adresser
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Kubernetes API — noderna själva + admin
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = concat(local.node_ips, [var.admin_cidr])
  }

  # etcd — bara mellan control plane-noderna
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "2379-2380"
    source_ips = local.cp_ips
  }

  # kubelet
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = local.node_ips
  }

  # WireGuard (flannel wireguard-native)
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51820"
    source_ips = local.node_ips
  }
}
