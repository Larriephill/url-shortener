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

variable "enable_lambda_alias" {
  description = "Create and use a Lambda alias 'live' for routing"
  type        = bool
  default     = true
}

variable "lambda_canary_weight" {
  description = "Optional % weight to another version (0..100). Leave 0 for no canary."
  type        = number
  default     = 0
}
