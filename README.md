# Kubernetes 클러스터 인프라 구축

공인 IP 하나, 로드밸런서 없는 사설 클라우드에 세운 3노드 클러스터

포트폴리오: https://bell-ha.github.io/projects/k8s-infra/

**작성자:** 이종하 | **기간:** 2025.09 ~ 2025.12

---

## 개요

사설 CloudStack(DKU 존) 위에 Terraform으로 VM 3대를 만들고, Ansible로 Kubernetes v1.30 클러스터를 세운 뒤 GitLab, Jenkins, 사설 Docker Registry를 올렸습니다. GitLab에 올린 테스트 앱을 Jenkins가 Kaniko로 빌드해 레지스트리에 넣고 클러스터에 배포합니다.

퍼블릭 클라우드가 아니라서 `type: LoadBalancer` 서비스에 로드밸런서를 붙여 주는 장치가 없고, 공인 IP도 하나만 받습니다. 이 두 가지가 설계 제약의 대부분이었습니다.

- **프로비저닝**: Terraform (CloudStack provider 0.5)
- **구성 관리**: Ansible 롤 5개
- **클러스터**: kubeadm, Kubernetes v1.30, Ubuntu 24.04, containerd, Calico
- **CI/CD**: GitLab, Jenkins(Kaniko), 사설 Docker Registry
- **외부 노출**: 공인 IP 하나에 포트포워딩을 걸어 NodePort로 전달

### 구성

```
CloudStack (DKU 존), 격리 네트워크 192.168.50.0/24, CNI Calico

  [k8s-master]          [k8s-gitlab]          [k8s-worker]
  control plane         worker1               worker2
  2 cores               4 cores               1 core

        ▲
        │ 공인 IP 하나, 포트포워딩
        │
   SSH      22    → k8s-master:22
   SSH      2201  → k8s-gitlab:22
   SSH      2202  → k8s-worker:22
   GitLab   30080 → k8s-gitlab:30080  (NodePort)
   Jenkins  32080 → k8s-master:32080  (NodePort)
   Registry 30500 → k8s-gitlab:30500  (NodePort)
```

`k8s-gitlab` VM은 이름과 달리 GitLab 전용 서버가 아니라 클러스터에 조인하는 워커입니다. 인벤토리에서는 `worker1`(포트 2201)이고, `k8s-worker`가 `worker2`(포트 2202)입니다. GitLab 파드가 어느 노드에 뜰지는 스케줄러가 정합니다.

### 한계

- 마스터가 1대라 마스터가 멈추면 클러스터도 멈춥니다.
- MetalLB를 설치해 IP 풀과 L2Advertisement까지 구성했지만, 외부 접근에는 쓰지 않습니다. 실제 외부 접근은 공인 IP의 포트포워딩에서 NodePort로 내려가는 경로뿐입니다.
- 테스트 앱의 NodePort 30001은 포트포워딩 규칙이 없어 클러스터 네트워크 안에서만 접근됩니다.

---

## 설계에서 정한 것

### 공인 IP 하나, 포트 규약을 먼저 정함

공인 IP가 하나라 포트 규약을 먼저 정했습니다. SSH는 22, 2201, 2202로 노드를 나누고, 서비스는 매니페스트에서 NodePort 번호를 고정한 뒤 그 번호를 그대로 외부 포트로 통과시켰습니다. 서비스가 늘 때마다 포트가 충돌하지 않게 하려는 것입니다. 포트포워딩과 방화벽 규칙은 모두 `terraform/main.tf`에 있습니다.

### 플레이 순서로 경계를 둠

`ansible/site.yml`은 롤마다 플레이를 나눠 마스터 준비, Calico, 워커 조인, MetalLB, 앱 배포 순으로 실행합니다. 워커는 마스터와 CNI가 준비된 뒤에야 조인할 수 있기 때문입니다.

### 조인 토큰은 파일 대신 메모리로

