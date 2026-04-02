terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# -------------------------------------------------------------------
# 0. Tunnel 생성 및 비밀번호 관리
# -------------------------------------------------------------------
resource "random_password" "tunnel_secrets" {
  for_each = toset(["gcp", "aws", "monitoring"])
  length   = 32
  special  = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "tunnels" {
  for_each   = toset(["gcp", "aws", "monitoring"])
  account_id = var.cf_account_id
  name       = "${var.project_name}-${each.key}-tunnel"
  secret     = base64encode(random_password.tunnel_secrets[each.key].result)
}

# -------------------------------------------------------------------
# 1. Access 설정 (인증 및 토큰)
# -------------------------------------------------------------------
resource "cloudflare_zero_trust_access_service_token" "monitoring_token" {
  account_id = var.cf_account_id
  name       = "Chilseongpa-Monitoring-Token"
}

resource "cloudflare_zero_trust_access_application" "gcp_metrics" {
  account_id = var.cf_account_id
  name       = "GCP K3s Metrics"
  domain     = "gcp-metrics.hjh-dev.site"
  type       = "self_hosted"
}

resource "cloudflare_zero_trust_access_policy" "gcp_metrics_policy" {
  application_id = cloudflare_zero_trust_access_application.gcp_metrics.id
  account_id     = var.cf_account_id
  name           = "Allow Prometheus Scraper"
  decision       = "non_identity"
  precedence     = 1

  include {
    service_token = [cloudflare_zero_trust_access_service_token.monitoring_token.id]
  }
}

# AWS 메트릭 엔드포인트는 CF Access 없이 터널로만 노출
# (Prometheus가 custom header를 scrape_config에서 지원하지 않음)
# 터널 hostname 자체가 외부에 노출되지 않으므로 현재 보안 수준에서 허용

# -------------------------------------------------------------------
# 2. Tunnel Config 설정 (멀티 서비스 매핑)
# -------------------------------------------------------------------
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "configs" {
  for_each   = cloudflare_zero_trust_tunnel_cloudflared.tunnels
  account_id = var.cf_account_id
  tunnel_id  = each.value.id

  config {
    # [A] Monitoring 터널 전용 규칙 (Grafana & Prometheus)
    dynamic "ingress_rule" {
      for_each = each.key == "monitoring" ? [1] : []
      content {
        hostname = var.grafana_domain # monitoring.bucheong...
        service  = "http://localhost:3000" # Grafana 접속
      }
    }

    dynamic "ingress_rule" {
      for_each = each.key == "monitoring" ? [1] : []
      content {
        hostname = var.prometheus_domain
        service  = "http://localhost:9090" # Prometheus 접속
      }
    }

    # [B] GCP 터널 전용 규칙 (Metrics)
    dynamic "ingress_rule" {
      for_each = each.key == "gcp" ? [1] : []
      content {
        hostname = "gcp-metrics.hjh-dev.site"
        service  = "http://localhost:9100"
      }
    }

    # [C] AWS 터널 전용 규칙 (Node Exporter & App Metrics)
    dynamic "ingress_rule" {
      for_each = each.key == "aws" ? [1] : []
      content {
        hostname = "aws-node-metrics.hjh-dev.site"
        service  = "http://localhost:9100"
      }
    }

    dynamic "ingress_rule" {
      for_each = each.key == "aws" ? [1] : []
      content {
        hostname = "aws-app-metrics.hjh-dev.site"
        service  = "http://localhost:8000"
      }
    }

    # [D] 기본 공통 규칙 (App 배포용)
    ingress_rule {
      hostname = var.app_domain
      service  = "http://localhost:80"
    }

    # [E] Catch-all 규칙 (필수)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# -------------------------------------------------------------------
# 3. DNS 레코드 설정 (도메인 - 터널 연결)
# -------------------------------------------------------------------
# Grafana 도메인
resource "cloudflare_record" "monitoring_record" {
  zone_id = var.cf_zone_id
  name    = "grafana"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.tunnels["monitoring"].id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# Prometheus 도메인
resource "cloudflare_record" "prometheus_record" {
  zone_id = var.cf_zone_id
  name    = "prometheus"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.tunnels["monitoring"].id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# GCP Metrics 도메인
resource "cloudflare_record" "metrics_record" {
  zone_id = var.cf_zone_id
  name    = "gcp-metrics"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.tunnels["gcp"].id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# AWS Node Exporter 도메인
resource "cloudflare_record" "aws_node_metrics_record" {
  zone_id = var.cf_zone_id
  name    = "aws-node-metrics"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.tunnels["aws"].id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# AWS App Metrics 도메인
resource "cloudflare_record" "aws_app_metrics_record" {
  zone_id = var.cf_zone_id
  name    = "aws-app-metrics"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.tunnels["aws"].id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# -------------------------------------------------------------------
# 4. Load Balancer 설정 (유료 기능 — 현재 비활성화)
# -------------------------------------------------------------------
# resource "cloudflare_load_balancer_monitor" "monitor" {
#   account_id     = var.cf_account_id
#   type           = "http"
#   path           = "/"
#   port           = 80
#   interval       = 60
#   retries        = 2
#   expected_codes = "200"
#
#   header {
#     header = "Host"
#     values = [var.app_domain]
#   }
# }
#
# resource "cloudflare_load_balancer_pool" "pools" {
#   for_each   = toset(["gcp", "aws"])
#   account_id = var.cf_account_id
#   name       = "${var.project_name}-${each.key}-pool"
#   monitor    = cloudflare_load_balancer_monitor.monitor.id
#
#   origins {
#     name    = "${each.key}-origin"
#     address = "${cloudflare_zero_trust_tunnel_cloudflared.tunnels[each.key].id}.cfargotunnel.com"
#   }
# }
#
# resource "cloudflare_load_balancer" "lb" {
#   zone_id = var.cf_zone_id
#   name    = var.app_domain
#
#   default_pool_ids = [
#     cloudflare_load_balancer_pool.pools["gcp"].id,
#     cloudflare_load_balancer_pool.pools["aws"].id
#   ]
#   fallback_pool_id = cloudflare_load_balancer_pool.pools["aws"].id
#   proxied = true
# }

# -------------------------------------------------------------------
# 4-1. app 도메인 → GCP 터널 직접 연결 (LB 대체, 수동 페일오버)
# -------------------------------------------------------------------
resource "cloudflare_record" "app_record" {
  zone_id = var.cf_zone_id
  name    = "app"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.tunnels["gcp"].id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}