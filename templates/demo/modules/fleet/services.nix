# Service instances — host field is a ref that resolves to the host instance.
{ ... }:
{
  fleet.services.nginx = {
    host = "igloo";
    port = 80;
  };

  fleet.services.postgres = {
    host = "iceberg";
    port = 5432;
  };
}
