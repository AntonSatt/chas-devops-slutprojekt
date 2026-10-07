variable "admin_cidr" {
  description = "Adressen som får nå Kubernetes API, t.ex. 1.2.3.4/32"
  type        = string
}

variable "worker_ip" {
  description = "Publik IPv4 för den dedikerade servern. Samma adress står i ansible/inventory/worker.ini"
  type        = string
  default     = "203.0.113.10"
}

variable "cluster_name" {
  type        = string
  description = "Klustrets namn, prefix för alla resurser och värdet på labeln cluster. Eget namn för eget pill tex thomas, för prod group1."
}

variable "control_plane_count" {
  type        = number
  description = "Antal control plane-VM:ar. 3 i prod, kan sättas lägre i en egen dev-miljö."
  default     = 3
}

variable "worker_count" {
  type        = number
  description = "Sätt till 1 om det behövs till egen dev-miljö. Gäller ej för prod."
  default     = 1
}
