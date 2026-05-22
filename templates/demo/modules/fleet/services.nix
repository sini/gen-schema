# Service instances — host field is a deferred ref, upstream is a direct ref.
# Demonstrates both string key coercion ("igloo") and instance value coercion.
{ config, ... }:
{
  fleet.services.nginx = {
    host = "igloo"; # string key → lookup in hosts registry
    port = 80;
  };

  fleet.services.postgres = {
    host = "iceberg"; # string key → lookup
    port = 5432;
  };

  fleet.services.gateway = {
    host = "igloo";
    port = 443;
    upstream = config.fleet.services.nginx; # instance value → passthrough
  };
}
