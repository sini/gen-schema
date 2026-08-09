# field-ref — the VALUE-level reference datum: its identity law, its structural scan, and the
# scan's by-construction refusal of functions.
#
# Pure Nix cannot capture a throw's *message* (builtins.tryEval yields only success:bool), so every
# refusal below is pinned by asserting that the throw FIRES at the stated force point.
#
# ── THE HAZARD PAIR IS THE POINT OF THIS FILE ──
# A scan that treats a function as a leaf and one that refuses it are indistinguishable on every
# ordinary value, so a suite of ordinary values cannot tell them apart and a regression from the
# refusing scan back to the open one would pass in silence. `test-hazard-*` below is the pair that
# discriminates: the ref-in-data arm is the positive control (one hop under EITHER scan) and the
# ref-in-a-function-body arm is the discriminator (refused here; silently zero hops under the open
# scan, which is the failure-open mode the refusal exists to eliminate).
{
  genSchema,
  prelude,
  ...
}:
let
  inherit (genSchema)
    fieldRef
    isFieldRef
    fieldRefsIn
    ;

  # The refusal's position renderer. Nix cannot capture a throw's message — `builtins.tryEval`
  # yields only `success` — so the part of the error a user actually acts on is pinned by calling
  # the SHIPPED renderer, reached by importing the module directly. A golden that re-implemented it
  # would not be an oracle for the one that ships. `renderAt` is deliberately absent from the public
  # `lib`; `test-render-at-is-not-public-surface` below is what keeps that true.
  fieldRefLib = import ../../lib/field-ref.nix { inherit prelude; };
  inherit (fieldRefLib) renderAt;

  throws = e: (builtins.tryEval (builtins.deepSeq e e)).success == false;
  # The scan is lazy in its result spine, so a refusal buried in it needs forcing to observe.
  scanThrows = v: (builtins.tryEval (builtins.deepSeq (fieldRefsIn v) true)).success == false;

  theme = {
    name = "theme";
    id_hash = "a1b2c3d4deadbeef";
  };
  terminal = {
    name = "terminal";
    id_hash = "e5f6a7b8cafef00d";
  };

  r = fieldRef terminal [ "g" ];

  # The hazard pair: the SAME ref value, once as data and once inside a function body.
  refInData = {
    k = r;
  };
  refInFunction = {
    k = _: r;
  };

  # Ordinary settings-shaped data — no ref, no function anywhere.
  plainData = {
    a = 1;
    b = [
      "x"
      "y"
    ];
    c = {
      d = "e";
    };
  };

  nested = {
    outer = {
      xs = [
        "lit"
        (fieldRef theme [
          "font"
          "size"
        ])
      ];
    };
  };
