{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  R = genLib.record;
  record = R;
  mixinLib = import ../../../nix/lib/mixin.nix { inherit lib record; };
  inherit (mixinLib)
    mkMixin
    composeMixins
    applyMixin
    ;

  a = mkMixin {
    requires = [ "port" ];
    provides = [ "metrics_port" ];
    name = "a";
    define = parent: {
      metrics_port = (R.select parent "port") + 1000;
    };
  };

  b = mkMixin {
    requires = [ "metrics_port" ];
    provides = [ "metrics_url" ];
    name = "b";
    define = parent: {
      metrics_url = "http://localhost:${toString (R.select parent "metrics_port")}";
    };
  };
in
{
  mixin-composition.test-compose-effective-requires = {
    expr =
      (composeMixins [
        a
        b
      ]).requires;
    expected = [ "port" ];
  };

  mixin-composition.test-compose-effective-provides = {
    expr =
      (composeMixins [
        a
        b
      ]).provides;
    expected = [
      "metrics_port"
      "metrics_url"
    ];
  };

  mixin-composition.test-compose-apply = {
    expr =
      let
        composed = composeMixins [
          a
          b
        ];
        base = R.fromAttrs { port = 8080; };
      in
      R.select (applyMixin composed base "service") "metrics_url";
    expected = "http://localhost:9080";
  };

  mixin-composition.test-compose-wrong-order-unsatisfied = {
    expr =
      let
        composed = composeMixins [
          b
          a
        ];
      in
      composed.requires;
    expected = [
      "metrics_port"
      "port"
    ];
  };

  mixin-composition.test-is-composed = {
    expr =
      (composeMixins [
        a
        b
      ]).__isComposed or false;
    expected = true;
  };

  mixin-composition.test-compose-single = {
    expr =
      let
        composed = composeMixins [ a ];
        base = R.fromAttrs { port = 3000; };
      in
      R.select (applyMixin composed base "service") "metrics_port";
    expected = 4000;
  };
}
