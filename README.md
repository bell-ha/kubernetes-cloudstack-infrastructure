# 클라우드 네이티브 Kubernetes 클러스터 인프라

CloudStack에 프로덕션급 Kubernetes 클러스터를 구현하고 자동화된 CI/CD 파이프라인을 통합한 포괄적인 Infrastructure as Code (IaC) 프로젝트입니다.

**작성자:** 이종하 | **프로젝트:** 인프라 설계 및 구현

---

## 📋 프로젝트 개요

이 프로젝트는 엔드-투-엔드 클라우드 인프라 설계 및 배포를 다음과 같은 특징으로 시연합니다:

- **Infrastructure as Code (IaC)**: Terraform을 사용하여 CloudStack의 컴퓨팅 리소스 프로비저닝
- **구성 관리**: Ansible을 사용하여 다중 노드 Kubernetes 클러스터 설정 조율
- **컨테이너 오케스트레이션**: Ubuntu 24.04에서 실행되는 Kubernetes (v1.30)
- **DevOps 파이프라인**: GitLab, Jenkins 및 비공개 Docker Registry
- **로드 밸런싱**: MetalLB를 사용하여 클러스터 외부에 서비스 노출

### 아키텍처 하이라이트

```
┌─────────────────────────────────────────────────────────────┐
│                      CloudStack (DKU)                       │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │   마스터     │    │    GitLab    │    │   워커       │   │
│  │  (2 코어)    │    │  (4 코어)    │    │  (1 코어)    │   │
│  │ k8s-master   │    │ k8s-gitlab   │    │ k8s-worker   │   │
│  └──────────────┘    └──────────────┘    └──────────────┘   │
│      네트워크: 192.168.50.0/24                               │
│      CNI: Calico, 로드 밸런서: MetalLB                      │
└─────────────────────────────────────────────────────────────┘
│
└─ 공개 IP 및 포트 포워딩
   ├─ SSH 마스터:   22    → Master:22
   ├─ SSH GitLab:   2201  → GitLab:22
   ├─ SSH 워커:     2202  → Worker:22
   ├─ Jenkins UI:   30880 (NodePort)
   ├─ GitLab UI:    30080 (NodePort)
   ├─ Registry:     30500 (비공개 Docker Registry)
   └─ TestApp:      30001 (테스트 애플리케이션)
```

---

## 🏗️ 인프라 컴포넌트

### 1. **Terraform 구성** (`terraform/`)

CloudStack에서 자동화된 인프라 프로비저닝:

| 리소스 | 구성 | 목적 |
|----------|---------------|---------|
| **네트워크** | 192.168.50.0/24 | 클러스터용 격리 네트워크 |
| **인스턴스** | 3개 VM | 마스터 (2코어), GitLab (4코어), 워커 (1코어) |
| **공개 IP** | 1개 탄력형 IP | 외부 접근 지점 |
| **포트 포워딩** | TCP 규칙 | SSH 및 서비스 접근 |
| **방화벽 규칙** | 송신 모두 허용 | 클러스터 외부 연결성 |

**주요 기능:**
- 매개변수화된 구성 (CPU 제공, 템플릿)
- 대기 조건을 사용한 의존성 관리
- 공개 IP 프로비저닝 및 자동 포트 포워딩
- 초기 VM 설정을 위한 Cloud-init 사용자 데이터

### 2. **Ansible 자동화** (`ansible/`)

다단계 클러스터 초기화 및 애플리케이션 배포:

#### **단계 1: k8s_master**
- DNS/호스트명 구성 (8.8.8.8, 1.1.1.1)
- APT 저장소 설정 (Ubuntu 24.04 Noble)
- 컨테이너 런타임: `containerd` with SystemdCgroup
- 공식 저장소를 통한 Kubernetes v1.30 설치
- 포드 네트워크 CIDR: 192.168.0.0/16
- 자동 조인 명령 생성을 통한 `kubeadm init`
- ubuntu 사용자용 kubeconfig 설정

