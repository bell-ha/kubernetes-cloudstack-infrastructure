# CloudStack API 접속 정보 — 실제 값은 terraform.tfvars(gitignore)에서 주입
variable "cloudstack_api_url" {
  default = "https://dku.kloud.zone/client/api"
}

variable "cloudstack_api_key" {
  sensitive = true
}

variable "cloudstack_secret_key" {
  sensitive = true
}

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
