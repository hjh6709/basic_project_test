# CLAUDE.md — 개인 레포 (hjh6709/basic_project_test)

> 이 파일은 Claude Code가 이 레포지토리에서 작업할 때 참조하는 가이드입니다.
> **이 레포는 팀 레포(Chilseongpa)의 main 브랜치를 복사한 개인 작업용 레포입니다.**
> 모든 인프라는 **정현(본인) 개인 AWS / GCP / Cloudflare 계정**을 사용합니다.

---

## 🧭 프로젝트 개요

**Chilseongpa** — Hybrid Multi-Cloud AIOps Platform

GCP(Primary) / AWS(Standby) K3s 클러스터 + Prometheus 기반 모니터링 + Gemini API 장애 분석 Discord Bot으로 구성된 고가용성 멀티클라우드 운영 플랫폼.

```
Users
  ↓
Cloudflare Load Balancer (DNS Failover + Health Check + Zero Trust Tunnel)
  ↓
GCP K3s Cluster (Primary)        AWS K3s Cluster (Standby)
  └→ Cloud SQL Auth Proxy ─────────┘
             ↓
       GCP Cloud SQL (단일 DB)

AWS Monitoring (별도 독립 서버)
  ├ Prometheus
  ├ Grafana
  └ Alertmanager → Discord Bot → Gemini API
```

---

## ⚠️ 개인 레포 작업 시 필수 주의사항

### 계정 분리
이 레포는 팀 레포 코드를 복사한 것이므로 **계정 정보는 전부 본인 개인 계정으로 교체**해야 합니다.
팀 레포의 값(도메인, 프로젝트 ID, 계정 ID 등)을 그대로 사용하면 **충돌 또는 팀 인프라에 영향**을 줄 수 있습니다.

| 항목 | 팀 레포 기본값 | 개인 레포에서 교체할 값 위치 |
|------|--------------|---------------------------|
| GCP Project ID | `your-gcp-project-id` | `infra/terraform/terraform.tfvars` |
| Cloudflare Account ID | `your-cloudflare-account-id` | `infra/terraform/terraform.tfvars` |
| Cloudflare Zone ID | `your-cloudflare-zone-id` | `infra/terraform/terraform.tfvars` |
| Cloudflare API Token | `your-cloudflare-api-token` | `infra/terraform/terraform.tfvars` |
| AWS Key Pair 이름 | `chilseongpa_keypair` | `infra/terraform/terraform.tfvars` |
| 앱 도메인 | `app.bucheongoyangijanggun.com` | `infra/terraform/terraform.tfvars` 또는 `variables.tf` default |
| Grafana 도메인 | `grafana.bucheongoyangijanggun.com` | 동일 |
| Prometheus 도메인 | `prometheus.bucheongoyangijanggun.com` | 동일 |
| Discord Bot Token | (팀 공용) | `infra/ansible/group_vars/all.yml` 환경변수 |
| Discord Channel ID | `123456789012345678` | `infra/ansible/group_vars/all.yml` |
| Gemini API Key | (팀 공용) | 환경변수 `GEMINI_API_KEY` |

> `terraform.tfvars`는 `.gitignore`에 등록되어 있으므로 Git에 올라가지 않습니다.
> 절대로 secrets 값을 코드에 하드코딩하거나 커밋하지 마세요.

---

## 📁 디렉토리 구조

```
.
├── CLAUDE.md                          ← 이 파일
├── infra/
│   ├── terraform/
│   │   ├── main.tf                    ← Provider 설정 + 모듈 호출 (Cloudflare → AWS → GCP 순)
│   │   ├── variables.tf               ← 전체 변수 선언
│   │   ├── outputs.tf                 ← 배포 후 출력값 (IP, SSH 명령어 등)
│   │   ├── terraform.tfvars.example   ← 이걸 복사해서 terraform.tfvars 생성 (⚠️ gitignore)
│   │   ├── ansible_inventory.tf       ← Terraform이 inventory.ini 자동 생성
│   │   ├── ssh_config_setup.sh        ← SSH ProxyJump 설정 자동화
│   │   └── modules/
│   │       ├── aws/                   ← VPC, EC2 (Bastion/K3s/Monitoring), SG, EBS
│   │       ├── gcp/                   ← Compute Engine, Cloud SQL, Firewall
│   │       └── cloudflare/            ← Tunnel 3개, Load Balancer, Origin Pool, Health Check
│   └── ansible/
│       ├── playbook.yml               ← 전체 구성 플레이북
│       ├── ansible.cfg
│       ├── group_vars/all.yml         ← 공통 변수 (secrets는 env 참조)
│       └── roles/
│           ├── node-exporter/         ← 전 서버 공통 설치
│           ├── k3s/                   ← GCP/AWS K3s 설치
│           ├── docker/                ← Monitoring 서버 Docker 설치
│           └── monitoring/            ← Prometheus + Grafana + Alertmanager + Discord Bot
│               └── templates/         ← Jinja2 템플릿 (prometheus.yml.j2, alert.rules.yml.j2 등)
├── application/
│   ├── backend/                       ← 백엔드 API (Dockerfile, /metrics 엔드포인트 포함)
│   ├── k8s/                           ← Kubernetes 매니페스트 (deployment, service, ingress 등)
│   └── k6/                            ← 부하 테스트 스크립트 (k6)
└── aiops/
    └── discord-bot/                   ← Python Discord Bot (Alertmanager webhook → Gemini API)
```

