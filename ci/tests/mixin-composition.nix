{
  lib,
  prelude,
  genSchema,
  genAlgebra,
  ...
}:
let
  R = genAlgebra.record;
  record = R;
  mixinLib = import ../../lib/mixin.nix { inherit prelude record; };
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
      metrics_port = (R.select "port" parent) + 1000;
    };
  };

  b = mkMixin {
    requires = [ "metrics_port" ];
    provides = [ "metrics_url" ];
    name = "b";
    define = parent: {
      metrics_url = "http://localhost:${toString (R.select "metrics_port" parent)}";
    };
  };
in
{
  flake.tests.mixin-composition.test-compose-effective-requires = {
    expr =
      (composeMixins [
        a
        b
      ]).requires;
    expected = [ "port" ];
  };

  flake.tests.mixin-composition.test-compose-effective-provides = {
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

  flake.tests.mixin-composition.test-compose-apply = {
    expr =
      let
        composed = composeMixins [
          a
          b
        ];
        base = R.fromAttrs { port = 8080; };
      in
      R.select "metrics_url" (applyMixin composed base "service");
    expected = "http://localhost:9080";
  };

  flake.tests.mixin-composition.test-compose-wrong-order-unsatisfied = {
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

  flake.tests.mixin-composition.test-is-composed = {
    expr =
      (composeMixins [
        a
        b
      ]).__isComposed or false;
    expected = true;
  };

  flake.tests.mixin-composition.test-compose-single = {
    expr =
      let
        composed = composeMixins [ a ];
        base = R.fromAttrs { port = 3000; };
      in
      R.select "metrics_port" (applyMixin composed base "service");
    expected = 4000;
  };

  # Shadowing order: composeMixins [a b] = b ⋆ a (via foldl').
  # Later mixins in the list have HIGHER priority (run last in § Bracha 1990 formula).
  # Earlier mixins run first and PROVIDE base values.
  # This matches the requires/provides dependency flow: earlier provides, later consumes + overrides.
  flake.tests.mixin-composition.test-compose-shadowing-order = {
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
        composed = composeMixins [
          first
          second
        ];
        base = R.empty;
      in
      R.select "status" (applyMixin composed base "test");
    expected = "from-second"; # last listed mixin wins (has priority), first provides base
  };

  # Per-mixin direction: beta mixin is overridden by what came before
  flake.tests.mixin-composition.test-compose-mixed-direction = {
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
        composed = composeMixins [
          provider
          betaMixin
        ];
        base = R.empty;
      in
      R.select "status" (applyMixin composed base "test");
    # provider is earlier (acc), betaMixin is beta so acc wins
    expected = "from-provider";
  };

  # Confirm: without beta, the later mixin would win
  flake.tests.mixin-composition.test-compose-without-beta-later-wins = {
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
        composed = composeMixins [
          provider
          overrider
        ];
        base = R.empty;
      in
      R.select "status" (applyMixin composed base "test");
    expected = "from-overrider"; # Smalltalk: later wins
  };
}
