# Schema composition: an "external plugin" extending existing kinds.
#
# This module simulates what a separate flake input would do — extend the
# host and service schemas with monitoring-related fields. The extensions
# merge cleanly with the base kind definitions in host.nix and service.nix
# through deferred module merge. Neither module knows about the other.
{ lib, ... }:
{
  # Extend host with monitoring fields
  config.schema.host = {
    options.metricsPort = lib.mkOption {
      type = lib.types.int;
      description = "Port exposing Prometheus metrics.";
      default = 9100;
    };
    options.monitored = lib.mkOption {
      type = lib.types.bool;
      description = "Whether this host is scraped by the monitoring stack.";
      default = true;
    };
  };

  # Extend service with a health check path
  config.schema.service = {
    options.healthPath = lib.mkOption {
      type = lib.types.str;
      description = "HTTP health check endpoint.";
      default = "/health";
    };
  };
}
