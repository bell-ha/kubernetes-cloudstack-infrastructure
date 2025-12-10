# Cloud-Native Kubernetes Cluster Infrastructure

A comprehensive Infrastructure as Code (IaC) project implementing a production-grade Kubernetes cluster on CloudStack with automated CI/CD pipeline integration.

**Author:** Lee Jong Ha (이종하) | **Project:** Infrastructure Design & Implementation

---

## 📋 Project Overview

This project demonstrates end-to-end cloud infrastructure design and deployment, featuring:

- **Infrastructure as Code (IaC)** using Terraform to provision compute resources on CloudStack
- **Configuration Management** using Ansible to orchestrate multi-node Kubernetes cluster setup
- **Container Orchestration** with Kubernetes (v1.30) running on Ubuntu 24.04
- **DevOps Pipeline** with GitLab, Jenkins, and private Docker Registry
- **Load Balancing** using MetalLB for exposing services outside the cluster

### Architecture Highlights

```
┌─────────────────────────────────────────────────────────────┐
│                      CloudStack (DKU)                       │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │   Master     │    │    GitLab    │    │   Worker     │   │
│  │  (2 Core)    │    │  (4 Core)    │    │  (1 Core)    │   │
│  │ k8s-master   │    │ k8s-gitlab   │    │ k8s-worker   │   │
│  └──────────────┘    └──────────────┘    └──────────────┘   │
│      Network: 192.168.50.0/24                               │
│      CNI: Calico, Load Balancer: MetalLB                    │
└─────────────────────────────────────────────────────────────┘
│
└─ Public IP with Port Forwarding
   ├─ SSH Master:   22    → Master:22
   ├─ SSH GitLab:   2201  → GitLab:22
   ├─ SSH Worker:   2202  → Worker:22
   ├─ Jenkins UI:   30880 (NodePort)
   ├─ GitLab UI:    30080 (NodePort)
   ├─ Registry:     30500 (Private Docker Registry)
   └─ TestApp:      30001 (Test Application)
```

---

## 🏗️ Infrastructure Components

### 1. **Terraform Configuration** (`terraform/`)

Automated infrastructure provisioning on CloudStack:

| Resource | Configuration | Purpose |
|----------|---------------|---------|
| **Network** | 192.168.50.0/24 | Isolated network for cluster |
| **Instances** | 3 VMs | Master (2 core), GitLab (4 core), Worker (1 core) |
| **Public IP** | 1 Elastic IP | External access point |
| **Port Forwarding** | TCP Rules | SSH & Service Access |
| **Firewall Rules** | Egress Allow All | Cluster external connectivity |

**Key Features:**
- Parameterized configuration (CPU offerings, templates)
- Dependency management with wait conditions
- Public IP provisioning with automatic port forwarding
- Cloud-init user data for initial VM setup

### 2. **Ansible Automation** (`ansible/`)

Multi-stage cluster initialization and application deployment:

#### **Stage 1: k8s_master**
- DNS/hostname configuration (8.8.8.8, 1.1.1.1)
- APT repository setup (Ubuntu 24.04 Noble)
- Container runtime: `containerd` with SystemdCgroup
- Kubernetes v1.30 installation via official repos
- Pod network CIDR: 192.168.0.0/16
- `kubeadm init` with automatic join command generation
- kubeconfig setup for ubuntu user

#### **Stage 2: k8s_cni**
- Calico CNI deployment (v3.27.3)
- Network policy enforcement
- Pod-to-pod communication routing

#### **Stage 3: k8s_worker**
- Identical container runtime & K8s tools installation
- Registry mirror configuration (Docker.io, Quay.io, GCR, K8s)
- Worker node joins cluster automatically

#### **Stage 4: k8s_metallb**
- MetalLB load balancer for service exposure
- Layer 2 mode configuration
- IP pool for NodePort services

#### **Stage 5: k8s_apps**
- **Local Path Provisioner**: Persistent volume support
- **GitLab Deployment**: Version control & artifact storage
- **Jenkins Deployment**: CI/CD pipeline orchestration
- **Docker Registry**: Private container image registry

**Orchestration Flow:**
```
Master Ready → CNI Enabled → Workers Join → MetalLB Ready → Apps Deploy
```

---

## 🐳 Container & Kubernetes Components

### **Docker Registry** (`manifests/registry/`)
- **Image**: Official Docker Registry
- **Storage**: PersistentVolumeClaim (50Gi)
- **Port**: 30500 (NodePort)
- **Access**: `192.168.50.131:30500/testapp:latest`

