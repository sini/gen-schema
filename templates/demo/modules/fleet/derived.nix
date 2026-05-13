# Deterministic UID assignment from id_hash.
{ lib, ... }:
let
  hexToInt =
    s:
    let
      hexChars = {
        "0" = 0;
        "1" = 1;
        "2" = 2;
        "3" = 3;
        "4" = 4;
        "5" = 5;
        "6" = 6;
        "7" = 7;
        "8" = 8;
        "9" = 9;
        "a" = 10;
        "b" = 11;
        "c" = 12;
        "d" = 13;
        "e" = 14;
        "f" = 15;
      };
    in
    lib.foldl' (acc: c: acc * 16 + hexChars.${c}) 0 (lib.stringToCharacters s);

  idFromHash =
    { min, max }:
    hash:
    let
      raw = hexToInt (builtins.substring 0 8 hash);
    in
    min + lib.mod raw (max - min);

  assignIds =
    range: instances:
    let
      sorted = lib.sort (a: b: a < b) (lib.attrNames instances);
    in
    (lib.foldl'
      (
        acc: name:
        let
          want = idFromHash range instances.${name}.id_hash;
          probe =
            slot:
            if !(acc.taken ? ${toString slot}) then
              slot
            else
              probe (range.min + lib.mod (slot - range.min + 1) (range.max - range.min));
          assigned = probe want;
        in
        {
          taken = acc.taken // {
            ${toString assigned} = true;
          };
          ids = acc.ids // {
            ${name} = assigned;
          };
        }
      )
      {
        taken = { };
        ids = { };
      }
      sorted
    ).ids;
in
{
  # uid option on user kind — shared by user and admin-user (via mix-in)
  config.schema.user.options.uid = lib.mkOption {
    type = lib.types.int;
    readOnly = true;
    internal = true;
    description = "Deterministic UID derived from id_hash.";
  };

  # Export helpers for registries.nix
  options._deriveHelpers = lib.mkOption {
    type = lib.types.raw;
    internal = true;
  };
  config._deriveHelpers = {
    inherit assignIds;
  };
}
