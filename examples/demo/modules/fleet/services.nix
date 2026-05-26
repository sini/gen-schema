# Service instances — host field is a deferred ref, upstream is a direct ref.
# Demonstrates both string key coercion ("igloo") and instance value coercion.
{ config, ... }:
{
  fleet.services.nginx = {
    host = "igloo"; # string key → lookup in hosts registry
    port = 80;
    replicas = [
      "igloo"
      "iceberg"
    ];
  };

  fleet.services.postgres = {
    host = "iceberg"; # string key → lookup
    port = 5432;
    replicas = [ "iceberg" ];
  };

  fleet.services.gateway = {
    host = "igloo";
    port = 443;
    upstream = config.fleet.services.nginx; # instance value → passthrough
  };
}