### **GitLab** (`manifests/gitlab/`)
- **Image**: `gitlab/gitlab-ce:latest`
- **Storage**: PersistentVolumeClaim (100Gi)
- **Credentials**: 
  - Root Password: `SuperStrongPass!2025`
  - Root Email: `root@example.com`
- **Ports**: 30080 (HTTP), 22 (SSH)
- **Repository**: Hosts test application source code

### **Jenkins** (`manifests/jenkins/`)
- **Image**: `jenkins/jenkins:lts`
- **Storage**: PersistentVolumeClaim (50Gi)
- **Port**: 30880 (HTTP)
- **Executor**: Kubernetes plugin with Kaniko builder
- **Pipeline**: Automated build, test, and deploy

### **Test Application** (`testapp/`)

**Flask Application:**
```python
# Simple web app returning pod hostname
- Route: GET /
- Response: "Hello! My name is LEE JONG HA!! {pod_hostname}"
- Port: 8080
```

**Docker Image:**
- Base: `python:3.10-slim`
- Dependency: Flask
- Registry: Private registry at `192.168.50.131:30500`

**Kubernetes Deployment:**
- Replicas: 1
- Service Type: NodePort (30001)
- Image Pull Policy: Always
- Registry: Private registry with credentials

---

## 🔄 CI/CD Pipeline

### **Jenkins Pipeline** (`testapp/Jenkinsfile`)

```groovy
Pipeline Stages:
  1. Clone         → Fetch from GitLab (http://192.168.50.131:30080)
  2. Build Image   → Kaniko executor (multi-platform builds)
  3. Push Registry → Private registry (30500)
  4. Deploy K8s    → Apply manifests to cluster
```

**Features:**
- Containerized Kaniko builder (no Docker daemon required)
- Insecure registry support
- Automated deployment to Kubernetes
- TLS verification skip for internal registry

---

## 📊 Network Architecture

### **Port Mapping**

| Service | Internal Port | External Port | Protocol | Node |
|---------|--------------|---------------|----------|------|
| SSH Master | 22 | 22 | TCP | Master |
| SSH GitLab | 22 | 2201 | TCP | GitLab |
| SSH Worker | 22 | 2202 | TCP | Worker |
| Jenkins UI | 8080 | 30880 | TCP | Cluster |
| GitLab UI | 80 | 30080 | TCP | Cluster |
| Registry | 5000 | 30500 | TCP | Cluster |
| TestApp | 8080 | 30001 | TCP | Cluster |

### **DNS & Resolution**
- Internal: Cluster DNS (CoreDNS)
- External: Google DNS (8.8.8.8), Cloudflare (1.1.1.1)
- Hostname resolution via `/etc/hosts`

---

## 🚀 Deployment Instructions

### **Prerequisites**
- Terraform CLI (>= 1.0)
- Ansible (>= 2.9)
- CloudStack credentials (API key, Secret key)
- SSH key for remote access

### **Step 1: Infrastructure Provisioning**

```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

**Outputs:**
```
public_ip  = "x.x.x.x"
master_ip  = "192.168.50.xxx"
gitlab_ip  = "192.168.50.xxx"
worker_ip  = "192.168.50.xxx"
jenkins_url = "http://x.x.x.x:30880"
gitlab_url  = "http://x.x.x.x:30080"
```

### **Step 2: Update Ansible Inventory**

```bash
cd ../ansible/
# Edit inventory/hosts.ini.tmpl with Terraform outputs
mv inventory/hosts.ini.tmpl inventory/hosts.ini
# Replace ${public_ip} with actual public IP
```

### **Step 3: Cluster Configuration**

```bash
# Test connectivity
ansible -i inventory/hosts.ini all -m ping

# Run full playbook
ansible-playbook -i inventory/hosts.ini site.yml -v
```

### **Step 4: Verify Cluster**

```bash
# SSH to master
ssh -i ~/.ssh/your-key ubuntu@${PUBLIC_IP}

