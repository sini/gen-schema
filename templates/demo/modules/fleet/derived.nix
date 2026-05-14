# Deterministic UID assignment from id_hash.
# Declares the uid option on the user kind (inherited by admin-user via mix-in).
#
# uid defaults to 0 (sentinel for "not set"). The derive hook assigns a
# computed value for any instance where uid == 0. Setting uid explicitly
# on an instance overrides the computed assignment.
{ lib, ... }:
{
  config.schema.user.options.uid = lib.mkOption {
    type = lib.types.int;
    default = 0;
    internal = true;
    description = ''
      User ID. Set explicitly to override the deterministic assignment.
      Default (0) means "assign automatically from id_hash".
    '';
  };
}
