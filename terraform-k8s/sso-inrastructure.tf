resource "kubernetes_namespace" "ssoInfrastructureNamespace" {
  metadata {
    name = "sso-infrastructure"
  }
}

# Redis

resource "kubernetes_manifest" "redisDeployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "redis"
      namespace = kubernetes_namespace.ssoInfrastructureNamespace.metadata[0].name
    }
    spec = {
      selector = {
        matchLabels = {
          app = "redis"
        }
      }
      replicas = 1
      template = {
        metadata = {
          labels = {
            app = "redis"
          }
        }
        spec = {
          containers = [
            {
              name  = "redis"
              image = "redis:latest"
              ports = [
                {
                  containerPort = 6379
                }
              ]
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "redisService" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "redis-service"
      namespace = kubernetes_namespace.ssoInfrastructureNamespace.metadata[0].name
    }
    spec = {
      selector = {
        app = "redis"
      }
      ports = [
        {
          protocol    = "TCP"
          port        = 6379
          targetPort  = 6379
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.redisDeployment]
}

# OAuth2 Proxy

resource "kubernetes_manifest" "oauth2ProxyDeployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      labels = {
        k8s-app = "oauth2-proxy"
      }
      name      = "oauth2-proxy"
      namespace = kubernetes_namespace.ssoInfrastructureNamespace.metadata[0].name
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          k8s-app = "oauth2-proxy"
        }
      }
      template = {
        metadata = {
          labels = {
            k8s-app = "oauth2-proxy"
          }
        }
        spec = {
          containers = [
            {
              args = [
                # https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview/
                # https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/ms_entra_id/
                "--provider=entra-id",
                "--scope=openid email profile",
                "--client-id=_OAUTH2_CLIENT_ID_",
                "--client-secret=_OAUTH2_CLIENT_SECRET_",
                "--oidc-issuer-url=https://login.microsoftonline.com/_OAUTH2_TENANT_ID_/v2.0",
                "--email-domain=*",
                "--redis-connection-url=redis://redis-service:6379",
                "--http-address=0.0.0.0:4180",
                "--set-authorization-header=true",
                "--pass-access-token=true",
                "--pass-authorization-header=true",
                "--cookie-refresh=1h",
                "--logging-max-age=1",
                "--request-logging=true",
                "--auth-logging=true",
                "--standard-logging=true",
                "--show-debug-on-error=true",
              ]
              env = [
                {
                  name  = "OAUTH2_PROXY_COOKIE_SECRET"
                  # https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview/#generating-a-cookie-secret
                  value = "_OAUTH2_PROXY_COOKIE_SECRET_"
                },
                {
                  name  = "OAUTH2_PROXY_SESSION_STORE_TYPE"
                  value = "redis"
                }
              ]
              # https://quay.io/repository/oauth2-proxy/oauth2-proxy?tab=tags
              image           = "quay.io/oauth2-proxy/oauth2-proxy:latest"
              imagePullPolicy = "Always"
              name            = "oauth2-proxy"
              ports = [
                {
                  containerPort = 4180
                  protocol      = "TCP"
                }
              ]
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "oauth2ProxyService" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      labels = {
        k8s-app = "oauth2-proxy"
      }
      name      = "oauth2-proxy"
      namespace = kubernetes_namespace.ssoInfrastructureNamespace.metadata[0].name
    }
    spec = {
      ports = [
        {
          name       = "http"
          port       = 4180
          protocol   = "TCP"
          targetPort = 4180
        }
      ]
      selector = {
        k8s-app = "oauth2-proxy"
      }
    }
  }

  depends_on = [kubernetes_manifest.oauth2ProxyDeployment]
}
