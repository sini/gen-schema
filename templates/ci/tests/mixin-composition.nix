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
    beta
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

  # Shadowing order: composeMixins [a b] = b ⋆ a (via foldl').
  # Later mixins in the list have HIGHER priority (run last in Bracha's formula).
  # Earlier mixins run first and PROVIDE base values.
  # This matches the requires/provides dependency flow: earlier provides, later consumes + overrides.
  mixin-composition.test-compose-shadowing-order = {
    expr =
      let
        first = mkMixin {
          provides = [ "status" ];
          name = "first";
          define = _: { status = "from-first"; };
        };
        second = mkMixin {
          provides = [ "status" ];
          name = "second";
          define = _: { status = "from-second"; };
        };
        composed = composeMixins [ first second ];
        base = R.empty;
      in
      R.select (applyMixin composed base "test") "status";
    expected = "from-second";  # last listed mixin wins (has priority), first provides base
  };

  # Per-mixin direction: beta mixin is overridden by what came before
  mixin-composition.test-compose-mixed-direction = {
    expr =
      let
        provider = mkMixin {
          provides = [ "status" ];
          name = "provider";
          define = _: { status = "from-provider"; };
        };
        # Beta: this mixin's "status" should be overridden by provider's
        betaMixin = beta (mkMixin {
          provides = [ "status" ];
          name = "beta-mixin";
          define = _: { status = "from-beta"; };
        });
        composed = composeMixins [ provider betaMixin ];
        base = R.empty;
      in
      R.select (applyMixin composed base "test") "status";
    # provider is earlier (acc), betaMixin is beta so acc wins
    expected = "from-provider";
  };

  # Confirm: without beta, the later mixin would win
  mixin-composition.test-compose-without-beta-later-wins = {
    expr =
      let
        provider = mkMixin {
          provides = [ "status" ];
          name = "provider";
          define = _: { status = "from-provider"; };
        };
        overrider = mkMixin {
          provides = [ "status" ];
          name = "overrider";
          define = _: { status = "from-overrider"; };
        };
        composed = composeMixins [ provider overrider ];
        base = R.empty;
      in
      R.select (applyMixin composed base "test") "status";
    expected = "from-overrider";  # Smalltalk: later wins
  };
}
