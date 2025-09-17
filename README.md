# Protect a k8s app with Azure SSO in AKS

## Motivation

I have an `AKS` cluster with a test application fully automated with `Terraform`. If you want a tutorial for this part, you can find it [here](https://github.com/Frunza/create-aks-cluster-with-a-testing-application-via-terraform): . I want to protect my test application with *SSO* `Azure` login. The implementation should clearly show how this scales, so that it is easy for me to add a second testing application and protect it with *SSO*.

## Prerequisites

A Linux or MacOS machine for local development. If you are running Windows, you first need to set up the *Windows Subsystem for Linux (WSL)* environment.

You need `docker cli` and `docker-compose` on your machine for testing purposes, and/or on the machines that run your pipeline.
You can check both of these by running the following commands:
```sh
docker --version
docker-compose --version
```

For `Azure` access you need the following:
- ARM_CLIENT_ID
- ARM_CLIENT_SECRET
- ARM_TENANT_ID
- ARM_SUBSCRIPTION_ID

For *OAUTH2* you need the following environment variables:
- OAUTH2_CLIENT_ID
- OAUTH2_CLIENT_SECRET
- OAUTH2_PROXY_COOKIE_SECRET


## Implementation

Since we want the *SSO* flow to work with `Azure` login, we must first set this up in `Azure`. The *SSO* flow can be implemented with help of `oauth2-proxy`. We will split this up in an general cluster infrastructure part, and a part specifically for our testing application, so that if we want to add a second application, we can just do it similar as the fist one.

### Azure setup

For the *SSO* flow, an *App registration* must be configured in `Azure`. Create a new *App registration*. 
In the *Authentication* section add a *Web* *Redirect URIs* with a redirect to the *oauth2* callback of your cluster; For example: https://cluster1.mycompany.com/oauth2/callback In the *Certificates & secrets* section create a client secret. You will need the value of the secret in the next step.

### SSO infrastructure

Let's fist create a namespace for this:
```sh
resource "kubernetes_namespace" "ssoInfrastructureNamespace" {
  metadata {
    name = "sso-infrastructure"
  }
}
```

For the `oauth2-proxy` to work properly, we can use `redis`, so that we can hold bigger cookies. Let's first add a `redis` deployment and a service for it:
```sh
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
```

Now we can create the `oauth2-proxy` deployment:
```sh
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
```
Note a few placeholders in the code. This is the place you use the secret value from the *App registration* you created earlier. You also need to create a secret for the cookies. Documentation for that can be found here: https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview/#generating-a-cookie-secret Feel free to remove any debug configuration.

Now we can create a service for the `oauth2-proxy` deployment:
```sh
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
```

### Testing app SSO

Our testing app is using the `nginx` *ingress* class. We have to update the ingress annotations first:
```sh
      "annotations" = {
        "kubernetes.io/ingress.class" = "nginx"
        "nginx.ingress.kubernetes.io/auth-response-headers" = "Authorization"
        # Docs: https://kubernetes.github.io/ingress-nginx/examples/auth/oauth-external-auth/
        "nginx.ingress.kubernetes.io/auth-url" = "https://${var.app1Host}/oauth2/auth"
        "nginx.ingress.kubernetes.io/auth-signin" = "https://${var.app1Host}/oauth2/start?rd=$escaped_request_uri"
      }
```

The last thing to do is to create an *ingress* for our app's *OAUTH2*:
```sh
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
```
Only note that this component must be deployed in the same namespace as the `oauth2-proxy` deployment.

## Usage

From now on, whenever you access your testing app, you will be required to do an `Azure` login first.