#### **단계 2: k8s_cni**
- Calico CNI 배포 (v3.27.3)
- 네트워크 정책 적용
- 포드 간 통신 라우팅

#### **단계 3: k8s_worker**
- 동일한 컨테이너 런타임 및 K8s 도구 설치
- 레지스트리 미러 구성 (Docker.io, Quay.io, GCR, K8s)
- 워커 노드가 자동으로 클러스터 조인

#### **단계 4: k8s_metallb**
- 서비스 노출을 위한 MetalLB 로드 밸런서
- Layer 2 모드 구성
- NodePort 서비스용 IP 풀

#### **단계 5: k8s_apps**
- **Local Path Provisioner**: 영구 볼륨 지원
- **GitLab 배포**: 버전 제어 및 아티팩트 저장소
- **Jenkins 배포**: CI/CD 파이프라인 오케스트레이션
- **Docker Registry**: 비공개 컨테이너 이미지 레지스트리

**오케스트레이션 흐름:**
```
마스터 준비 → CNI 활성화 → 워커 조인 → MetalLB 준비 → 앱 배포
```

---

## 🐳 컨테이너 및 Kubernetes 컴포넌트

### **Docker Registry** (`manifests/registry/`)
- **이미지**: 공식 Docker Registry
- **스토리지**: PersistentVolumeClaim (50Gi)
- **포트**: 30500 (NodePort)
- **접근**: `192.168.50.131:30500/testapp:latest`

### **GitLab** (`manifests/gitlab/`)
- **이미지**: `gitlab/gitlab-ce:latest`
- **스토리지**: PersistentVolumeClaim (100Gi)
- **인증정보**: 
  - 루트 비밀번호: `SuperStrongPass!2025`
  - 루트 이메일: `root@example.com`
- **포트**: 30080 (HTTP), 22 (SSH)
- **저장소**: 테스트 애플리케이션 소스 코드 호스팅

### **Jenkins** (`manifests/jenkins/`)
- **이미지**: `jenkins/jenkins:lts`
- **스토리지**: PersistentVolumeClaim (50Gi)
- **포트**: 30880 (HTTP)
- **실행자**: Kaniko 빌더를 사용한 Kubernetes 플러그인
- **파이프라인**: 자동화된 빌드, 테스트 및 배포

### **테스트 애플리케이션** (`testapp/`)

**Flask 애플리케이션:**
```python
# 포드 호스트명을 반환하는 간단한 웹 앱
- 경로: GET /
- 응답: "Hello! My name is LEE JONG HA!! {pod_hostname}"
- 포트: 8080
```

**Docker 이미지:**
- 기본 이미지: `python:3.10-slim`
- 의존성: Flask
- 레지스트리: `192.168.50.131:30500`의 비공개 레지스트리

**Kubernetes 배포:**
- 복제본: 1개
- 서비스 유형: NodePort (30001)
- 이미지 풀 정책: Always
- 레지스트리: 인증정보가 있는 비공개 레지스트리

---

## 🔄 CI/CD 파이프라인

### **Jenkins 파이프라인** (`testapp/Jenkinsfile`)

```groovy
파이프라인 단계:
  1. Clone         → GitLab에서 가져오기 (http://192.168.50.131:30080)
  2. Build Image   → Kaniko 실행자 (멀티플랫폼 빌드)
  3. Push Registry → 비공개 레지스트리 (30500)
  4. Deploy K8s    → 클러스터에 매니페스트 적용
```

**기능:**
- 컨테이너화된 Kaniko 빌더 (Docker 데몬 불필요)
- 안전하지 않은 레지스트리 지원
- Kubernetes에 자동 배포
- 내부 레지스트리용 TLS 검증 건너뛰기

---

## 📊 네트워크 아키텍처

### **포트 매핑**

