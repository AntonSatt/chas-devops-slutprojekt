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

# --- Control plane-noder ----------------------------------------------------
# Workern är bare metal-servern och skapas inte här, se var.worker_ip.

resource "hcloud_server" "nodes" {
  for_each = toset([
    for i in range(var.control_plane_count) : "${var.cluster_name}-node-cp-${i}"
  ])

  name        = each.key
  image       = "ubuntu-26.04"
  server_type = "cx23"
  location    = "fsn1"
  ssh_keys    = [data.hcloud_ssh_key.group.id]
  labels      = { role = "control_plane", cluster = var.cluster_name }
}

# --- Worker-noder ----------------------------------------------------
# Worker för egen dev-miljö

resource "hcloud_server" "workers" {
  for_each = toset([
    for i in range(var.worker_count) : "${var.cluster_name}-node-worker-${i}"
  ])

  name        = each.key
  image       = "ubuntu-26.04"
  server_type = "cx23"
  location    = "fsn1"
  ssh_keys    = [data.hcloud_ssh_key.group.id]
  labels      = { role = "worker", cluster = var.cluster_name }
}

# --- Brandvägg för control plane --------------------------------------------
# Gäller bara control planes. Workers har ingen molnbrandvägg, där sköter
# Ansible ufw — både på bare metal-workern i prod och på dev-workern.
#
# node_ips är alla noder i klustret: control planes, eventuell dev-worker och
# prods bare metal-worker. worker_ips är tom när worker_count = 0.

locals {
  cp_ips     = [for s in hcloud_server.nodes : "${s.ipv4_address}/32"]
  worker_ips = [for s in hcloud_server.workers : "${s.ipv4_address}/32"]
  node_ips   = concat(local.cp_ips, local.worker_ips, ["${var.worker_ip}/32"])
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

  # node-exporter. Prometheus kör på workern och skrapar control planes via
  # deras publika IP. Utan regeln larmar TargetDown för node-exporter.
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "9100"
    source_ips = local.node_ips
  }
}
