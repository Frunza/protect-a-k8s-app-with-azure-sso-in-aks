terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.9"
    }
  }
}

provider "kubernetes" {
  config_path = "/app/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "/app/.kube/config"
  }
}
