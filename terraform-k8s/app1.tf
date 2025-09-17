variable "app1Host" {
  description = "Public host for app1"
  type        = string
  default     = "app1.cluster1.mycompany.com"
}

resource "kubernetes_namespace" "app1Namespace" {
  metadata {
    name = "app1"
  }
}

resource "kubernetes_manifest" "app1Deployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "app1"
      namespace = kubernetes_namespace.app1Namespace.metadata[0].name
    }
    spec = {
      selector = {
        matchLabels = {
          app = "app1"
        }
      }
      replicas = 2
      template = {
        metadata = {
          labels = {
            app = "app1"
          }
        }
        spec = {
          containers = [{
            name  = "app1"
            image = "frunzahincu/write_headers"
            ports = [{
              containerPort = 8000
            }]
          }]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "app1Service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "app1"
      namespace = kubernetes_namespace.app1Namespace.metadata[0].name
    }
    spec = {
      ports = [{
        port       = 80
        targetPort = 8000
      }]
      selector = {
        app = "app1"
      }
    }
  }
}

resource "kubernetes_manifest" "app1Ingress" {
  manifest = {
    "apiVersion" = "networking.k8s.io/v1"
    "kind"       = "Ingress"
    "metadata" = {
      "name"      = "app1-ingress"
      "namespace" = kubernetes_namespace.app1Namespace.metadata[0].name
      "annotations" = {
        "kubernetes.io/ingress.class" = "nginx"
        "nginx.ingress.kubernetes.io/auth-response-headers" = "Authorization"
        # Docs: https://kubernetes.github.io/ingress-nginx/examples/auth/oauth-external-auth/
        "nginx.ingress.kubernetes.io/auth-url" = "https://${var.app1Host}/oauth2/auth"
        "nginx.ingress.kubernetes.io/auth-signin" = "https://${var.app1Host}/oauth2/start?rd=$escaped_request_uri"
      }
    }
    "spec" = {
      "rules" = [{
        "host" = "${var.app1Host}"
        "http" = {
          "paths" = [{
            "path"     = "/"
            "pathType" = "Prefix"
            "backend" = {
              "service" = {
                "name" = "app1"
                "port" = {
                  "number" = 80
                }
              }
            }
          }]
        }
      }]
      "tls" = [{
        "hosts"      = ["${var.app1Host}"]
        "secretName" = "app1-ingress-tls-crt"
      }]
    }
  }
}

resource "kubernetes_manifest" "app1TlsSecret" {
  manifest = {
    "apiVersion" = "v1"
    "kind"       = "Secret"
    "metadata" = {
      "name"      = "app1-ingress-tls-crt"
      "namespace" = kubernetes_namespace.app1Namespace.metadata[0].name
    }
    "type" = "kubernetes.io/tls"
    "data" = {
      # base64 fullchain1.pem | tr -d '\n' on MacOS. On Linux, use base64 -w 0 fullchain1.pem
      "tls.crt" = "DUMMYCRT"
      # base64 privkey1.pem | tr -d '\n' on MacOS. On Linux, use base64 -w 0 privkey1.pem
      "tls.key" = "DUMMYKEY"
    }
  }
}

resource "kubernetes_manifest" "app1Oauth2ProxyIngress" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "app1-oauth2-proxy-ingress"
      namespace = kubernetes_namespace.ssoInfrastructureNamespace.metadata[0].name
      annotations = {
        "kubernetes.io/ingress.class" = "nginx"
      }
    }
    spec = {
      rules = [
        {
          host = "${var.app1Host}"
          http = {
            paths = [
              {
                path     = "/oauth2"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "oauth2-proxy"
                    port = {
                      number = 4180
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }
}

output "app1Host" {
  value = kubernetes_manifest.app1Ingress.manifest.spec.rules[0].host
}
