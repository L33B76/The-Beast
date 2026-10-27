# ESQUELETO de IaC DR Common. NO aplicar sin antes IMPORTAR los recursos existentes
# (terraform import) y revisar que el plan sale sin cambios.
# Principio: Terraform describe la infraestructura DR "siempre lista"; el failover lo hace el pipeline.

resource "azurerm_traffic_manager_profile" "common" {
  name                   = var.tm_profile_name
  resource_group_name    = var.common_resource_group
  traffic_routing_method = "Priority"

  dns_config {
    relative_name = var.tm_dns_relative_name
    ttl           = 30
  }

  monitor_config {
    protocol                     = "HTTPS"
    port                         = 443
    path                         = "/"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }
}

resource "azurerm_traffic_manager_azure_endpoint" "prod" {
  name               = "tm-pro-common-ep-appgw-eun"
  profile_id         = azurerm_traffic_manager_profile.common.id
  target_resource_id = var.appgw_prod_public_ip_id
  priority           = 1
  enabled            = true

  # IMPORTANTE: el estado enabled lo cambia el pipeline durante el failover.
  lifecycle { ignore_changes = [enabled] }
}

resource "azurerm_traffic_manager_azure_endpoint" "dr" {
  name               = "tm-pro-common-ep-appgw-euw-dr"
  profile_id         = azurerm_traffic_manager_profile.common.id
  target_resource_id = var.appgw_dr_public_ip_id
  priority           = 2
  enabled            = false

  lifecycle { ignore_changes = [enabled] }
}

resource "azurerm_mssql_managed_instance_failover_group" "phoenix" {
  name                        = var.sqlmi_fog_name
  location                    = var.sqlmi_dr_location
  managed_instance_id         = var.sqlmi_prod_id
  partner_managed_instance_id = var.sqlmi_dr_id

  read_write_endpoint_failover_policy {
    mode = "Manual" # el failover lo decide el runbook, no Azure
  }
}

# TODO: App Gateway DR, Key Vault DR y secretos (Redis, BBDD, wallet), reglas NSG y config de pods.
#       Los fallos del ensayo (LDAP mal configurado, App Gateway, secreto Redis) deben vivir AQUÍ,
#       versionados, y no como pasos manuales el día del cutover.
