

variable "ttl_days" {
  description = "Days till a short link expires (0 disables TTL writes)"
  type        = number
  default     = 30
}

variable "domain_zone_name" {
  description = "Hosted zone name in Route 53"
  type        = string
  default     = "regalhorizon.click"
}

variable "api_subdomain" {
  description = "Subdomain for API custom domain (e.g., api or api-dev)"
  type        = string
  default     = "api"
}

variable "enable_lambda_alias" {
  description = "Create/use Lambda alias 'live'"
  type        = bool
  default     = true
}

variable "lambda_canary_weight" {
  description = "Optional % weight to another version (0..100)"
  type        = number
  default     = 0
}


variable "origin_shared_secret" {
  description = "Optional shared secret header from a reverse proxy"
  type        = string
  default     = ""
}


variable "use_apigw_custom_domain" {
  description = "Kept for compatibility; custom domain is always created"
  type        = bool
  default     = true
}

variable "attach_waf_to_cloudfront" {
  description = "Temporarily detach/attach WAF to allow safe changes"
  type        = bool
  default     = true
}


