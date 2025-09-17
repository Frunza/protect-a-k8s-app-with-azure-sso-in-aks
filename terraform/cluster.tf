# AKS Cluster

resource "azurerm_resource_group" "clusterResourceGroup" {
  name     = local.resourceGroupName
  location = var.location

  tags = {
    Environment = var.tag
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.tag}-aks-nsg"
  location            = azurerm_resource_group.clusterResourceGroup.location
  resource_group_name = azurerm_resource_group.clusterResourceGroup.name

  security_rule {
    name                       = "allow-http"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    destination_port_range     = "80"
    source_port_range          = "*"
  }

  security_rule {
    name                       = "allow-https"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    destination_port_range     = "443"
    source_port_range          = "*"
  }

  tags = {
    Environment = var.tag
  }
}

resource "azurerm_virtual_network" "aksVnet" {
  name                = "aks-vnet"
  location            = azurerm_resource_group.clusterResourceGroup.location
  resource_group_name = azurerm_resource_group.clusterResourceGroup.name
  address_space       = ["10.224.0.0/16"]

  tags = {
    Environment = var.tag
  }
}

resource "azurerm_subnet" "aksSubnet" {
  name                 = "${var.tag}-aks-subnet"
  resource_group_name  = azurerm_resource_group.clusterResourceGroup.name
  virtual_network_name = azurerm_virtual_network.aksVnet.name
  address_prefixes     = ["10.224.0.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
}

resource "azurerm_subnet_network_security_group_association" "aksSubnetNsgAssociation" {
  subnet_id                 = azurerm_subnet.aksSubnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_kubernetes_cluster" "cluster" {
  name                = "${var.tag}-aks"
  location            = azurerm_resource_group.clusterResourceGroup.location
  resource_group_name = azurerm_resource_group.clusterResourceGroup.name
  node_resource_group = "${var.tag}-node-rg"
  dns_prefix          = "${var.tag}-dns-prefix-aks"

  default_node_pool {
    name           = "default"
    node_count     = var.nodeCount
    vm_size        = var.vmSize
    vnet_subnet_id = azurerm_subnet.aksSubnet.id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aksIdentity.id]
  }

  tags = {
    Environment = var.tag
  }
}

resource "azurerm_user_assigned_identity" "aksIdentity" {
  location            = var.location
  name                = "my-subcription-prod-aks-${var.tag}-identity"
  resource_group_name = azurerm_resource_group.clusterResourceGroup.name

  tags = {
    Environment = var.tag
  }
}

# ---------------- Role Assignments ----------------
resource "azurerm_role_assignment" "aksNetworkContributor" {
  scope                = azurerm_virtual_network.aksVnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aksIdentity.principal_id
}

resource "azurerm_role_assignment" "aksNsgContributor" {
  scope                = azurerm_network_security_group.nsg.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aksIdentity.principal_id
}

# ---------------- Kubernetes Config ----------------
resource "local_file" "kubeconfig" {
  content  = azurerm_kubernetes_cluster.cluster.kube_config_raw
  filename = "/app/.kube/config"
}

resource "null_resource" "runTerraformK8s" {
  count = var.runTerraformK8s ? 1 : 0
  depends_on = [ local_file.kubeconfig ]

  triggers = {
    always_run = "${timestamp()}" # This will force the resource to run every time
  }

  provisioner "local-exec" {
    command = <<EOT
cd /app/terraform-k8s
terraform init
terraform apply -auto-approve
EOT
  }
  
}
