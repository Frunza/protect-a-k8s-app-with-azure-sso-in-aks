resource "kubernetes_namespace" "ingressNginxNamespace" {
  metadata {
    name = "ingress-nginx"
  }
}

resource "helm_release" "nginxIngress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = kubernetes_namespace.ingressNginxNamespace.metadata[0].name
  version    = "4.12.0"

  values = [
    <<-EOF
    controller:
      service:
        type: LoadBalancer
        externalTrafficPolicy: Local
    EOF
  ]
}

data "kubernetes_service" "ingressService" {
  metadata {
    name      = "nginx-ingress-ingress-nginx-controller" # Default name for the NGINX ingress controller service
    namespace = kubernetes_namespace.ingressNginxNamespace.metadata[0].name
  }

  depends_on = [helm_release.nginxIngress] # Ensure the ingress controller is deployed first
}
