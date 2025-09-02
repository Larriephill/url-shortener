variable "stage" {
  description = "Deployment stage (dev/prod)"
  type        = string
  default     = "dev"
}

variable "ttl_days" {
  description = "How many days until a short link expires. 0 disables TTL writes."
  type        = number
  default     = 30
}
variable "domain_zone_name" {
  type    = string
  default = "regalhorizon.click"
}

variable "api_subdomain" {
  type    = string
  default = "api"
} # => api.regalhorizon.click