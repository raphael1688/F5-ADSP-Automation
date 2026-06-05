#XC variables.tf 

# GCP Configuration
variable "gcp_project_id" {
  type        = string
  description = "GCP project ID"
}

variable "gcp_region" {
  type        = string
  description = "GCP region (e.g., us-west1)"
}

variable "tf_state_bucket" {
  type        = string
  description = "GCS bucket name for Terraform remote state"
}

variable "infra_state_prefix" {
  type        = string
  description = "GCS prefix where infra state is stored"
  default     = "state/uc1/infra"
}

variable "bigip_state_prefix" {
  type        = string
  description = "GCS prefix where bigip-base state is stored"
  default     = "state/uc1/bigip-base"
}

/* 
#Backend selection flags
variable "backend_compute" {
  type        = bool
  description = "Whether to reference compute remote state"
  default     = false
}
*/

variable "backend_bigip" {
  type        = bool
  description = "Whether to reference BIG-IP remote state"
  default     = false
}

variable "backend_nic" {
  type        = bool
  description = "Whether to reference NIC remote state for the origin LoadBalancer IP."
  default     = false
}

variable "nic_state_prefix" {
  type        = string
  description = "GCS prefix where NIC + NAP state is stored. Read when backend_nic is true."
  default     = "state/uc2/nic"
}

# XC
variable "xc_tenant" {
  type        = string
  description = "Your F5 XC tenant name"
}

variable "api_url" {
  type        = string
  description = "Your F5 XC tenant api url"
}

variable "xc_namespace" {
  type        = string
  description = "Volterra app namespace where the object will be created. This cannot be system or shared ns."

  validation {
    condition     = var.xc_namespace != "" && var.xc_namespace != "system" && var.xc_namespace != "shared"
    error_message = "The xc_namespace must be non-empty and cannot be 'system' or 'shared'."
  }
}

variable "app_domain" {
  type        = string
  description = "FQDN for the app. If you have delegated domain `prod.example.com`, then your app_domain can be `<app_name>.prod.example.com`"
}

# XC WAF
variable "xc_waf_blocking" {
  type        = bool
  description = "Set XC WAF to Blocking(true) or Monitoring(false)"
  default     = false
}

# XC AI/ML settings for MUD and APIP. Only set when using shared-namespace AI/ML.
variable "xc_app_type" {
  type        = list(any)
  description = "Set Apptype for shared AI/ML"
  default     = null
}

variable "xc_multi_lb" {
  type        = bool
  description = "ML configured externally using app type feature and label added to the HTTP load balancer."
  default     = false
}

# XC API Protection and Discovery
variable "xc_api_disc" {
  type        = bool
  description = "Enable API Discovery on single LB"
  default     = false
}

variable "xc_api_crawler" {
  type        = bool
  description = "Enable the active API crawler against app_domain (requires xc_api_disc)."
  default     = false
}

variable "xc_api_auth_discovery" {
  type        = bool
  description = "Enable default API authentication discovery (requires xc_api_disc)."
  default     = false
}

variable "xc_api_pro" {
  type        = bool
  description = "Enable API Protection (Definition and Rules)"
  default     = false
}

variable "xc_api_spec" {
  type        = list(any)
  description = "Pre-uploaded XC object store path(s) to a swagger spec. Leave null when xc_oas_content is used."
  default     = null
}

variable "xc_api_val" {
  type        = bool
  description = "Enable API Validation"
  default     = false
}

variable "xc_api_val_all" {
  type        = bool
  description = "Enable API Validation on all endpoints"
  default     = false
}

variable "xc_api_val_properties" {
  type    = list(string)
  default = ["PROPERTY_QUERY_PARAMETERS", "PROPERTY_PATH_PARAMETERS", "PROPERTY_CONTENT_TYPE", "PROPERTY_COOKIE_PARAMETERS", "PROPERTY_HTTP_HEADERS", "PROPERTY_HTTP_BODY"]
}

variable "xc_resp_val_properties" {
  type    = list(string)
  default = ["PROPERTY_HTTP_HEADERS", "PROPERTY_CONTENT_TYPE", "PROPERTY_HTTP_BODY", "PROPERTY_RESPONSE_CODE"]
}

variable "xc_api_val_active" {
  type        = bool
  description = "Enable API Validation on active endpoints"
  default     = false
}

variable "xc_resp_val_active" {
  type        = bool
  description = "Enable response API Validation on active endpoints"
  default     = false
}

variable "enforcement_block" {
  type        = bool
  description = "Enable enforcement block"
  default     = false
}

variable "enforcement_report" {
  type        = bool
  description = "Enable enforcement report"
  default     = false
}

variable "fall_through_mode_allow" {
  type        = bool
  description = "Enable fall through mode allow"
  default     = false
}

variable "fall_through_mode_report" {
  type        = bool
  description = "When fall_through_mode_allow is false, emit a single action_report rule for unknown paths instead of action_block."
  default     = false
}

variable "xc_api_val_custom" {
  type        = bool
  description = "Enable API Validation custom rules"
  default     = false
}

# JWT Validation
variable "xc_jwt_val" {
  type        = bool
  description = "Enable JWT Validation"
  default     = false
}

variable "jwt_val_block" {
  type        = bool
  description = "Enable JWT Validation block"
  default     = false
}

variable "jwt_val_report" {
  type        = bool
  description = "Enable JWT Validation report"
  default     = false
}

variable "jwks" {
  type        = string
  description = "JWK for validation"
  default     = "app_domain"
}

variable "iss_claim" {
  type        = bool
  description = "JWT Validation issuer claim"
  default     = false
}

variable "aud_claim" {
  type        = list(string)
  description = "JWT Validation audience claim"
  default     = [""]
}

