output "cp_ips" {
  value = { for name, s in hcloud_server.cp : name => s.ipv4_address }
}
