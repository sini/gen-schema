# Deterministic UID assignment from id_hash.
# Declares the uid option on the user kind (inherited by admin-user via mix-in).
#
# uid defaults to null ("assign automatically"). Setting uid explicitly
# on an instance overrides the computed assignment.
{ lib, ... }:
{
  config.schema.user.options.uid = lib.mkOption {
    type = lib.types.nullOr lib.types.int;
    default = null;
    internal = true;
    description = ''
      User ID. Set explicitly to override the deterministic assignment.
      null means "assign automatically from id_hash".
    '';
  };
}
