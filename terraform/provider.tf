terraform {
  required_providers {
    cloudstack = {
      source  = "cloudstack/cloudstack"
      version = "~> 0.5.0"
    }
    local = {
      source = "hashicorp/local"
    }
  }
  required_version = ">= 1.0"
}

provider "cloudstack" {
  api_url    = "https://dku.kloud.zone/client/api"
  api_key    = "BDciNzMKijOYkjmCbW6kZBgmmF96eDZUfLZW8PrCljDL6q093ApSpaHsbs9ucFTQ5iPbjAjyaoJwog5_gY4Lkg"
  secret_key = "qG1NHRsyI4iTqPyYr76o6xuFc7AJSf2_xONDDP4fS9DLpHvSWgxz1xuclpCSfzI0-XYIS0rYjWbOSEURpGFNHg"
}
