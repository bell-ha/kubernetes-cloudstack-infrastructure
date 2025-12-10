output "public_ip" {
  value = cloudstack_ipaddress.public_ip.ip_address
}

output "master_ip" {
  value = cloudstack_instance.master.ip_address
}

output "gitlab_ip" {
  value = cloudstack_instance.gitlab.ip_address
}

output "worker_ip" {
  value = cloudstack_instance.worker.ip_address
}

output "jenkins_url" {
  value = "http://${cloudstack_ipaddress.public_ip.ip_address}:30880"
}

output "gitlab_url" {
  value = "http://${cloudstack_ipaddress.public_ip.ip_address}:30080"
}

