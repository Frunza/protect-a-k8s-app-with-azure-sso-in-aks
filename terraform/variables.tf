variable "location" {
  default = "Germany West Central"
}

variable "tag" {
  default = "my-test" # tag must be shorter because it is or might be used in various places with maximum length
}

variable "nodeCount" {
  default = 2
}

variable "vmSize" {
  default = "Standard_D2_v2"
}

locals {
  resourceGroupName = "${var.tag}-rg"
}

variable "runTerraformK8s" {
  default = true
}