---

## 🔑 Secrets 관리 규칙

다음 파일들은 **절대 Git 커밋 금지** (`.gitignore` 등록 확인):

```
infra/terraform/terraform.tfvars     ← 클라우드 credentials 전체
infra/ansible/inventory.ini          ← Terraform이 자동 생성하는 서버 IP 목록
infra/ansible/secrets.sh             ← Ansible Vault 비밀번호 및 env 변수
```

환경변수로 주입하는 Secrets:
```bash
export TF_VAR_gcp_project_id="본인-gcp-project-id"
export TF_VAR_gcp_credentials="/path/to/service-account.json"
export DISCORD_BOT_TOKEN="본인-discord-bot-token"
export DISCORD_CHANNEL_ID="본인-channel-id"
export GEMINI_API_KEY="본인-gemini-api-key"
```

---

## 🚀 배포 순서

### 1단계 — Terraform (인프라 프로비저닝)

```bash
cd infra/terraform

# terraform.tfvars 준비 (최초 1회)
cp terraform.tfvars.example terraform.tfvars
# → terraform.tfvars를 열어 본인 계정 값으로 전부 교체

terraform init
terraform plan    # 변경사항 확인
terraform apply   # 실제 배포

# SSH config 자동 생성 (Bastion ProxyJump 설정)
bash ssh_config_setup.sh
```

> **모듈 실행 의존성 순서**: Cloudflare 먼저 → AWS → GCP
> Cloudflare 모듈이 터널 토큰 3개를 생성하고, 해당 토큰이 AWS/GCP EC2 user_data에 주입됩니다.

### 2단계 — Ansible (서버 구성)

```bash
cd infra/ansible

# 환경변수 로드
source secrets.sh

# 연결 확인
ansible all -m ping

# 전체 구성 실행
ansible-playbook playbook.yml

# 선택적 실행
ansible-playbook playbook.yml --limit gcp-main        # GCP K3s만
ansible-playbook playbook.yml --limit aws-sub          # AWS K3s만
ansible-playbook playbook.yml --limit aws-monitor      # Monitoring만
ansible-playbook playbook.yml -e "storage_setup_enabled=false"  # EBS 없이
```

### 3단계 — Kubernetes (애플리케이션 배포)

```bash
cd application/k8s
kubectl apply -f namespace.yaml
kubectl apply -f .
```

### 4단계 — 부하 테스트

```bash
cd application/k6

# Docker 기반 실행 (권장)
docker build -t chilseongpa-k6 .
docker run --rm --ulimit nofile=65535:65535 \
  --env-file .env.testk6 \
  -v "${PWD}:/work" -w /work \
  chilseongpa-k6 run scenarios/single_api_load.js \
  --dns ttl=0 \
  --summary-export "results/summary_$(date +%s).json"
```

### 5단계 — 알림 흐름 검증

```
Prometheus Alert 발생
  → Alertmanager
  → Discord Bot (http://alert-bot:5000/webhook)
  → Gemini API 분석
  → Discord 채널 전송
```

---

## 🌐 네트워크 구조

### AWS VPC (`10.20.0.0/16`)

```
Public Subnet (10.20.1.0/24)
  ├ Bastion Host (t3.micro)        ← 운영자 SSH 진입점
  └ NAT Gateway + EIP              ← Private 인스턴스 아웃바운드

Private Subnet (10.20.2.0/24)
  ├ K3s Node (t3.small)            ← AWS Standby 클러스터
  └ Monitoring Server (t3.small)   ← Prometheus / Grafana / Alertmanager
```