in
{
  flake.tests.field-ref = {
    # ── the datum ──
    test-record-is-a-ref = {
      expr = isFieldRef r;
      expected = true;
    };
    test-plain-attrs-is-not-a-ref = {
      expr = isFieldRef { aspect = terminal; };
      expected = false;
    };
    test-scalar-is-not-a-ref = {
      expr = isFieldRef "terminal";
      expected = false;
    };
    # identity in ≡ identity out: the record carries the caller's own instance, never a name.
    test-identity-in-equals-out = {
      expr = r.aspect.id_hash;
      expected = terminal.id_hash;
    };
    test-path-preserved = {
      expr = r.path;
      expected = [ "g" ];
    };

    # ── the constructor's refusals ──
    test-refuses-string-target = {
      expr = throws (fieldRef "terminal" [ "g" ]);
      expected = true;
    };
    test-refuses-target-without-id-hash = {
      expr = throws (fieldRef { name = "terminal"; } [ "g" ]);
      expected = true;
    };
    test-refuses-empty-path = {
      expr = throws (fieldRef terminal [ ]);
      expected = true;
    };
    test-refuses-non-string-path-component = {
      expr = throws (fieldRef terminal [ 0 ]);
      expected = true;
    };

    # ── the scan ──
    # EMPTY CONTROL: the assertions below are non-emptiness claims, so the instrument must be shown
    # able to report a true zero as well as a hit.
    test-scan-of-ref-free-data-is-empty = {
      expr = fieldRefsIn plainData;
      expected = [ ];
    };
    test-scan-finds-ref-at-root = {
      expr = builtins.length (fieldRefsIn r);
      expected = 1;
    };
    test-scan-root-position-is-empty-path = {
      expr = (builtins.head (fieldRefsIn r)).at;
      expected = [ ];
    };
    test-scan-composes-attr-keys-and-list-indices = {
      expr = (builtins.head (fieldRefsIn nested)).at;
      expected = [
        "outer"
        "xs"
        1
      ];
    };
    test-scan-carries-target-and-path = {
      expr = builtins.map (h: {
        inherit (h.aspect) id_hash;
        inherit (h) path;
      }) (fieldRefsIn nested);
      expected = [
        {
          inherit (theme) id_hash;
          path = [
            "font"
            "size"
          ];
        }
      ];
    };

    # ── the hazard pair (see the header) ──
    # POSITIVE CONTROL: the same ref, as data, is one hop. True under either scan.
    test-hazard-control-ref-in-data-is-one-hop = {
      expr = builtins.length (fieldRefsIn refInData);
      expected = 1;
    };
    # DISCRIMINATOR: the same ref inside a function body is REFUSED, not silently skipped.
    # Under the open (function-as-leaf) scan this scan returns [ ] and this assertion goes red.
    test-hazard-ref-in-function-body-is-refused = {
      expr = scanThrows refInFunction;
      expected = true;
    };
    # NEGATIVE CONTROL: the refusal observes nothing on data, so `scanThrows` is not stuck true.
    test-hazard-control-plain-data-is-accepted = {
      expr = scanThrows plainData;
      expected = false;
    };
    # The refusal is positional, not top-level: a function nested under a list under an attrset is
    # refused too, so the scan is total everywhere it descends.
    test-refuses-function-nested-under-a-list = {
      expr = scanThrows {
        outer = [
          "lit"
          { inner = x: x; }
        ];
      };
      expected = true;
    };
    # ── the refusal's blame position, which is the part of the message a user acts on ──
    # Every arm above only asserts that the throw FIRES. These pin WHERE it says the function was,
    # so a dropped root case or a mis-composed list index cannot pass while breaking the error.
    test-render-at-dotted-attr-path = {
      expr = renderAt [
        "listen"
        "bind"
      ];
      expected = "listen.bind";
    };
    test-render-at-list-index-in-path = {
      expr = renderAt [
        "xs"
        1
        "deep"
      ];
      expected = "xs.1.deep";
    };
    test-render-at-root-is-named-not-empty = {
      expr = renderAt [ ];
      expected = "(the scanned value itself)";
    };
    test-render-at-single-component = {
      expr = renderAt [ "k" ];
      expected = "k";
    };
    # The renderer is reached by importing the module, NOT through the library's exports. This is
    # the assertion that keeps the golden above from quietly becoming a public-surface addition.
    test-render-at-is-not-public-surface = {
      expr = genSchema ? renderAt;
      expected = false;
    };
    # CONTROL for the row above: the same predicate reports true for a name that IS exported, so a
    # renamed or vanished export could not read as "correctly absent".
    test-control-public-surface-predicate-fires = {
      expr = genSchema ? fieldRefsIn;
      expected = true;
    };

    # An attrset carrying `__functor` is not a function to `builtins.isFunction`, but its member
    # IS one in a scanned position — so the attrset is refused too. The domain is data, without a
    # callable exception.
    test-functor-attrset-is-refused = {
      expr = scanThrows {
        __functor = self: _: 1;
        k = r;
      };
      expected = true;
    };
  };
}
