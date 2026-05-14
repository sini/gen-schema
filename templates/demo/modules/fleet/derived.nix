# Deterministic UID assignment from id_hash.
# Declares the uid option on the user kind (inherited by admin-user via mix-in).
{ lib, ... }:
{
  config.schema.user.options.uid = lib.mkOption {
    type = lib.types.int;
    readOnly = true;
    internal = true;
    description = "Deterministic UID derived from id_hash.";
  };
}