variable "exp_claim" {
  type        = bool
  description = "JWT Validation expiration claim"
  default     = false
}

# XC Bot Defense
variable "xc_bot_def" {
  type        = bool
  description = "Enable XC Bot Defense"
  default     = false
}

variable "xc_bot_def_advanced" {
  type        = bool
  description = "Enable the modern bot_defense_advanced block. Mutually exclusive with xc_bot_def."
  default     = false
}

variable "xc_bot_def_advanced_web_policy_name" {
  type        = string
  description = "Name of a pre-existing bot defense (web) policy in XC. Required when xc_bot_def_advanced is true."
  default     = ""
}

variable "xc_bot_def_advanced_web_policy_namespace" {
  type        = string
  description = "Namespace of the referenced bot defense (web) policy."
  default     = "shared"
}

# XC DDoS Protection
variable "xc_ddos_pro" {
  type        = bool
  description = "Enable XC DDoS Protection"
  default     = false
}

variable "xc_l7_ddos_rps_threshold" {
  type        = number
  description = "Per-source RPS threshold above which the L7 DDoS mitigation engages."
  default     = 100
}

variable "xc_slow_ddos" {
  type        = bool
  description = "Enable slow-DDoS mitigation (request header / full request timeouts)."
  default     = false
}

variable "xc_slow_ddos_request_headers_timeout" {
  type        = number
  description = "Maximum seconds allowed to receive complete request headers."
  default     = 10
}

variable "xc_slow_ddos_request_timeout" {
  type        = number
  description = "Maximum seconds allowed for the full request to complete."
  default     = 60
}

# XC IP Reputation
variable "xc_ip_reputation" {
  type        = bool
  description = "Enable IP reputation filtering against the listed threat categories."
  default     = false
}

variable "xc_ip_threat_categories" {
  type        = list(string)
  description = "Threat categories to match (e.g., SPAM_SOURCES, WINDOWS_EXPLOITS, TOR_PROXY)."
  default = [
    "SPAM_SOURCES",
    "WINDOWS_EXPLOITS",
    "WEB_ATTACKS",
    "BOTNETS",
    "SCANNERS",
    "DOS_ATTACKS",
    "PHISHING",
    "PROXY",
    "TOR_PROXY"
  ]
}

# XC Threat Mesh
variable "xc_threat_mesh" {
  type        = bool
  description = "Opt the LB into the cross-tenant XC threat mesh signal."
  default     = false
}

# XC API Rate Limit (modern api_rate_limit block, replaces api_rate_limit_legacy)
variable "xc_api_rate_limit" {
  type        = bool
  description = "Enable the modern API rate limit with a baseline global rule."
  default     = false
}

variable "xc_api_rate_limit_threshold" {
  type        = number
  description = "Request count threshold for the baseline rate limit rule."
  default     = 100
}

variable "xc_api_rate_limit_unit" {
  type        = string
  description = "Rate limit window unit (SECOND, MINUTE, HOUR)."
  default     = "MINUTE"
  validation {
    condition     = contains(["SECOND", "MINUTE", "HOUR"], var.xc_api_rate_limit_unit)
    error_message = "xc_api_rate_limit_unit must be one of: SECOND, MINUTE, HOUR."
  }
}

variable "xc_api_rate_limit_base_path" {
  type        = string
  description = "Base path the baseline rate limit rule applies to."
  default     = "/"
}

# XC Malicious User Detection
variable "xc_mud" {
  type        = bool
  description = "Enable Malicious User Detection on single LB"
  default     = false
}

variable "xc_data_guard" {
  type        = bool
  description = "F5 XC Data Guard"
  default     = false
}

variable "xc_client_side_defense" {
  type        = bool
  description = "Enable client-side defense (JS insertion for monitoring client-side script tampering)."
  default     = false
}

# XC WAF Exclusion (modern singular waf_exclusion block referencing a policy)
variable "xc_waf_exclusion" {
  type        = bool
  description = "Attach a pre-existing volterra_waf_exclusion_policy to the LB."
  default     = false
}

variable "xc_waf_exclusion_policy_name" {
  type        = string
  description = "Name of the pre-existing WAF exclusion policy. Required when xc_waf_exclusion is true."
  default     = ""
}

variable "xc_waf_exclusion_policy_namespace" {
  type        = string
  description = "Namespace of the referenced WAF exclusion policy."
  default     = "shared"
}

variable "xc_sensitive_data_policy" {
  type        = bool
  description = "Provision a baseline volterra_sensitive_data_policy and attach it to the LB."
  default     = false
}

variable "xc_sensitive_data_compliances" {
  type        = list(string)
  description = "Compliance profiles applied to the sensitive data policy (e.g., COMPLIANCE_PCI, COMPLIANCE_HIPAA)."
  default     = []
}

# Origin backend configuration
variable "origin_server" {
  type        = string
  description = "Origin server IP or DNS name (can be auto-discovered from remote state if backend_bigip/backend_nic enabled)"
  default     = ""
}

variable "origin_port" {
  type        = number
  description = "Origin server port"
  default     = 80
}

# TLS termination at the XC HTTP LoadBalancer
variable "xc_byo_cert" {
  type        = bool
  description = "Use a pre-existing volterra_certificate (BYO TLS cert) on the LB instead of XC-managed auto-cert. Requires xc_byo_cert_name."
  default     = false
}

variable "xc_byo_cert_name" {
  type        = string
  description = "Name of the pre-existing volterra_certificate to attach. Required when xc_byo_cert is true."
  default     = ""
}

variable "xc_byo_cert_namespace" {
  type        = string
  description = "Namespace of the referenced volterra_certificate."
  default     = "shared"
}
