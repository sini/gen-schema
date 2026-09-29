# (c+) — den-hoag-markof-partial-preimage-znfjq. A kind's mark is minted over its distinguishing
# CONTENT as per-component tags: each option declaration's `type` (den-hoag-pa887, arm A), the
# declaration's `freeformType`, the collection values, `keySemantics`, `refs`, the computed fields,
# the opaque modules, and the PATH of every other attribute of a declaration and every kind-level
# definition, as a sealed component (den-hoag-egei0). A component carrying a minted identity enters by it, an inert
# one whole, one with no value at WHNF as `undefined`, anything else as the sealed marker. Two
# declarations that then mint one mark and differ only at a sealed component are refused BY NAME by
# `kindEq`, never merged; every other pair is decided.
{
  genSchema,
  genMerge,
  genAlgebra,
  genIdentity,
  ...
}:
let
  inherit (genSchema) mkSchemaOption kindEq refinements;
  T = genMerge.types;
  kindIn =
    args: decl:
    (genMerge.evalModuleTree {
      modules = [
        { options.schema = mkSchemaOption args; }
        { config.schema.host = decl; }
      ];
    }).config.schema.host;
  kindOf = kindIn { };
  opt = type: genMerge.mkOption { inherit type; };
  decides = e: (builtins.tryEval e).success;

  portTcp = kindOf { options.port = opt (genSchema.refined T.int refinements.tcpPort); };
  portPos = kindOf { options.port = opt (genSchema.refined T.int refinements.positive); };
  fieldInt = kindOf { options.port = opt T.int; };
  fieldStr = kindOf { options.port = opt T.str; };

  # A predicate built from a REGISTERED constructor (ADR-0034's migration form).
  its = genAlgebra.mkIntensional genIdentity.hashIdentity {
    revision = "r1";
    members.between = a: v: v >= a.lo && v <= a.hi;
  };
  between = lo: hi: {
    check = its "between" { inherit lo hi; };
    message = "must be in [${toString lo}, ${toString hi}]";
  };
  portWide = kindOf { options.port = opt (genSchema.refined T.int (between 1 65535)); };
  portLow = kindOf { options.port = opt (genSchema.refined T.int (between 1 1023)); };

  # F1 · a METHOD BODY is content: the option it answers through is typed `str`, the body is a lambda.
  greeter =
    word:
    kindOf {
      options.name = opt T.str;
      methods.greeting = genSchema.schemaFn "g" T.str ({ name }: "${word} ${name}");
    };
  hello = greeter "Hello";
  bye = greeter "Bye";

  # F1's CLASS, the other members: content in a lambda the option plane cannot see into.
  withFqdn =
    suffix:
    kindOf {
      options.name = opt T.str;
      options.fqdn = opt T.str;
      imports = [ ({ config, ... }: { config.fqdn = "${config.name}.${suffix}"; }) ];
    };
  lambdaDefault =
    f:
    kindOf {
      options.greet = genMerge.mkOption {
        type = T.raw;
        default = f;
      };
    };

  # F2 · inert content: a default, a kind-level definition, a collection value, a keySemantics value.
  defaulted =
    d:
    kindOf {
      options.port = genMerge.mkOption {
        type = T.int;
        default = d;
      };
    };
  defined = kindOf {
    options.port = genMerge.mkOption {
      type = T.int;
      default = 80;
    };
    config.port = 443;
  };
  parented =
    p:
    kindOf {
      options.name = opt T.str;
      parent = p;
    };
  categorised =
    c:
    kindIn {
      keySemantics.nixos.category = c;
    } { options.name = opt T.str; };
  # A default with content AND a throwing member: defined at WHNF, so sealed, never `undefined`.
  partial =
    a:
    kindOf {
      options.cfg = genMerge.mkOption {
        type = T.raw;
        default = {
          inherit a;
          b = throw "unset";
        };
      };
    };
  # A derivation default with a throwing passthru member (a package's shape, without nixpkgs).
  pkgDefault =
    n:
    kindOf {
      options.package = genMerge.mkOption {
        type = T.raw;
        default =
          (derivation {
            name = n;
            builder = "/bin/sh";
            system = "x86_64-linux";
          })
          // {
            passthru.broken = throw "meta";
          };
      };
    };
  # `freeformType` at both sites decides which undeclared instance keys are accepted.
  free =
    ft: kindOf ({ options.a = opt T.int; } // (if ft == null then { } else { freeformType = ft; }));
  moduleFree = kindOf {
    options.a = opt T.int;
    config._module.freeformType = T.attrsOf T.int;
  };
  # One option declaration differing at one attribute other than `type`.
  attributed =
    attr: v:
    kindOf {
      options.port = genMerge.mkOption (
        {
          type = T.int;
        }
        // {
          ${attr} = v;
        }
      );
    };
  # Two kinds differing only at `attr` (`a` against `b`): `true` is the reopened collision.
  sharesIdentity =
    attr: a: b:
    kindEq (attributed attr a) (attributed attr b);
  # A module pulled in through a shorthand module's `require`, which gen-merge joins into its
  # imports (`importsOf`): an attrset one differing in an inert default, a function one in a
  # default reading an instance's `name`.
  requireOpen =
    port:
    kindOf {
      require = [
        {
          options.port = genMerge.mkOption {
            type = T.int;
            default = port;
          };
        }
      ];
    };
  requireFn =
    word:
    kindOf {
      require = [
        (
          { config, ... }:
          {
            options.p = genMerge.mkOption {
              type = T.str;
              default = "${word}-${config.name}";
            };
          }
        )
      ];
    };

  # den-hoag-pa887 · THE ORDINARY IDIOM: a function module whose option attribute, or kind-level
  # definition, reads an instance's `name`, which the kind does NOT declare (`name` is injected per
  # instance). At kind level the read aborts UNCATCHABLY, so a kind identity demanded over it takes
  # the whole evaluation down; the cell below is green only if the mark never forces it.
  readsName =
    attr: word:
    kindOf {
      imports = [
        (
          { config, ... }:
          {
            options.p = genMerge.mkOption (
              {
                type = T.str;
                default = "x";
              }
              // {
                ${attr} = "${word}-${config.name}";
              }
            );
          }
        )
      ];
    };
  definesName =
    wrap: word:
    kindOf {
      imports = [
        (
          { config, ... }:
          {
            options.p = genMerge.mkOption { type = T.str; };
            config.p = wrap "${word}-${config.name}";
          }
        )
      ];
    };
  # den-hoag-egei0 C1-C3: `meta` (folded into config by gen-merge), a kind-level `_module` key,
  # and the same content stated by different modules or in a different order.
  metaK =
    v:
    kindOf (
      {
        options.meta.x = opt T.int;
      }
      // (if v == null then { } else { meta.x = v; })
    );
  argsK =
    v:
    kindOf {
      options.p = opt T.str;
      config._module.args.x = v;
    };
  portM = {
    options.port = genMerge.mkOption {
      type = T.int;
      default = 80;
    };
  };
  nameM = {
    options.name = opt T.str;
  };
  ordered = ms: kindOf { imports = ms; };
  definedIn =
    first:
    kindOf {
      imports = [
        ({ options.port = opt T.int; } // (if first then { config.port = 443; } else { }))
        (nameM // (if first then { } else { config.port = 443; }))
      ];
    };
  # C4: one kind value carried through a consumer option of type `t`.
  via =
    t: k:
    (genMerge.evalModuleTree {
      modules = [
        { options.k = genMerge.mkOption { type = t; }; }
        { config.k = k; }
      ];
    }).config.k;
  tr =
    e:
    let
      r = builtins.tryEval (builtins.deepSeq e e);
    in
    if r.success then r.value else "REFUSED";
  instanceP =
    kind:
    (genMerge.evalModuleTree {
      modules = [
        { options.hosts = genSchema.mkInstanceRegistry kind { }; }
        { config.hosts.a = { }; }
      ];
    }).config.hosts.a;

  # F3 · the `mkType` arm (gen-aspects' door), where the published `options` is `{ }`.
  aspectShaped =
    { defs, kind, ... }:
    {
      __functor = _: _: { imports = map (d: d.value) defs; };
      inherit kind;
    };
  # A schema's own `mkType` body is content too: this one adds a definition the kind level
  # cannot evaluate (it reads an instance's `name`).
  fqdnShaped =
    suffix:
    { defs, kind, ... }:
    {
      __functor = _: _: {
        imports = map (d: d.value) defs ++ [
          ({ config, ... }: { config.fqdn = "${config.name}.${suffix}"; })
        ];
      };
      inherit kind;
    };
  fqdnKind =
    suffix:
    kindIn { mkType = fqdnShaped suffix; } {
      options.name = opt T.str;
      options.fqdn = opt T.str;
    };
  mkTypeKind =
    r: kindIn { mkType = aspectShaped; } { options.port = opt (genSchema.refined T.int r); };
in
{
  flake.tests.kind-mark-cplus = {
    # A MINTED field type enters by its digest, so kinds differing only in a field's type separate.
    test-a-minted-field-type-separates-the-mark = {
      expr = {
        marksDiffer = fieldInt.__mint.minted != fieldStr.__mint.minted;
        decided = kindEq fieldInt fieldStr;
      };
      expected = {
        marksDiffer = true;
        decided = false;
      };
    };
    # A SEALED field enters as the marker: the predicate-only pair shares a mark and is REFUSED.
    test-a-sealed-field-shares-the-mark-and-is-refused = {
      expr = {
        sameMark = portTcp.__mint.minted == portPos.__mint.minted;
        decided = decides (kindEq portTcp portPos);
      };
      expected = {
        sameMark = true;
        decided = false;
      };
    };
    # A REGISTERED predicate mints, so its field enters by digest and the pair separates, decided.
    test-a-registered-predicate-mints-and-separates = {
      expr = {
        marksDiffer = portWide.__mint.minted != portLow.__mint.minted;
        decided = kindEq portWide portLow;
        enforces = map (r: [
          (r.check 80)
          (r.check 8080)
        ]) (genSchema.refined T.int (between 1 1023)).__schema.refinements;
      };
      expected = {
        marksDiffer = true;
        decided = false;
        enforces = [
          [
            true
            false
          ]
        ];
      };
    };
    # F1 — two kinds differing only in a METHOD BODY are refused, never called one kind.
    test-a-method-body-is-sealed-content = {
      expr = {
        sameMark = hello.__mint.minted == bye.__mint.minted;
        decided = decides (kindEq hello bye);
        reflexive = kindEq hello hello;
      };
      expected = {
        sameMark = true;
        decided = false;
        reflexive = true;
      };
    };
    # F1's class: a function module's body and a schema's `mkType` are each sealed content, so each
    # pair shares a mark and is refused, never merged.
    test-lambda-content-is-sealed = {
      expr = {
        moduleBody = decides (kindEq (withFqdn "a") (withFqdn "b"));
        schemaMkType = decides (kindEq (fqdnKind "a") (fqdnKind "b"));
        moduleBodySameMark = (withFqdn "a").__mint.minted == (withFqdn "b").__mint.minted;
      };
      expected = {
        moduleBody = false;
        schemaMkType = false;
        moduleBodySameMark = true;
      };
    };
    # F2 — inert content outside the option declarations enters the mark: each pair separates and
    # is decided `false`.
    test-inert-content-separates = {
      expr = {
        parent = kindEq (parented "net") (parented "site");
        category = kindEq (categorised "class") (categorised "channel");
      };
      expected = {
        parent = false;
        category = false;
      };
    };
    # ★ OPEN CONTENT IS REFUSED BY NAME, NEVER MERGED (den-hoag-egei0). An option enters the mark by
    # its `type` alone (den-hoag-pa887, arm A) and no other attribute of a declaration, and no
    # kind-level definition, is forced. Each such attribute's PATH is a sealed component instead: the
    # mark carries its marker, and `__sealed` a subject equal only to itself. So two kinds whose
    # open-attribute path sets agree share a mark and `kindEq` refuses them BY NAME at `open.*`; two
    # whose path sets differ separate and are decided. One cell per class.
    #
    # F2 (the znfjq gate's pair): an inert literal default, 80 against 443, shares one mark and is
    # refused.
    test-open-content-f2-inert-default-refused = {
      expr = {
        default = decides (sharesIdentity "default" 80 443);
        sameMark = (attributed "default" 80).__mint.minted == (attributed "default" 443).__mint.minted;
      };
      expected = {
        default = false;
        sameMark = true;
      };
    };
    # F2's definition member: a kind-level definition (`config.port = 443`) is a path the other
    # operand lacks, so the marks differ and the pair is decided two kinds.
    test-open-content-f2-kind-level-definition-separates = {
      expr = {
        decided = kindEq (attributed "default" 80) defined;
        sameMark = (attributed "default" 80).__mint.minted == defined.__mint.minted;
      };
      expected = {
        decided = false;
        sameMark = false;
      };
    };
    # F1 and the partly-defined class: a lambda, a partial and a derivation default are each refused
    # by name at the default's path, and none is forced.
    test-open-content-f1-non-inert-default-refused = {
      expr = {
        lambdaDefault = decides (kindEq (lambdaDefault (x: "a")) (lambdaDefault (x: "b")));
        partialDefault = decides (kindEq (partial 1) (partial 2));
        partialSealed = builtins.attrNames (partial 1).__sealed;
        derivationDefault = decides (kindEq (pkgDefault "hello") (pkgDefault "cowsay"));
      };
      expected = {
        lambdaDefault = false;
        partialDefault = false;
        partialSealed = [
          "open.options.cfg.default"
          "options.cfg.type"
        ];
        derivationDefault = false;
      };
    };
    # F1: an `apply` is refused by name.
    test-open-content-f1-apply-refused = {
      expr = decides (sharesIdentity "apply" (x: x) (x: x + 1));
      expected = false;
    };
    # N3's presentation keys: an instance module can read `options.port.description`, and a pair
    # differing there is refused.
    test-open-content-n3-presentation-refused = {
      expr = {
        description = decides (sharesIdentity "description" "one" "two");
        example = decides (sharesIdentity "example" 1 2);
        defaultText = decides (sharesIdentity "defaultText" "80" "443");
        visible = decides (sharesIdentity "visible" true false);
        internal = decides (sharesIdentity "internal" false true);
      };
      expected = {
        description = false;
        example = false;
        defaultText = false;
        visible = false;
        internal = false;
      };
    };
    # Behavioural attributes: `readOnly` decides whether an instance may define the option at all,
    # and `identity = false` removes a primitive option from the instance key set; a pair differing
    # there is refused.
    test-open-content-behavioural-attributes-refused = {
      expr = {
        readOnly = decides (sharesIdentity "readOnly" false true);
        identity = decides (sharesIdentity "identity" true false);
      };
      expected = {
        readOnly = false;
        identity = false;
      };
    };
    # Any attribute gen-merge does not know is carried on the declaration and refused like a known one.
    test-open-content-unknown-attribute-refused = {
      expr = decides (sharesIdentity "pa887Unknown" 1 2);
      expected = false;
    };
    # F2 under `require`: an attrset module reached through `require` is walked as an open module
    # like an imported one, so its inert default is refused too.
    test-open-content-f2-required-default-refused = {
      expr = decides (kindEq (requireOpen 80) (requireOpen 443));
      expected = false;
    };
    # C1: a structured module's `meta` is a kind-level definition (gen-merge folds it into config).
    test-open-content-meta-refused = {
      expr = {
        pair = decides (kindEq (metaK 80) (metaK 443));
        oneSided = kindEq (metaK 80) (metaK null);
        sealed = builtins.attrNames (metaK 80).__sealed;
      };
      expected = {
        pair = false;
        oneSided = false;
        sealed = [ "open.config.meta" ];
      };
    };
    # C2: a kind-level `_module` key other than `freeformType` is open content.
    test-open-content-module-args-refused = {
      expr = {
        pair = decides (kindEq (argsK "1") (argsK "2"));
        sealed = builtins.attrNames (argsK "1").__sealed;
      };
      expected = {
        pair = false;
        sealed = [ "open._module.args" ];
      };
    };
    # C3: which module states a key is not identity. A reordered twin and a definition moved into
    # another module reach the same paths and are REFUSED like the same-order twin, never split.
    test-open-content-module-order-is-not-identity = {
      expr = {
        reordered = decides (
          kindEq
            (ordered [
              portM
              nameM
            ])
            (ordered [
              nameM
              portM
            ])
        );
        reorderedSameMark =
          (ordered [
            portM
            nameM
          ]).__mint.minted == (ordered [
            nameM
            portM
          ]).__mint.minted;
        moved = decides (kindEq (definedIn true) (definedIn false));
        movedSameMark = (definedIn true).__mint.minted == (definedIn false).__mint.minted;
      };
      expected = {
        reordered = false;
        reorderedSameMark = true;
        moved = false;
        movedSameMark = true;
      };
    };
    # C4 · ENUMERATED EXCEPTION (the `kindEq` door): a kind carried through gen-merge's `anything`
    # is rebuilt, so comparing it with itself is refused (nix, Determinate) or `true` (Lix). Never
    # `false`: the mark is untouched. `raw` carries the value itself and decides `true`.
    test-open-content-transport-is-never-false = {
      expr =
        let
          k = defaulted 80;
        in
        {
          anything = tr (kindEq k (via T.anything k)) != false;
          attrsOfAnything = tr (kindEq k (via (T.attrsOf T.anything) { x = k; }).x) != false;
          listOfAnything = tr (kindEq k (builtins.head (via (T.listOf T.anything) [ k ]))) != false;
          raw = kindEq k (via T.raw k);
        };
      expected = {
        anything = true;
        attrsOfAnything = true;
        listOfAnything = true;
        raw = true;
      };
    };
    # ★ THE TWIN COST (the named refusal class). Two independent constructions of ONE declaration
    # carrying open content are refused: each subject is equal only to itself, and nothing forces the
    # content to compare it. One kind VALUE with itself is decided (`openReflexive` below). The only
    # remedy is the sealed-literal constructor (den-hoag-egei0 (i)), which puts an inert literal into
    # the mark so mark equality decides the pair; K3 captures and lambdas stay refused under it.
    test-open-content-twin-is-refused = {
      expr = decides (kindEq (defaulted 80) (defaulted 80));
      expected = false;
    };
    # Presence enters the mark: a default against none is decided two kinds, never refused.
    test-open-content-presence-one-sided = {
      expr = {
        decided = kindEq (attributed "default" 80) fieldInt;
        sameMark = (attributed "default" 80).__mint.minted == fieldInt.__mint.minted;
      };
      expected = {
        decided = false;
        sameMark = false;
      };
    };
    # A function module reached through `require` is a sealed component at `modules`, as one reached
    # through `imports` is: the pair mints and is refused (by name: `kind-mark-cplus-refusal`),
    # never called one kind.
    test-open-term-under-require-is-sealed = {
      expr = {
        mints = builtins.isString (requireFn "x").__mint.minted;
        distinguished = decides (kindEq (requireFn "x") (requireFn "y"));
      };
      expected = {
        mints = true;
        distinguished = false;
      };
    };
    # den-hoag-pa887 · the REGRESSION CELL. A kind whose option attribute other than `type`, or a
    # kind-level definition (plain or `mkDefault`), reads an instance's UNDECLARED `name` mints a
    # mark, and its instances mint an `id_hash` and read the value. One process per arm, on three
    # evaluators: the pa887 build report's probe. Before arm A this cell ABORTS (uncatchable
    # "attribute 'name' missing"), which takes the whole run down rather than failing the cell.
    # Such a term is not lost: its function module is a sealed component, so a pair differing only
    # there is refused (by name at 'modules': `kind-mark-cplus-refusal`).
    test-open-term-reading-instance-name-mints = {
      expr = {
        marks = map (k: builtins.isString (builtins.deepSeq k.__mint.minted k.__mint.minted)) (
          map (a: readsName a "x") [
            "default"
            "defaultText"
            "description"
            "example"
            "readOnly"
            "apply"
            "visible"
            "internal"
            "pa887Unknown"
          ]
          ++ [
            (definesName genMerge.mkDefault "x")
            (definesName (v: v) "x")
          ]
        );
        idHash = builtins.isString (instanceP (readsName "default" "x")).id_hash;
        defaultValue = (instanceP (readsName "default" "x")).p;
        definedIdHash = builtins.isString (instanceP (definesName genMerge.mkDefault "x")).id_hash;
        definedValue = (instanceP (definesName genMerge.mkDefault "x")).p;
        # ONE kind value: separately built twins of a function module are refused (znfjq's R1).
        reflexive =
          let
            k = readsName "default" "x";
          in
          kindEq k k;
        distinguished = decides (kindEq (readsName "default" "x") (readsName "default" "y"));
      };
      expected = {
        marks = builtins.genList (_: true) 11;
        idHash = true;
        defaultValue = "x-a";
        definedIdHash = true;
        definedValue = "x-a";
        reflexive = true;
        distinguished = false;
      };
    };
    # A declaration's `freeformType`, at either site, is content: each pair differs in which
    # undeclared keys an instance accepts, and is decided two kinds.
    test-freeform-type-is-content = {
      expr = {
        topLevel = kindEq (free (T.attrsOf T.int)) (free null);
        moduleSite = kindEq moduleFree (free null);
        sealed = builtins.attrNames moduleFree.__sealed;
      };
      expected = {
        topLevel = false;
        moduleSite = false;
        sealed = [ "freeformType" ];
      };
    };
    # F3 — the `mkType` arm's mark and `kindEq` read ONE plane: its predicate-only pair is refused,
    # and a refined against a bare field separates.
    test-mktype-arm-reads-one-plane = {
      expr = {
        predicateOnly = decides (kindEq (mkTypeKind refinements.tcpPort) (mkTypeKind refinements.positive));
        refinedVsBare = kindEq (mkTypeKind refinements.tcpPort) (
          kindIn { mkType = aspectShaped; } { options.port = opt T.int; }
        );
      };
      expected = {
        predicateOnly = false;
        refinedVsBare = false;
      };
    };
    # F4 — a non-kind operand is refused by name, catchably.
    test-kindEq-refuses-a-non-kind-catchably = {
      expr = decides (kindEq { name = "not-a-kind"; } fieldInt);
      expected = false;
    };
    # Controls: a kind is one kind with itself, open content included; minted and valueless twins are
    # one kind across evaluations; a field NAME separates.
    test-kindEq-decides-outside-the-collision = {
      expr = {
        reflexive = kindEq portTcp portTcp;
        nameDiffers = kindEq portTcp (kindOf {
          options.porte = opt (genSchema.refined T.int refinements.tcpPort);
        });
        mintedTwin = kindEq fieldInt (kindOf {
          options.port = opt T.int;
        });
        openReflexive =
          let
            k = defaulted 80;
          in
          kindEq k k;
        requiredTwin = kindEq (kindOf { options.name = opt T.str; }) (kindOf {
          options.name = opt T.str;
        });
      };
      expected = {
        reflexive = true;
        nameDiffers = false;
        mintedTwin = true;
        openReflexive = true;
        requiredTwin = true;
      };
    };
  };

  flake.testsError.kind-mark-cplus-refusal = {
    test-sealed-only-collision-refuses-by-name = {
      expr = kindEq portTcp portPos;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: two declarations of 'host' mint one identity and differ, compared as values, only at sealed component\\(s\\) 'options.port.type'; a sealed component has no identity \\(ADR-0034\\): migrate it to a first-order term, a registered constructor over inert arguments, so that it mints$";
      };
    };
    test-method-body-collision-names-the-method = {
      expr = kindEq hello bye;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: two declarations of 'host' mint one identity and differ, compared as values, only at sealed component\\(s\\) 'collections.methods.greeting'; .*$";
      };
    };
    # den-hoag-pa887: an open term reading an instance's `name` is distinguished by its function
    # module, the sealed `modules` component, and the collision is refused naming it.
    test-open-term-collision-names-its-module = {
      expr = kindEq (readsName "default" "x") (readsName "default" "y");
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: two declarations of 'host' mint one identity and differ, compared as values, only at sealed component\\(s\\) 'modules'; .*$";
      };
    };
    test-open-term-under-require-names-its-module = {
      expr = kindEq (requireFn "x") (requireFn "y");
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: two declarations of 'host' mint one identity and differ, compared as values, only at sealed component\\(s\\) 'modules'; .*$";
      };
    };
    # den-hoag-egei0: open content is refused naming the attribute's path.
    test-open-content-collision-names-the-attribute = {
      expr = kindEq (defaulted 80) (defaulted 443);
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: two declarations of 'host' mint one identity and differ, compared as values, only at sealed component\\(s\\) 'open\\.options\\.port\\.default'; .*$";
      };
    };
    test-non-kind-operand-refuses-by-name = {
      expr = kindEq { name = "not-a-kind"; } fieldInt;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: expected a kind value carrying a mint-backed mark \\(`__mint.minted`\\); got an attrset with no mark$";
      };
    };
  };

  # P1 · every `test-open-content-*-refused` pair, pinned by the refusal MESSAGE and the path it
  # names, so a refusal from anywhere else (a walker that throws) cannot pass for the named one.
  flake.testsError.kind-mark-cplus-open-refusal =
    let
      msg =
        comp:
        "^gen-schema: kindEq: two declarations of 'host' mint one identity and differ, compared as values, only at sealed component\\(s\\) '${comp}'; a sealed component has no identity \\(ADR-0034\\): .*$";
      at = attr: "open\\.options\\.port\\.${attr}";
      cell = expr: comp: {
        inherit expr;
        expectedError = {
          type = "ThrownError";
          msg = msg comp;
        };
      };
      attrPair =
        attr: a: b:
        cell (sharesIdentity attr a b) (at attr);
    in
    {
      test-inert-default = attrPair "default" 80 443;
      test-apply = attrPair "apply" (x: x) (x: x + 1);
      test-description = attrPair "description" "one" "two";
      test-example = attrPair "example" 1 2;
      test-defaultText = attrPair "defaultText" "80" "443";
      test-visible = attrPair "visible" true false;
      test-internal = attrPair "internal" false true;
      test-readOnly = attrPair "readOnly" false true;
      test-identity = attrPair "identity" true false;
      test-unknown-attribute = attrPair "pa887Unknown" 1 2;
      test-lambda-default = cell (kindEq (lambdaDefault (x: "a")) (
        lambdaDefault (x: "b")
      )) "open\\.options\\.greet\\.default";
      test-partial-default = cell (kindEq (partial 1) (partial 2)) "open\\.options\\.cfg\\.default";
      test-derivation-default = cell (kindEq (pkgDefault "hello") (pkgDefault "cowsay")) "open\\.options\\.package\\.default";
      test-required-default = cell (kindEq (requireOpen 80) (requireOpen 443)) "open\\.options\\.port\\.default";
      test-twin = cell (kindEq (defaulted 80) (defaulted 80)) "open\\.options\\.port\\.default";
      test-meta = cell (kindEq (metaK 80) (metaK 443)) "open\\.config\\.meta";
      test-module-args = cell (kindEq (argsK "1") (argsK "2")) "open\\._module\\.args";
      test-reordered-twin = cell (kindEq
        (ordered [
          portM
          nameM
        ])
        (ordered [
          nameM
          portM
        ])
      ) "open\\.options\\.port\\.default";
      test-moved-definition = cell (kindEq (definedIn true) (definedIn false)) "open\\.config\\.port";
    };
}
