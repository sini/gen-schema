{ lib, ... }:
let
  schemaLib = import ./lib { inherit lib; };
in
{
  options.schema = schemaLib.mkSchemaOption { };
}
