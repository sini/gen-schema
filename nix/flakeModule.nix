{ lib, ... }:
let
  schemaLib = import ./lib { inherit lib; };
in {
  # options.schema will be added when mkSchema exists
}