# Check cluster status
kubectl get nodes -o wide
kubectl get pods --all-namespaces
kubectl get services --all-namespaces
```

---

## 📈 Key Technologies & Skills Demonstrated

### **Infrastructure & IaC**
- ✅ Terraform: Multi-resource orchestration, state management
- ✅ CloudStack: Public cloud provisioning, networking
- ✅ Networking: Port forwarding, firewall rules, isolated networks

### **Configuration Management**
- ✅ Ansible: Multi-stage playbooks, roles, handlers
- ✅ System Administration: DNS, APT repositories, Linux networking
- ✅ Container Runtime: Containerd configuration, registry mirrors

### **Kubernetes & Orchestration**
- ✅ kubeadm: Cluster bootstrap and node joining
- ✅ CNI: Calico network policy implementation
- ✅ Load Balancing: MetalLB service exposure
- ✅ Storage: Persistent volumes & local path provisioning
- ✅ Manifests: Deployments, Services, PersistentVolumeClaims

### **DevOps & CI/CD**
- ✅ Jenkins: Pipeline-as-code, Kubernetes pod execution
- ✅ GitLab: Repository hosting, artifact storage
- ✅ Docker: Image building (Kaniko), registry management
- ✅ Container Security: Private registry, insecure mode handling

### **Python & Application Development**
- ✅ Flask: Lightweight web framework
- ✅ Docker: Containerization with slim base images
- ✅ Deployment: Kubernetes-native application deployment

---

## 🔐 Security Considerations

### **Implemented**
- ✅ Isolated network (192.168.50.0/24) for cluster
- ✅ Port forwarding: SSH exposed selectively
- ✅ Private Docker registry: No public access
- ✅ SystemdCgroup: Enhanced container resource isolation

### **Recommendations for Production**
- [ ] Enable TLS for service communication
- [ ] Implement RBAC (Role-Based Access Control)
- [ ] Use managed secrets (Sealed Secrets, Vault)
- [ ] Enable Network Policies (Calico)
- [ ] Implement Pod Security Policies
- [ ] Use private SSH keys (avoid password auth)
- [ ] Enable logging & monitoring (Prometheus, ELK)

---

## 📁 Project Structure

```
.
├── terraform/              # Infrastructure provisioning
│   ├── main.tf            # Resource definitions
│   ├── variables.tf       # Parameterized inputs
│   ├── outputs.tf         # Export resource info
│   └── provider.tf        # CloudStack provider config
│
├── ansible/               # Cluster configuration
│   ├── playbook.yaml      # Main playbook entry
│   ├── site.yml           # Full cluster playbook
│   ├── ansible.cfg        # Ansible configuration
│   ├── inventory/         # Host inventory
│   │   ├── hosts.ini      # Host definitions
│   │   └── hosts.ini.tmpl # Template with variables
│   └── roles/
│       ├── k8s_master/    # Master node setup
│       ├── k8s_cni/       # CNI deployment
│       ├── k8s_worker/    # Worker node setup
│       └── k8s_metallb/   # Load balancer
│
├── manifests/             # Kubernetes manifests
│   ├── gitlab/           # GitLab deployment
│   ├── jenkins/          # Jenkins deployment
│   └── registry/         # Docker registry
│
├── testapp/              # Sample application
│   ├── src/
│   │   └── app.py       # Flask application
│   ├── Dockerfile       # Container image
│   ├── Jenkinsfile      # CI/CD pipeline
│   └── k8s/
│       ├── deployment.yaml
│       └── service.yaml
│
└── README.md            # This file
```

---

## 🎯 Learning Outcomes & Achievements

This project demonstrates:

1. **End-to-End Infrastructure Design**: From VM provisioning to application deployment
2. **Infrastructure as Code**: Reproducible, version-controlled infrastructure
3. **Automation & Orchestration**: Reducing manual effort and human error
4. **Cloud-Native Architecture**: Kubernetes-first design with scalability
5. **DevOps Best Practices**: CI/CD integration, containerization, infrastructure automation
6. **Troubleshooting Skills**: Network debugging, Kubernetes pod management, Ansible plays

---

## 📝 License & Attribution

This project is created as part of academic coursework in Infrastructure Design & Implementation.

**Contact:** Lee Jong Ha (이종하)

---

## 🤝 Contributing & Support

For questions or improvements to this infrastructure:

1. Review the Kubernetes documentation: https://kubernetes.io/docs/
2. Check Ansible best practices: https://docs.ansible.com/
3. Refer to Terraform CloudStack provider: https://registry.terraform.io/providers/cloudstack/cloudstack/latest
4. GitLab documentation: https://docs.gitlab.com/
5. Jenkins documentation: https://www.jenkins.io/doc/

---

**Last Updated:** 2025-12-10 | **Version:** 1.0
