# CloudStack zone
variable "zone" {
  default = "DKU"
}

# VM template
variable "template_name" {
  default = "Ubuntu_24.04_VSCode"
}

# CPU offering names (CloudStack UI에 있는 이름 그대로)
variable "master_offering" {
  default = "Medium" # 2 core
}

variable "gitlab_offering" {
  default = "Large" # 4 core
}

variable "worker_offering" {
  default = "Small" # 1 core
}
