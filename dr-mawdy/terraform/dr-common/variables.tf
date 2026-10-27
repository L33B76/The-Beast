variable "subscription_id" { type = string }

variable "common_resource_group" { type = string }

variable "tm_profile_name" {
  type    = string
  default = "tm-pro-common-eun"
}

variable "tm_dns_relative_name" { type = string } # nombre DNS del perfil de Traffic Manager

variable "appgw_prod_public_ip_id" { type = string }
variable "appgw_dr_public_ip_id" { type = string }

variable "sqlmi_prod_id" { type = string }
variable "sqlmi_dr_id" { type = string }
variable "sqlmi_dr_location" { type = string }
variable "sqlmi_fog_name" { type = string }
