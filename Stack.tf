terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.5.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "3.48.0"
    }
  }
  backend "http" {}
}

data "terraform_remote_state" "eks" {
  backend = "http"
  config = {
    address  = "https://git.example.com/api/v4/projects/100/terraform/state/eks"
    username = "gitlab-ci-token"
    password = var.REMOTE_STATE_PASSWORD
  }
}

data "terraform_remote_state" "manager" {
  backend = "http"
  config = {
    address  = "https://git.example.com/api/v4/projects/101/terraform/state/manager"
    username = "gitlab-ci-token"
    password = var.REMOTE_STATE_PASSWORD
  }
}

data "aws_eks_cluster_auth" "eks_token" {
  name = data.terraform_remote_state.eks.outputs.eks-cluster-name
}

provider "aws" {}
provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.eks-ca)
  token                  = data.aws_eks_cluster_auth.eks_token.token
}

resource "kubernetes_ingress" "app" {
  metadata {
    name      = "app-ingress"
    namespace = var.NAMESPACE
    annotations = {
      "nginx.ingress.kubernetes.io/force-ssl-redirect"     = "true"
      "nginx.ingress.kubernetes.io/server-snippet"         = local.app_server_snipet
      "nginx.ingress.kubernetes.io/limit-whitelist"        = "1.1.1.1"
      "nginx.ingress.kubernetes.io/limit-connections"      = "10"
      "nginx.ingress.kubernetes.io/limit-rps"              = "5"
      "nginx.ingress.kubernetes.io/limit-burst-multiplier" = "5"
    }
  }
  spec {
    ingress_class_name = "nginx"
    rule {
      host = "app.example.com"
      http {
        path {
          path = "/"
          backend {
            service_name = kubernetes_service.app.metadata.0.name
            service_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "app" {
  metadata {
    name      = "app"
    namespace = var.NAMESPACE
  }
  spec {
    selector = {
      app   = kubernetes_deployment.app.spec.0.template.0.metadata[0].labels.app
      track = "stable"
    }
    session_affinity = "ClientIP"
    port {
      name        = "http"
      protocol    = "TCP"
      port        = 80
      target_port = "http"
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_config_map" "app" {
  metadata {
    name      = "app-nginx-config"
    namespace = var.NAMESPACE
  }
  data = {
    "default.conf" = "${templatefile("${path.module}/config/default.conf.tpl", { manager-private-ip = "${data.terraform_remote_state.manager.outputs.HRM_private_ip}" })}"
  }
}

resource "kubernetes_secret" "app" {
  metadata {
    name      = "gitlab-pull-secret"
    namespace = var.NAMESPACE
  }
  data = {
    ".dockerconfigjson" = var.GITLAB_PULL_SECRET
  }
  type = "kubernetes.io/dockerconfigjson"
}

resource "kubernetes_deployment" "app" {
  metadata {
    name = "app"
    annotations = {
      "app.gitlab.com/app" = var.CI_PROJECT_PATH_SLUG
      "app.gitlab.com/env" = var.CI_ENVIRONMENT_SLUG
    }
    namespace = var.NAMESPACE
    labels = {
      app   = "app"
      track = "stable"
    }
  }
  spec {
    replicas               = 1
    revision_history_limit = 10
    selector {
      match_labels = {
        app   = "app"
        track = "stable"
      }
    }
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "25%"
        max_unavailable = "25%"
      }
    }
    template {
      metadata {
        annotations = {
          "app.gitlab.com/app" = var.CI_PROJECT_PATH_SLUG
          "app.gitlab.com/env" = var.CI_ENVIRONMENT_SLUG
        }
        name = "app"
        labels = {
          app   = "app"
          track = "stable"
        }
      }
      spec {
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "topology.kubernetes.io/zone"
                  operator = "In"
                  values   = ["eu-west-1b"]
                }
              }
            }
          }
        }
        volume {
          name = "defaulf-conf"
          config_map {
            name = kubernetes_config_map.app.metadata.0.name
          }
        }
        image_pull_secrets {
          name = kubernetes_secret.app.metadata.0.name
        }
        container {
          name              = "react-app"
          image             = format("%s/nginx:%s", var.REPOSITORY_URL, var.DOCKER_TAG)
          image_pull_policy = "IfNotPresent"
          port {
            name           = "http"
            container_port = 80
          }
          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
          }
          volume_mount {
            name       = "defaulf-conf"
            mount_path = "/etc/nginx/conf.d"
          }
          readiness_probe {
            http_get {
              path = "/ready"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 5
            failure_threshold     = 15
            success_threshold     = 3
          }
          liveness_probe {
            http_get {
              path = "/alive"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 5
            failure_threshold     = 5
          }
        }
      }
    }
  }
}
