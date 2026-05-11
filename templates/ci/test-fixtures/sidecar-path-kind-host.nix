# Helper module for sidecar-path-kind.nix test.
{ lib, ... }:
{
  options.name = lib.mkOption { type = lib.types.str; };
}