| 서비스 | 내부 포트 | 외부 포트 | 프로토콜 | 노드 |
|--------|--------------|---------------|----------|------|
| SSH 마스터 | 22 | 22 | TCP | Master |
| SSH GitLab | 22 | 2201 | TCP | GitLab |
| SSH 워커 | 22 | 2202 | TCP | Worker |
| Jenkins UI | 8080 | 30880 | TCP | Cluster |
| GitLab UI | 80 | 30080 | TCP | Cluster |
| Registry | 5000 | 30500 | TCP | Cluster |
| TestApp | 8080 | 30001 | TCP | Cluster |

### **DNS 및 해석**
- 내부: 클러스터 DNS (CoreDNS)
- 외부: Google DNS (8.8.8.8), Cloudflare (1.1.1.1)
- `/etc/hosts`를 통한 호스트명 해석

---

## 🚀 배포 지침

### **필수 요구사항**
- Terraform CLI (>= 1.0)
- Ansible (>= 2.9)
- CloudStack 인증정보 (API 키, 비밀키)
- 원격 접근용 SSH 키

### **단계 1: 인프라 프로비저닝**

```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

**출력:**
```
public_ip  = "x.x.x.x"
master_ip  = "192.168.50.xxx"
gitlab_ip  = "192.168.50.xxx"
worker_ip  = "192.168.50.xxx"
jenkins_url = "http://x.x.x.x:30880"
gitlab_url  = "http://x.x.x.x:30080"
```

### **단계 2: Ansible 인벤토리 업데이트**

```bash
cd ../ansible/
# inventory/hosts.ini.tmpl을 Terraform 출력으로 편집
mv inventory/hosts.ini.tmpl inventory/hosts.ini
# ${public_ip}을 실제 공개 IP로 교체
```

### **단계 3: 클러스터 구성**

```bash
# 연결 테스트
ansible -i inventory/hosts.ini all -m ping

# 전체 플레이북 실행
ansible-playbook -i inventory/hosts.ini site.yml -v
```

### **단계 4: 클러스터 검증**

```bash
# 마스터에 SSH 접속
ssh -i ~/.ssh/your-key ubuntu@${PUBLIC_IP}