마스터 롤이 `kubeadm token create --print-join-command`의 결과를 `add_host`로 가상 호스트 `worker_join_info`에 담고, 워커 롤이 `hostvars['worker_join_info'].join_cmd`로 꺼내 실행합니다. 조인 명령을 파일로 남기거나 복사하지 않습니다.

### 재실행

`kubeadm init`에는 `creates: /etc/kubernetes/admin.conf`, 워커 조인에는 `creates: /etc/kubernetes/kubelet.conf` 조건을 걸어 두었습니다. 다만 두 롤 모두 그 앞에서 `kubeadm reset -f`를 실행하므로, 지금 코드로 플레이북을 다시 돌리면 클러스터를 새로 초기화하고 다시 조인합니다.

---

## Terraform (`terraform/`)

| 리소스 | 내용 |
|---|---|
| 네트워크 | 격리 네트워크 192.168.50.0/24 (Source NAT) |
| 인스턴스 | `k8s-master` Medium(2코어), `k8s-gitlab` Large(4코어), `k8s-worker` Small(1코어), 템플릿 `Ubuntu_24.04_VSCode` |
| 공인 IP | 1개 |
| 포트포워딩과 방화벽 | 위 구성도의 TCP 6개 포트 |
| 송신 방화벽 | 전체 허용 |
| 인벤토리 | `hosts.ini.tmpl`에 공인 IP를 넣어 `ansible/inventory/hosts.ini` 생성 (`local_file`) |

공인 IP가 준비될 때까지 `time_sleep`으로 60초 기다린 뒤 포트포워딩을 만듭니다. VM은 cloud-init으로 비밀번호 로그인을 켭니다. CloudStack API 키는 `terraform.tfvars`(git 제외)에서 넣습니다.

## Ansible (`ansible/`)

| 순서 | 롤 | 대상 | 내용 |
|---|---|---|---|
| 1 | `k8s_master` | master | 호스트명과 DNS(8.8.8.8, 1.1.1.1), APT 소스, swap 끄기, containerd(SystemdCgroup, 레지스트리 미러), kubeadm/kubelet/kubectl v1.30, `kubeadm init --pod-network-cidr=192.168.0.0/16`, kubeconfig, 조인 명령 생성 |
| 2 | `k8s_cni` | master | Calico v3.27.3 매니페스트 적용 |
| 3 | `k8s_worker` | workers | APT 소스, swap 끄기, containerd(레지스트리 미러), Kubernetes 도구 설치, 클러스터 조인 |
| 4 | `k8s_metallb` | master | MetalLB v0.14.5 설치, IP 풀 192.168.50.100~200, L2Advertisement |
| 5 | `k8s_apps` | master | local-path-provisioner 설치, `manifests/` 복사 후 GitLab, Jenkins, Registry 적용 |

## 클러스터에 올린 서비스 (`manifests/`)

| 서비스 | 이미지 | PVC | 서비스 포트 → NodePort |
|---|---|---|---|
| GitLab | `gitlab/gitlab-ce:latest` | 10Gi | 80 → 30080 |
| Jenkins | `jenkins/jenkins:lts` | 5Gi | 8080 → 32080 |
| Registry | `registry:2` | 3Gi | 5000 → 30500 |

PVC는 모두 `local-path` 스토리지 클래스를 씁니다. GitLab 초기 root 비밀번호는 배포 시 설정합니다.

## 테스트 앱과 파이프라인 (`testapp/`)

- **앱**: Flask, `GET /`에 파드 호스트명을 붙여 응답, 포트 8080
- **이미지**: `python:3.10-slim` 기반, `192.168.50.131:30500/testapp:latest`로 푸시
- **배포**: Deployment 1개(`imagePullPolicy: Always`), NodePort 30001 (외부 포워딩 없음)

`testapp/Jenkinsfile`의 단계는 세 개입니다.

