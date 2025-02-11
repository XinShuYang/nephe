terraform {
  required_providers {
    azurerm = {
      version = "~>3.11.0"
    }
    random = {
      version = "~> 2.1"
    }
  }
}

provider "azurerm" {
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  subscription_id = var.azure_client_subscription_id
  tenant_id       = var.azure_client_tenant_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

resource "azurerm_resource_group" "vm" {
  name     = local.resource_group_name
  location = var.location
}

locals {
  resource_group_name = "nephe-vnet-${var.owner}-${random_string.suffix.result}"
  azure_vm_os_types   = var.with_agent ? var.azure_vm_os_types_agented : var.azure_vm_os_types
}

locals {
  vnet_name_random = "nephe-vnet-${random_id.suffix.hex}"
}

resource "random_id" "suffix" {
  byte_length = 8
}

resource "random_string" "suffix" {
  length  = 4
  special = false
}

data "template_file" user_data {
  count    = length(local.azure_vm_os_types)
  template = file(local.azure_vm_os_types[count.index].init)
  vars     = {
    WITH_AGENT               = var.with_agent
    K8S_CONF                 = var.with_agent ? file(var.antrea_agent_k8s_config) : ""
    ANTREA_CONF              = var.with_agent ? file(var.antrea_agent_antrea_config) : ""
    INSTALL_VM_AGENT_WRAPPER = var.with_agent ? file(var.install_vm_agent_wrapper) : ""
    NAMESPACE                = var.namespace
    ANTREA_VERSION           = var.antrea_version
  }
}

module "vm_cluster" {
  source                  = "Azure/compute/azurerm"
  resource_group_name     = azurerm_resource_group.vm.name
  count                   = length(local.azure_vm_os_types)
  nb_instances            = 1
  vm_os_publisher         = local.azure_vm_os_types[count.index].publisher
  vm_os_offer             = local.azure_vm_os_types[count.index].offer
  vm_os_sku               = local.azure_vm_os_types[count.index].sku
  vm_hostname             = "${local.azure_vm_os_types[count.index].name}-${var.owner}"
  vm_size                 = var.azure_vm_type
  vnet_subnet_id          = module.network.vnet_subnets[0]
  enable_ssh_key          = true
  ssh_key                 = var.ssh_public_key
  remote_port             = var.with_agent ? "*" : "80"
  source_address_prefixes = ["0.0.0.0/0"]

  custom_data = data.template_file.user_data[count.index].rendered

  nb_public_ip      = 1
  allocation_method = "Static"

  tags = {
    Terraform   = "true"
    Environment = "nephe"
    Name        = local.azure_vm_os_types[count.index].name
  }
}

module "network" {
  source              = "Azure/vnet/azurerm"
  resource_group_name = azurerm_resource_group.vm.name
  address_space       = [var.network_address_space]
  subnet_prefixes     = [var.subnet_prefix]
  subnet_names        = ["subnet1"]
  vnet_name           = local.vnet_name_random
  vnet_location       = var.location
}