### SSH 접근 경로

```bash
# Bastion 직접
ssh -i ~/본인_키.pem ubuntu@<bastion_public_ip>

# Private 서버 (Bastion 경유)
ssh -i ~/본인_키.pem -A -J ubuntu@<bastion_public_ip> ubuntu@<private_ip>

# GCP K3s
ssh -i ~/본인_gcp_key ubuntu@<gcp_k3s_ip>
```

`terraform apply` 후 출력되는 `ssh_commands` output 값을 그대로 사용하면 됩니다.

### GCP (default 네트워크)

```
Compute Engine (e2-standard-2, Ubuntu 22.04)  ← GCP Primary K3s
Cloud SQL (MySQL 8.0, Public IP)              ← Auth Proxy + IAM 인증만 허용
```

### Cloudflare Tunnel 구성

```
Tunnel 3개:
  ├ GCP Tunnel         → GCP K3s 노드 연결
  ├ AWS Tunnel         → AWS K3s 노드 연결
  └ Monitoring Tunnel  → AWS Monitoring 서버 연결 (Prometheus/Grafana)

Load Balancer:
  ├ Origin Pool: GCP (Primary)
  ├ Origin Pool: AWS (Standby / Fallback)
  └ Health Check: HTTP GET /, 60초 간격, 2회 실패 → unhealthy → Failover
```

---

## 📊 모니터링 스택

Monitoring 서버에서 Docker Compose로 실행:

| 서비스 | 역할 |
|--------|------|
| Prometheus | GCP/AWS 양쪽 K3s `/metrics` scrape, Cloud SQL 메트릭(stackdriver-exporter) |
| Grafana | 대시보드 시각화 |
| Alertmanager | 알림 라우팅 → Discord Bot webhook |
| Discord Bot | Gemini API 호출 → 장애 분석 결과 Discord 채널 전송 |

### 메트릭 수집 경로

```
# Cloud SQL 메트릭
GCP Monitoring API → stackdriver-exporter → Prometheus

# GCP K3s 메트릭 (Cross-Cloud)
Prometheus → Cloudflare Zero Trust Tunnel → GCP K3s /metrics

# AWS K3s 메트릭 (VPC 내부)
Prometheus → Direct Scrape → AWS K3s /metrics
```

---

## 🔁 Failover 시나리오

```
GCP Primary 장애 발생
  → Cloudflare Health Check 실패 감지 (2회)
  → Failover 실행
  → AWS Standby로 트래픽 전환

(동시에)
  Prometheus Target Down 감지
  → Alertmanager Alert 발생
  → Discord Bot 장애 알림
  → Gemini API 분석 결과 전송

GCP 복구
  → Health Check 정상
  → GCP Primary로 자동 Failback

Failover 소요 시간 ≈ Health Check Interval(60s) × 2 + DNS TTL(30s) + α
```

> ⚠️ DB(Cloud SQL)는 GCP 단일 구성이므로 Cloud SQL 장애 시 전체 서비스 영향.
> DB DR은 이번 프로젝트 범위 외입니다.

---

## ✏️ 코드 수정 시 주의사항

- **수정 전 반드시 현재 상태를 확인**하고, 변경 범위를 먼저 설명한 뒤 명시적 요청이 있을 때만 실제 파일을 수정합니다.
- Terraform 변수 기본값(`variables.tf`의 `default`)에 팀 도메인(`bucheongoyangijanggun.com`)이 남아 있을 수 있으므로, 개인 도메인으로 교체 필요 여부를 항상 확인하세요.
- `ansible_inventory.tf`는 Terraform output을 기반으로 `inventory.ini`를 자동 생성합니다. 직접 수정하지 마세요.
- K8s 매니페스트(`application/k8s/`)의 이미지 경로가 팀 Container Registry를 참조하고 있을 수 있으므로 개인 GCR/ECR 경로로 교체하세요.

---

## 📌 현재 레포 상태 메모

- 팀 레포(`Seungmin-Jeong2001/Chilseongpa`) main 브랜치 기준으로 복사
- 개인 계정 값은 아직 `terraform.tfvars`에 미입력 상태일 수 있음
- `terraform.tfvars` 생성 및 개인 계정 값 입력이 가장 먼저 필요한 작업
