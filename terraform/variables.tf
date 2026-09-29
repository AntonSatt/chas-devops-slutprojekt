variable "ssh_public_key" {
  description = "Gruppens publika SSH-nyckel"
  type        = string
}

variable "admin_cidr" {
  description = "Adressen som får nå Kubernetes API, t.ex. 1.2.3.4/32"
  type        = string
}

variable "worker_ip" {
  description = "Publik IPv4 för den dedikerade servern. Samma adress står i ansible/inventory/worker.ini"
  type        = string
  default     = "203.0.113.10"
}