1. **Clone**: 클러스터 안의 GitLab(`http://192.168.50.131:30080`)에서 `main` 브랜치를 받음
2. **Build Image with Kaniko**: Docker 데몬 없이 Kaniko로 빌드해 레지스트리에 푸시 (`--insecure`, `--skip-tls-verify`)
3. **Deploy to K8s**: `kubectl apply`로 `k8s/deployment.yaml`, `k8s/service.yaml` 적용

에이전트는 Jenkins에 등록해 둔 `kaniko` 파드 템플릿을 상속합니다. 이 템플릿 설정은 저장소에 없습니다.

---

## 실행 방법

### 준비물

- Terraform 1.0 이상
- Ansible, 그리고 비밀번호 SSH 접속용 `sshpass`와 매니페스트 복사용 `rsync`
- CloudStack API 키와 시크릿 키

### 1. 인프라 생성

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars   # API 키 입력
terraform init
terraform apply
```

출력은 `public_ip`, `master_ip`, `gitlab_ip`, `worker_ip`, `jenkins_url`, `gitlab_url`입니다. `outputs.tf`의 `jenkins_url`은 포트가 30880으로 남아 있지만, 실제 Jenkins NodePort와 포워딩 포트는 32080입니다.

`terraform apply`가 `ansible/inventory/hosts.ini`를 공인 IP로 채워 만듭니다. 접속 비밀번호 변수는 템플릿에 없으므로 배포 환경에서 따로 지정합니다.

### 2. 클러스터 구성

```bash
cd ../ansible/
ansible all -m ping
ansible-playbook site.yml
```

### 3. 확인

```bash
ssh ubuntu@<공인 IP>        # 마스터 (22)
kubectl get nodes -o wide   # 노드 3대
kubectl get pods -A
kubectl get svc
```

브라우저에서는 `http://<공인 IP>:30080`(GitLab), `http://<공인 IP>:32080`(Jenkins)로 접속합니다.

---

## 보안 메모

해 둔 것

- 클러스터를 격리 네트워크(192.168.50.0/24)에 두고 공인 IP에는 필요한 포트만 포워딩
- containerd SystemdCgroup 설정

남은 것

- [ ] VM 비밀번호 로그인 대신 SSH 키 사용
- [ ] 레지스트리(30500)가 공인 IP로 열려 있으므로 인증 또는 접근 제한 추가
- [ ] 서비스 간 TLS 적용 (레지스트리는 지금 `--insecure`로 사용)
- [ ] 비밀값을 매니페스트 평문 대신 Secret 또는 외부 비밀 저장소로 관리
- [ ] RBAC 정리
- [ ] Calico 네트워크 정책 작성 (지금은 CNI만 설치하고 정책은 없음)
- [ ] 로깅과 모니터링 (Prometheus 등)
- [ ] 컨트롤 플레인 이중화

---

## 디렉터리 구조

```
.
├── terraform/
│   ├── main.tf                 # 네트워크, VM, 공인 IP, 포트포워딩, 방화벽, 인벤토리 생성
│   ├── variables.tf            # 존, 템플릿, VM 사양, API 접속 정보
│   ├── outputs.tf
│   ├── provider.tf
│   └── terraform.tfvars.example
├── ansible/
│   ├── site.yml                # 롤 순서
│   ├── playbook.yaml           # site.yml import
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── hosts.ini.tmpl      # Terraform이 채우는 템플릿
│   │   └── hosts.ini
│   └── roles/
│       ├── k8s_master/
│       ├── k8s_cni/
│       ├── k8s_worker/
│       ├── k8s_metallb/
│       └── k8s_apps/
├── manifests/
│   ├── gitlab/
│   ├── jenkins/
│   └── registry/
└── testapp/
    ├── src/app.py
    ├── Dockerfile
    ├── Jenkinsfile
    └── k8s/
        ├── deployment.yaml
        └── service.yaml
```
