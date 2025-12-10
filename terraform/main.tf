########################################
# CloudStack Kubernetes Cluster — main.tf
########################################

########################
# ISOLATED NETWORK
########################
resource "cloudstack_network" "k8s_network" {
  name             = "k8s-network"
  display_text     = "k8s-network"
  cidr             = "192.168.50.0/24"
  network_offering = "DefaultIsolatedNetworkOfferingWithSourceNatService"
  zone             = var.zone
}

########################
# ALLOW ALL EGRESS
########################
resource "cloudstack_egress_firewall" "allow_all_egress" {
  network_id = cloudstack_network.k8s_network.id

  rule {
    protocol  = "all"
    cidr_list = ["0.0.0.0/0"]
  }
}

########################
# PUBLIC IP
########################
resource "cloudstack_ipaddress" "public_ip" {
  zone       = var.zone
  depends_on = [cloudstack_network.k8s_network]
}

########################
# WAIT UNTIL PUBLIC IP READY
########################
resource "time_sleep" "wait_for_ip" {
  depends_on      = [cloudstack_ipaddress.public_ip]
  create_duration = "60s"
}

########################
# MASTER NODE
########################
resource "cloudstack_instance" "master" {
  name             = "k8s-master"
  service_offering = var.master_offering
  template         = var.template_name
  zone             = var.zone
  network_id       = cloudstack_network.k8s_network.id
  expunge          = true

  user_data = <<EOF
#cloud-config
ssh_pwauth: true
password: ubuntu
chpasswd: { expire: False }
EOF
}

########################
# GITLAB NODE
########################
resource "cloudstack_instance" "gitlab" {
  name             = "k8s-gitlab"
  service_offering = var.gitlab_offering
  template         = var.template_name
  zone             = var.zone
  network_id       = cloudstack_network.k8s_network.id
  expunge          = true

  user_data = <<EOF
#cloud-config
ssh_pwauth: true
password: ubuntu
chpasswd: { expire: False }
EOF
}

########################
# WORKER NODE
########################
resource "cloudstack_instance" "worker" {
  name             = "k8s-worker"
  service_offering = var.worker_offering
  template         = var.template_name
  zone             = var.zone
  network_id       = cloudstack_network.k8s_network.id
  expunge          = true

  user_data = <<EOF
#cloud-config
ssh_pwauth: true
password: ubuntu
chpasswd: { expire: False }
EOF
}

########################################
# PORT FORWARDING — SSH
########################################
resource "cloudstack_port_forward" "ssh_master" {
  depends_on     = [cloudstack_instance.master, time_sleep.wait_for_ip]
  ip_address_id  = cloudstack_ipaddress.public_ip.id

  forward {
    protocol           = "tcp"
    private_port       = 22
    public_port        = 22
    virtual_machine_id = cloudstack_instance.master.id
  }
}

resource "cloudstack_port_forward" "ssh_gitlab" {
  depends_on     = [cloudstack_instance.gitlab, time_sleep.wait_for_ip]
  ip_address_id  = cloudstack_ipaddress.public_ip.id

  forward {
    protocol           = "tcp"
    private_port       = 22
    public_port        = 2201
    virtual_machine_id = cloudstack_instance.gitlab.id
  }
}

resource "cloudstack_port_forward" "ssh_worker" {
  depends_on     = [cloudstack_instance.worker, time_sleep.wait_for_ip]
  ip_address_id  = cloudstack_ipaddress.public_ip.id

  forward {
    protocol           = "tcp"
    private_port       = 22
    public_port        = 2202
    virtual_machine_id = cloudstack_instance.worker.id
  }
}

########################################
# FIREWALL RULES — SSH
########################################
resource "cloudstack_firewall" "fw_ssh_master" {
  depends_on     = [time_sleep.wait_for_ip]
  ip_address_id  = cloudstack_ipaddress.public_ip.id

  rule {
    protocol  = "tcp"
    ports     = ["22"]
    cidr_list = ["0.0.0.0/0"]
  }
}

resource "cloudstack_firewall" "fw_ssh_gitlab" {
  depends_on     = [time_sleep.wait_for_ip]
  ip_address_id  = cloudstack_ipaddress.public_ip.id

  rule {
    protocol  = "tcp"
    ports     = ["2201"]
    cidr_list = ["0.0.0.0/0"]
  }
}

resource "cloudstack_firewall" "fw_ssh_worker" {
  depends_on     = [time_sleep.wait_for_ip]
  ip_address_id  = cloudstack_ipaddress.public_ip.id

  rule {
    protocol  = "tcp"
    ports     = ["2202"]
    cidr_list = ["0.0.0.0/0"]
  }
}

########################################
# NODEPORT SERVICES
########################################

resource "cloudstack_port_forward" "gitlab_web" {
  depends_on     = [cloudstack_instance.gitlab, time_sleep.wait_for_ip]
  ip_address_id  = cloudstack_ipaddress.public_ip.id

  forward {
    protocol           = "tcp"
    private_port       = 30080
    public_port        = 30080
    virtual_machine_id = cloudstack_instance.gitlab.id
  }
}

resource "cloudstack_firewall" "fw_gitlab_web" {
  depends_on    = [time_sleep.wait_for_ip]
  ip_address_id = cloudstack_ipaddress.public_ip.id

  rule {
    protocol  = "tcp"
    ports     = ["30080"]
    cidr_list = ["0.0.0.0/0"]
  }
}

resource "cloudstack_port_forward" "jenkins_web" {
  depends_on     = [cloudstack_instance.master, time_sleep.wait_for_ip]
  ip_address_id  = cloudstack_ipaddress.public_ip.id

  forward {
    protocol           = "tcp"
    private_port       = 32080
    public_port        = 32080
    virtual_machine_id = cloudstack_instance.master.id
  }
}

resource "cloudstack_firewall" "fw_jenkins_web" {
  depends_on    = [time_sleep.wait_for_ip]
  ip_address_id = cloudstack_ipaddress.public_ip.id

  rule {
    protocol  = "tcp"
    ports     = ["32080"]
    cidr_list = ["0.0.0.0/0"]
  }
}

resource "cloudstack_port_forward" "registry_web" {
  depends_on     = [cloudstack_instance.gitlab, time_sleep.wait_for_ip]
  ip_address_id  = cloudstack_ipaddress.public_ip.id

  forward {
    protocol           = "tcp"
    private_port       = 30500
    public_port        = 30500
    virtual_machine_id = cloudstack_instance.gitlab.id
  }
}

resource "cloudstack_firewall" "fw_registry_web" {
  depends_on    = [time_sleep.wait_for_ip]
  ip_address_id = cloudstack_ipaddress.public_ip.id

  rule {
    protocol  = "tcp"
    ports     = ["30500"]
    cidr_list = ["0.0.0.0/0"]
  }
}

########################################
# ANSIBLE INVENTORY
########################################
resource "local_file" "ansible_inventory" {
  depends_on = [cloudstack_ipaddress.public_ip]
  filename   = "${path.module}/../ansible/inventory/hosts.ini"

  content = templatefile("${path.module}/../ansible/inventory/hosts.ini.tmpl", {
    public_ip = cloudstack_ipaddress.public_ip.ip_address
  })
}