# 클러스터 상태 확인
kubectl get nodes -o wide
kubectl get pods --all-namespaces
kubectl get services --all-namespaces
```

---

## 📈 주요 기술 및 시연 기술

### **인프라 및 IaC**
- ✅ Terraform: 다중 리소스 오케스트레이션, 상태 관리
- ✅ CloudStack: 공용 클라우드 프로비저닝, 네트워킹
- ✅ 네트워킹: 포트 포워딩, 방화벽 규칙, 격리 네트워크

### **구성 관리**
- ✅ Ansible: 다단계 플레이북, 역할, 핸들러
- ✅ 시스템 관리: DNS, APT 저장소, Linux 네트워킹
- ✅ 컨테이너 런타임: Containerd 구성, 레지스트리 미러

### **Kubernetes 및 오케스트레이션**
- ✅ kubeadm: 클러스터 부트스트랩 및 노드 조인
- ✅ CNI: Calico 네트워크 정책 구현
- ✅ 로드 밸런싱: MetalLB 서비스 노출
- ✅ 스토리지: 영구 볼륨 및 로컬 경로 프로비저닝
- ✅ 매니페스트: 배포, 서비스, PersistentVolumeClaim

### **DevOps 및 CI/CD**
- ✅ Jenkins: 파이프라인-코드, Kubernetes 포드 실행
- ✅ GitLab: 저장소 호스팅, 아티팩트 저장소
- ✅ Docker: 이미지 빌드 (Kaniko), 레지스트리 관리
- ✅ 컨테이너 보안: 비공개 레지스트리, 안전하지 않은 모드 처리

### **Python 및 애플리케이션 개발**
- ✅ Flask: 경량 웹 프레임워크
- ✅ Docker: 슬림 기본 이미지로 컨테이너화
- ✅ 배포: Kubernetes 네이티브 애플리케이션 배포

---

## 🔐 보안 고려사항

### **구현됨**
- ✅ 클러스터용 격리 네트워크 (192.168.50.0/24)
- ✅ 포트 포워딩: SSH 선택적으로 노출
- ✅ 비공개 Docker 레지스트리: 공개 접근 불가
- ✅ SystemdCgroup: 향상된 컨테이너 리소스 격리

### **프로덕션용 권장사항**
- [ ] 서비스 통신용 TLS 활성화
- [ ] RBAC (Role-Based Access Control) 구현
- [ ] 관리형 비밀 사용 (Sealed Secrets, Vault)
- [ ] 네트워크 정책 활성화 (Calico)
- [ ] Pod 보안 정책 구현
- [ ] 비공개 SSH 키 사용 (비밀번호 인증 회피)
- [ ] 로깅 및 모니터링 활성화 (Prometheus, ELK)

---

## 📁 프로젝트 구조

```
.
├── terraform/              # 인프라 프로비저닝
│   ├── main.tf            # 리소스 정의
│   ├── variables.tf       # 매개변수화된 입력
│   ├── outputs.tf         # 리소스 정보 내보내기
│   └── provider.tf        # CloudStack 공급자 구성
│
├── ansible/               # 클러스터 구성
│   ├── playbook.yaml      # 주 플레이북 엔트리
│   ├── site.yml           # 전체 클러스터 플레이북
│   ├── ansible.cfg        # Ansible 구성
│   ├── inventory/         # 호스트 인벤토리
│   │   ├── hosts.ini      # 호스트 정의
│   │   └── hosts.ini.tmpl # 변수가 있는 템플릿
│   └── roles/
│       ├── k8s_master/    # 마스터 노드 설정
│       ├── k8s_cni/       # CNI 배포
│       ├── k8s_worker/    # 워커 노드 설정
│       └── k8s_metallb/   # 로드 밸런서
│
├── manifests/             # Kubernetes 매니페스트
│   ├── gitlab/           # GitLab 배포
│   ├── jenkins/          # Jenkins 배포
│   └── registry/         # Docker 레지스트리
│
├── testapp/              # 샘플 애플리케이션
│   ├── src/
│   │   └── app.py       # Flask 애플리케이션
│   ├── Dockerfile       # 컨테이너 이미지
│   ├── Jenkinsfile      # CI/CD 파이프라인
│   └── k8s/
│       ├── deployment.yaml
│       └── service.yaml
│
└── README.md            # 이 파일
```

---

## 🎯 학습 성과 및 성취

이 프로젝트는 다음을 시연합니다:

1. **엔드-투-엔드 인프라 설계**: VM 프로비저닝에서 애플리케이션 배포까지
2. **Infrastructure as Code**: 재현 가능하고 버전 관리되는 인프라
3. **자동화 및 오케스트레이션**: 수동 작업 및 인적 오류 감소
4. **클라우드 네이티브 아키텍처**: Kubernetes 우선 설계 및 확장성
5. **DevOps 베스트 프랙티스**: CI/CD 통합, 컨테이너화, 인프라 자동화
6. **문제 해결 기술**: 네트워크 디버깅, Kubernetes 포드 관리, Ansible 플레이

---

## 📝 라이선스 및 저작권

이 프로젝트는 인프라 설계 및 구현 학과의 학술 과정의 일부로 작성되었습니다.

**연락처:** 이종하

---

## 🤝 기여 및 지원

이 인프라에 대한 질문이나 개선사항:

1. Kubernetes 문서 검토: https://kubernetes.io/docs/
2. Ansible 베스트 프랙티스 확인: https://docs.ansible.com/
3. Terraform CloudStack 공급자 참조: https://registry.terraform.io/providers/cloudstack/cloudstack/latest
4. GitLab 문서: https://docs.gitlab.com/
5. Jenkins 문서: https://www.jenkins.io/doc/

---

**마지막 업데이트:** 2025-12-10 | **버전:** 1.0
