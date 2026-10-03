output "cp_ips" {
  value = { for name, s in hcloud_server.nodes : name => s.ipv4_address }
}
