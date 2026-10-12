# Extending the Framework

The earlier parts describe the framework as it is; this chapter describes how it grows. Some extensions are open to any consumer through a public macro or protocol, and some are work on the packages themselves, because this version deliberately exports no registration point for them. Each section below takes one of the seven documented extension routes, says when the route applies, names the public interfaces it uses, and gives the checks that keep the result in the ecosystem's shape. All of the routes end in the same three obligations: a public inventory entry, a manual entry in both languages, and an acceptance test.

## Which routes are open

<!-- index: extension point; package work -->

| Route | Open to consumers | Public interface |
| --- | --- | --- |
| New Behavior | Yes | `etaf-define-behavior`, `etaf-behavior-create` |
| New UI component | Yes | `etaf-define-component` |
| New Data backend | Yes | `etaf-data-source`, `etaf-data-source-load-page` |
| New image converter | Yes | `ebox-image-converters`, `ebox-image-prepare` |
| Expose an Ebox capability through ETAF | Yes, by extending ETAF | The new ETAF adapter, plus the Ebox interface it wraps |
| New Host kind | No: package work in Ebox and ETAF | Ebox author tags; ETAF Host kinds |
| New style property | No: package work in Ebox | `ebox-style-schema-id`, `ebox-style-property-accepted-p` |

The two closed routes are not an accident of incomplete work. A Host kind and a style property sit in the middle of the layout engine and the cascade, where an outside definition could break invariants the whole framework relies on, so they are added by changing the package that owns them. The five open routes cover what a consumer can build without touching those layers.

## Adding a Host kind

<!-- index: host kind; author tag -->

A new Host kind is warranted when an interface needs a primitive whose layout or interaction cannot be expressed with the existing kinds — `text`, `box`, `fragment`, `row`, `column`, `flex`, `grid` and `image`. Because the kind must participate in style acceptance, layout, hit testing and incremental damage, adding one is work in Ebox and then in ETAF; this version has no `define-host` style registration.

The steps follow the layering. In Ebox, choose the author tag and define what it means: which author properties it accepts, how it treats children, how it lays out and paints, and which part of it is interactive. Teach the builder and the node layer to accept the tag and reject the wrong shapes with a named error. In ETAF, add the Host kind to the View language and map it to the Ebox tag, including the semantic and event properties that apply and the validation of each. Expose any new query or mutation as a public ETAF interface rather than letting callers reach the node. Then update the Hosts chapter, the style-property applicability tables and the property-acceptance matrix, and add the acceptance scenarios.

The check is the same as for any Host: mount it in a real window, verify its layout at several viewport sizes, and exercise its focus, pointer, drag and input behavior if it has any. `etaf-runtime-host-props-for` must report the committed semantic properties, and the boundary gate must pass.

## Adding a style property

<!-- index: style property; schema; hot field -->

A new style property is warranted when a visual concept has no existing property and its value should participate in the cascade like the rest. Adding one is Ebox package work; the public interfaces report the result rather than accept a definition.

In Ebox, add the property to the style schema: its canonical name, aliases, initial value, whether it inherits, the contexts where it applies, its value validator and its membership in shorthands. If the property affects geometry, fill the corresponding hot field in the computed style record and mark the dirty bit that makes the flush recompute layout; a paint-only property needs the paint bit instead. The schema is registered with ECSS, so the computed style record and its provenance include the property automatically: writers then use it through rules and inline declarations, and readers through `ecss-computed-style-value`, `ecss-computed-style-present-p` and `ecss-computed-style-property-fact`. `ebox-style-property-accepted-p` is what a Host kind uses to accept or reject it.

Finally, update the style property reference with the value syntax, initial value, applicability, inheritance and paint-or-geometry effect, in both languages, and add scenarios for the validators, the shorthand expansion and the visible effect. A property that never changes a pixel or a geometry fact should not exist.

## Adding a Behavior

<!-- index: behavior extension; installer -->

A Behavior bundles semantic attributes and optional setup into one reusable unit, installed on a Host with `:use`. Use this route when the same interaction attribute set appears on several Hosts and you want one definition instead of copies. A Behavior is data, not a View node: it never renders and never introduces a container.

Define the constructor with `etaf-define-behavior`; its body must return an `etaf-behavior-create` spec. The spec's attributes merge into the Host's properties, and the reserved `:install` attribute runs setup and returns a cleanup function:

```elisp
(etaf-define-behavior demo-hint (label)
  (etaf-behavior-create
   'demo-hint
   :help-echo label
   :install (lambda ()
              (push 'installed log)
              (lambda () (push 'cleaned log)))))
```

Install it with `(text :use (demo-hint "press me") "hello")`. The installer runs when the Behavior is installed on a committed Host and the cleanup runs when it is removed or the Host is unmounted, which is what makes the route safe for resources. An invalid spec signals `etaf-behavior-error`. Keep the Behavior free of application policy: which Behavior to use and when belongs to the application, the attributes and cleanup belong to the Behavior.

## Adding a UI component

