# loadbalancer.tf

resource "volterra_origin_pool" "op" {
  depends_on  = [volterra_namespace.this]
  name        = format("%s-xcop-%s", local.project_prefix, local.build_suffix)
  namespace   = var.xc_namespace
  description = format("Origin pool pointing to origin server %s", local.origin_server)

  dynamic "origin_servers" {
    for_each = local.dns_origin_pool ? [1] : []
    content {
      public_name {
        dns_name = local.origin_server
      }
    }
  }

  dynamic "origin_servers" {
    for_each = local.dns_origin_pool ? [] : [1]
    content {
      public_ip {
        ip = local.origin_server
      }
    }
  }

  no_tls = true
  port   = tostring(local.origin_port)

  endpoint_selection     = "LOCAL_PREFERRED"
  loadbalancer_algorithm = "LB_OVERRIDE"
}

resource "volterra_http_loadbalancer" "lb_https" {
  depends_on = [
    volterra_namespace.this,
    volterra_app_firewall.waap-tf,
    volterra_origin_pool.op
  ]

  name      = format("%s-xclb-%s", local.project_prefix, local.build_suffix)
  namespace = var.xc_namespace

  labels = merge(
    {},
    length(var.xc_app_type) != 0 ? { "ves.io/app_type" = volterra_app_type.app-type[0].name } : {}
  )

  description                     = format("HTTPS loadbalancer object for %s origin server", local.project_prefix)
  domains                         = [var.app_domain]
  advertise_on_public_default_vip = true

  default_route_pools {
    pool {
      name      = volterra_origin_pool.op.name
      namespace = var.xc_namespace
    }
    weight = 1
  }

  # TLS termination: auto-cert (XC-managed) by default, or a referenced
  # volterra_certificate (BYO) when xc_byo_cert is set with a name.
  dynamic "https_auto_cert" {
    for_each = (var.xc_byo_cert && var.xc_byo_cert_name != "") ? [] : [1]
    content {
      add_hsts              = false
      http_redirect         = true
      no_mtls               = true
      enable_path_normalize = true
      tls_config {
        default_security = true
      }
    }
  }

  dynamic "https" {
    for_each = (var.xc_byo_cert && var.xc_byo_cert_name != "") ? [1] : []
    content {
      add_hsts              = false
      http_redirect         = true
      enable_path_normalize = true
      tls_cert_params {
        no_mtls = true
        certificates {
          name      = var.xc_byo_cert_name
          namespace = var.xc_byo_cert_namespace
        }
        tls_config {
          default_security = true
        }
      }
    }
  }

  app_firewall {
    name      = volterra_app_firewall.waap-tf.name
    namespace = var.xc_namespace
  }

  # WAF Exclusion 
  dynamic "waf_exclusion" {
    for_each = (var.xc_waf_exclusion && var.xc_waf_exclusion_policy_name != "") ? [1] : []
    content {
      waf_exclusion_policy {
        name      = var.xc_waf_exclusion_policy_name
        namespace = var.xc_waf_exclusion_policy_namespace
      }
    }
  }

  disable_waf                     = false
  round_robin                     = true
  service_policies_from_namespace = true
  user_id_client_ip               = true
  source_ip_stickiness            = true

  # Data Guard Rules
  dynamic "data_guard_rules" {
    for_each = var.xc_data_guard ? [1] : []
    content {
      metadata {
        name = format("%s-data-guard-%s", local.project_prefix, local.build_suffix)
      }
      apply_data_guard = true
      any_domain       = true
      path {
        prefix = "/"
      }
    }
  }

  # Sensitive Data Policy
  dynamic "sensitive_data_policy" {
    for_each = var.xc_sensitive_data_policy ? [1] : []
    content {
      sensitive_data_policy_ref {
        name      = volterra_sensitive_data_policy.this[0].name
        namespace = volterra_sensitive_data_policy.this[0].namespace
      }
    }
  }

  # API Discovery
  dynamic "enable_api_discovery" {
    for_each = var.xc_api_disc ? [1] : []
    content {
      enable_learn_from_redirect_traffic = true
      default_api_auth_discovery         = var.xc_api_auth_discovery

      discovered_api_settings {
        purge_duration_for_inactive_discovered_apis = 5
      }

      dynamic "api_crawler" {
        for_each = var.xc_api_crawler ? [1] : []
        content {
          api_crawler_config {
            domains {
              domain = var.app_domain
            }
          }
        }
      }
    }
  }

  # API Protection (Definition + Validation)
  dynamic "api_specification" {
    for_each = var.xc_api_pro ? [1] : []
    content {
      api_definition {
        name      = volterra_api_definition.api-def[0].name
        namespace = volterra_api_definition.api-def[0].namespace
        tenant    = var.xc_tenant
      }

      validation_disabled = !var.xc_api_val

      dynamic "validation_all_spec_endpoints" {
        for_each = var.xc_api_val_all ? [1] : []
        content {
          validation_mode {
            dynamic "validation_mode_active" {
              for_each = var.xc_api_val_active ? [1] : []
              content {
                request_validation_properties = var.xc_api_val_properties
                enforcement_block             = var.enforcement_block
                enforcement_report            = var.enforcement_report
              }
            }

            dynamic "response_validation_mode_active" {
              for_each = var.xc_resp_val_active ? [1] : []
              content {
                response_validation_properties = var.xc_resp_val_properties
                enforcement_block              = var.enforcement_block
                enforcement_report             = var.enforcement_report
              }
            }
          }

          fall_through_mode {
            fall_through_mode_allow = var.fall_through_mode_allow

            dynamic "fall_through_mode_custom" {
              for_each = var.fall_through_mode_allow ? [] : [1]
              content {
                open_api_validation_rules {
                  metadata {
                    name = format("%s-apip-fall-through-%s", local.project_prefix, local.build_suffix)
                  }
                  action_report = var.fall_through_mode_report
                  action_block  = !var.fall_through_mode_report
                  base_path     = "/"
                }
              }
            }
          }

          settings {
            oversized_body_fail_validation = true
            property_validation_settings_custom {
              query_parameters {
                disallow_additional_parameters = true
              }
            }
          }
        }
      }

      dynamic "validation_custom_list" {
        for_each = var.xc_api_val_custom ? [1] : []
        content {
          open_api_validation_rules {
            metadata {
              name = format("%s-apip-val-rule-block-%s", local.project_prefix, local.build_suffix)
            }

            validation_mode {
              dynamic "validation_mode_active" {
                for_each = var.xc_api_val_active ? [1] : []
                content {
                  request_validation_properties = var.xc_api_val_properties
                  enforcement_block             = var.enforcement_block
                  enforcement_report            = var.enforcement_report
                }
              }

              dynamic "response_validation_mode_active" {
                for_each = var.xc_resp_val_active ? [1] : []
                content {
                  response_validation_properties = var.xc_resp_val_properties
                  enforcement_block              = var.enforcement_block
                  enforcement_report             = var.enforcement_report
                }
              }
            }

            any_domain = true
            base_path  = "/"
          }

          fall_through_mode {
            fall_through_mode_allow = var.fall_through_mode_allow

            dynamic "fall_through_mode_custom" {
              for_each = var.fall_through_mode_allow ? [] : [1]
              content {
                open_api_validation_rules {
                  metadata {
                    name = format("%s-apip-fall-through-%s", local.project_prefix, local.build_suffix)
                  }
                  action_report = var.fall_through_mode_report
                  action_block  = !var.fall_through_mode_report
                  base_path     = "/"
                }
              }
            }
          }

          settings {
            oversized_body_fail_validation = true
            property_validation_settings_custom {
              query_parameters {
                disallow_additional_parameters = true
              }
            }
          }
        }
      }
    }
  }

  dynamic "api_protection_rules" {
    for_each = var.xc_api_pro ? [1] : []
    content {
      api_groups_rules {
        metadata {
          name = format("%s-apip-deny-rule-%s", local.project_prefix, local.build_suffix)
        }
        action {
          deny = true
        }
        base_path = "/api"
        api_group = join("-", ["ves-io-api-def", volterra_api_definition.api-def[0].name, "all-operations"])
      }

      api_groups_rules {
        metadata {
          name = format("%s-apip-allow-rule-%s", local.project_prefix, local.build_suffix)
        }
        action {
          deny = false
        }
        base_path = "/"
      }
    }
  }

  # API Rate Limit 
  dynamic "api_rate_limit" {
    for_each = var.xc_api_rate_limit ? [1] : []
    content {
      no_ip_allowed_list = true

      server_url_rules {
        any_domain = true
        base_path  = var.xc_api_rate_limit_base_path

        client_matcher {
          any_client = true
        }

        inline_rate_limiter {
          threshold = var.xc_api_rate_limit_threshold
          unit      = var.xc_api_rate_limit_unit
        }
      }
    }
  }

  # JWT Validation
  dynamic "jwt_validation" {
    for_each = var.xc_jwt_val ? [1] : []
    content {
      target {
        all_endpoint = true
      }
      token_location {
        bearer_token = true
      }
      action {
        block  = var.jwt_val_block
        report = var.jwt_val_report
      }
      jwks_config {
        cleartext = "string:///${var.jwks}"
      }
      reserved_claims {
        issuer = var.iss_claim
        audience {
          audiences = var.aud_claim
        }
        validate_period_enable = var.exp_claim
      }
    }
  }

  # BOT Configuration
  dynamic "bot_defense" {
    for_each = var.xc_bot_def ? [1] : []
    content {
      policy {
        javascript_mode    = "ASYNC_JS_NO_CACHING"
        disable_js_insert  = false
        js_insert_all_pages {
          javascript_location = "AFTER_HEAD"
        }
        disable_mobile_sdk = true
        js_download_path   = "/common.js"

        protected_app_endpoints {
          metadata {
            name = format("%s-bot-rule-%s", local.project_prefix, local.build_suffix)
          }
          http_methods = ["METHOD_POST", "METHOD_PUT"]
          mitigation {
            block {
              status = "Unauthorized"
              body   = "string:///WW91ciByZXF1ZXN0IHdhcyBCTE9DS0VEID4uPAo="
            }
          }
          path { path = "/trading/login.php" }
          flow_label {
            authentication {
              login {}
            }
          }
        }
      }
      regional_endpoint = "US"
      timeout           = 1000
    }
  }

  # Bot Defense Advanced 
  dynamic "bot_defense_advanced" {
    for_each = (var.xc_bot_def_advanced && var.xc_bot_def_advanced_web_policy_name != "") ? [1] : []
    content {
      web {
        name      = var.xc_bot_def_advanced_web_policy_name
        namespace = var.xc_bot_def_advanced_web_policy_namespace
      }
      js_insert_all_pages {
        javascript_location = "AFTER_HEAD"
      }
    }
  }

  # Client-Side Defense
  dynamic "client_side_defense" {
    for_each = var.xc_client_side_defense ? [1] : []
    content {
      policy {
        js_insert_all_pages = true
      }
    }
  }

  # DDoS
  dynamic "l7_ddos_protection" {
    for_each = var.xc_ddos_pro ? [1] : []
    content {
      mitigation_block       = true
      clientside_action_none = true
      ddos_policy_none       = true
      rps_threshold          = var.xc_l7_ddos_rps_threshold
    }
  }

  dynamic "ddos_mitigation_rules" {
    for_each = var.xc_ddos_pro ? [1] : []
    content {
      metadata {
        name = format("%s-ddos-rule-%s", local.project_prefix, local.build_suffix)
      }
      block = true
      ddos_client_source {
        country_list = ["COUNTRY_KP"]
      }
    }
  }

  # Slow-DDoS Mitigation
  dynamic "slow_ddos_mitigation" {
    for_each = var.xc_slow_ddos ? [1] : []
    content {
      request_headers_timeout = var.xc_slow_ddos_request_headers_timeout
      request_timeout         = var.xc_slow_ddos_request_timeout
    }
  }

  # IP Reputation
  disable_ip_reputation = var.xc_ip_reputation ? null : true

  dynamic "enable_ip_reputation" {
    for_each = var.xc_ip_reputation ? [1] : []
    content {
      ip_threat_categories = var.xc_ip_threat_categories
    }
  }

  # Threat Mesh
  enable_threat_mesh  = var.xc_threat_mesh ? true : null
  disable_threat_mesh = var.xc_threat_mesh ? null : true

  # Common Security Controls
  disable_rate_limit              = true
  enable_malicious_user_detection = var.xc_mud
  no_challenge                    = !(contains(var.xc_app_type, "mud") || var.xc_mud)

  dynamic "policy_based_challenge" {
    for_each = var.xc_mud ? [1] : []
    content {
      default_js_challenge_parameters       = true
      default_captcha_challenge_parameters = true
      default_mitigation_settings          = true
      no_challenge                         = true
      rule_list {}
    }
  }

  dynamic "policy_based_challenge" {
    for_each = contains(var.xc_app_type, "mud") && var.xc_multi_lb ? [1] : []
    content {
      malicious_user_mitigation {
        namespace = volterra_malicious_user_mitigation.mud-mitigation[0].namespace
        name      = volterra_malicious_user_mitigation.mud-mitigation[0].name
      }
    }
  }
}