<!-- index: ui component; catalog entry; theme token -->

A new UI component is the most common extension: an application-specific control, or a new entry in the component catalog. Use `etaf-define-component` and choose exactly one frontend: `:view` when the output is a compiled structure, `:render` when ordinary Elisp is the clearer way to compute it. Instance state belongs in `:bindings` or in refs created by `:setup`; props are the inputs, and `:validate` rejects invalid ones before anything is published.

When the component belongs in etaf-ui, it also follows the catalog contract: one entry shape with a props table (name, type, default, controlled or `:bind` participation, meaning), then slots, reported events, keyboard and focus behavior, accessible metadata, the theme tokens it reads, and its size rules. New theme tokens are added to the catalog's default theme and read through `etaf-theme-token`. A catalog component uses ETAF public APIs only: it never calls an Ebox-prefixed function, which the workspace boundary gate checks.

An extension in flight can redefine a Component with `etaf-component-redefine-run` around the definition, which replaces the registry entry and invalidates compiled material; mounted instances of the old definition keep it until they are disposed. Validate a new component the way the catalog chapters do: a runnable example that mounts, a real GUI pass at wide, ordinary, compact and short viewports, and the manual entry in both languages.

## Adding a Data backend

<!-- index: data backend; source capability -->

A Data backend adapts a storage or service to the Data Source protocol. Create the source with `etaf-data-source` and the capabilities that describe it. `:load` is required: it receives the query, page and page size and returns a plist containing at least `:items`, optionally `:total`, `:page` and `:page-size`. Writes use optional `:mutate`, or `:mutate-v2` when the backend can report commit certainty, or `:mutate-batch` when it can apply a list of operations atomically. `:dispose` releases the backend when its controller stops, `:item-key` supplies stable selection identity, and `:provider` names the source in observation reports. Any callback may return `etaf-async` instead of a value.

Check the loading path without a Controller first: `etaf-data-source-load-page` loads and normalizes one page and is also what a prepared `:initial-result` comes from. Then hand the source to `etaf-data-controller`, which owns its lifecycle; keep one owning controller per source. A backend that cannot prove an external write result reports `external-unknown` rather than guessing, and it never implies local rollback. The shipped SQLite backend in etaf-db is the reference implementation, and [Data Sources](data-sources.md) defines the protocol in full.

## Adding an image converter

<!-- index: image converter; preparation -->

An image converter turns a source into an Ebox image character surface. It is a function of the source, the columns and the rows that returns a string of exactly ROWS lines of COLUMNS `▀` characters, each carrying a `face` plist with 24-bit foreground and background colors. Returning nil, signaling, or returning a malformed string declines the source, so the next converter in the list gets it.

Converters are consulted only during preparation. Install one at the front of `ebox-image-converters`, or pass a list with `:converters` to `ebox-image-prepare` for one call. Preparation resolves the source, runs the converters and caches the result; layout and buffer writes only reuse prepared content, which is why an image conversion can never stall a flush. Inspect the result with `ebox-image-info` and `ebox-image-content`, and call `ebox-image-cache-clear` when a converter's behavior changes so cached preparations are not reused. A converter must not mutate its source.

## Exposing an Ebox capability through ETAF

<!-- index: etaf adapter; boundary rule -->

When an application or a catalog component needs a capability that only Ebox has — a measurement, a retained update, viewport control — the capability is exposed as an ETAF interface, and the application uses that interface. This is the ecosystem's boundary rule, and it applies to framework extensions too: an Ebox-prefixed call stays inside ETAF or inside an Ebox-owned package such as etaf-ui's viewport helpers.

The extension goes in five steps. First confirm that no existing ETAF interface already provides the fact. Second, implement the capability in Ebox as a public interface with its own acceptance scenario, including the invariant it must keep — for example, that preparation work does not happen during layout. Third, add the ETAF adapter: it validates its Runtime and Host references before changing anything, routes retained edits through the normal commit so one call produces one publication and one revision, and keeps no parallel copy of Ebox facts. Fourth, add the definition entry and update the affected chapters in both languages, plus the test that the boundary gate runs. Fifth, migrate the callers to the new interface and remove the direct Ebox route.

The retained content and geometry updates are the model: `etaf-runtime-update-host-contents` and `etaf-runtime-update-host-geometries` validate every target first, publish once per call, and advance the revision once, which is exactly the contract an application needs from a high-frequency display surface.

## What every extension shares

<!-- index: extension checklist -->

Whatever the route, an extension is not finished until the same four things are true. The entry Commentary of the owning package lists the new public interfaces, because that Commentary is the authoritative inventory. The manual has a definition entry for each new public interface and the affected chapters updated in both languages, because the book gate checks coverage, signatures and translation structure. The change has an acceptance scenario in the package's `tests/acceptance.json` that exercises the new behavior through public interfaces, and no diagnostic that the framework reports during it is ignored. And a change that is visible or interactive has been exercised in a real window at the supported viewport sizes, because a mounted example in batch mode does not establish appearance or input latency.
