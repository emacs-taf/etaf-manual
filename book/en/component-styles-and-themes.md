# Component Styles and Themes

<!-- index: component styles; Theme; theme token; palette; hover style -->

A Component owns its default appearance through a static rule list and paints through the inherited Theme. The rule list is written with the same declaration grammar as any other style input, and `&` scopes it to the Component's roots. A Theme is a Context value that supplies Host defaults and named tokens; tokens let a static rule read the current Theme without becoming an inline dynamic property. This chapter defines the rule format, the runtime style replacement hook, state and hover styling, Theme provision and palette resolution, the token vocabulary and the moment a token resolves. [The Style System](style-system.md) defines the cascade and [Values](values.md) the value grammar; [Host](hosts.md) defines the properties the rules declare.

## Rules and roots

<!-- index: :styles; static rule list; component scope; rule specificity -->

The `:styles` clause of `etaf-define-component` is a static, ordered rule list without a wrapper: `((SELECTOR PROPERTY VALUE ...) ...)`. Its values are style data — a literal `(1 2)` or `bold` needs no quote — and the rules are compiled against the Ebox schema when the Component is defined, so an invalid property or value fails the definition.

The rules of one Component form one scope around its View. `&` and `:scope` match each Component root, including every root when a Component renders a fragment or a forest; an ordinary selector is rewritten to a strict descendant of the root, so `&.selected` styles a root itself while `.selected` styles owned descendants only. Rules of a parent Component do not reach into a nested Component's internals, and content supplied through a caller slot keeps the caller's scope. Inside one rule list, later rules win ties.

The rules enter Ebox at author origin, under the same cascade as inline Host properties: normal inline declarations outrank normal Component rules and important rules can override normal inline values. A nil Host property is omitted rather than declared. [Selectors](selectors.md) defines the selector language and the state model.

## Replacing styles at runtime

<!-- index: runtime style replacement; stylesheet reload -->

A preview or authoring tool can replace a Component's rule list without redefining the Component.

#### Function: etaf-component-set-styles (name styles)

Replace the static style form for Component NAME with STYLES.

**Arguments.** NAME is a registered Component name. STYLES uses the same `((SELECTOR PROPERTY VALUE ...) ...)` contract as `etaf-define-component`.

**Semantics.** STYLES is validated immediately against the Ebox schema, exactly like the `:styles` clause of a definition. On success it becomes the Component's rule list; the next mount or render lowers the new rules, while already mounted runtimes are not flushed implicitly, so their current paint stays until they commit again. The replacement is visible to every instance that renders afterwards.

**Returns.** STYLES.

**Errors.** `error→ etaf-component-definition-error` when NAME is not a registered Component, or when STYLES is not a valid rule list; the message names the Component and the rejected part.

**Example.**

```elisp
(etaf-component-set-styles
 'styled-card '(("&" :background-color "#1F2937")))
```

**See also.** the `:styles` clause in [Component](components.md).

## State styles and hover

<!-- index: state selector; selected class; hover style -->

State styling is selector styling: a rule such as `&.selected` or `&:disabled` matches the derived or authored state of a root, as [Selectors](selectors.md) describes. Components commonly carry an authored state class (`selected`, `disabled`, `active`) and switch it from a prop, which keeps the style static and the state on the retained Host.

Hover is different: it is a native Emacs text-property effect, not a retained visual state. A Host declares `:hover-style` with a plist of paint properties, and Ebox applies it as the mouse face while the pointer is over the node; `:hover-content` can replace one line of text the same way. Both are semantic properties of Hosts, defined in [Host](hosts.md). A `:hover-style` value may contain deferred Theme tokens: ETAF resolves them together with the rest of the instance's styles, because an unresolved token would be an invalid face attribute.

## Providing a Theme

<!-- index: Theme provision; Host defaults; UA origin -->

A Theme is an ordinary Context value under the key `theme`. It is a property plist that mixes two kinds of entries: a key that names a style property supplies a default for every Host in the subtree that accepts that property, and any other key is a named token for `etaf-theme-token` to read.

Host defaults from a Theme enter Ebox at UA origin, so normal author declarations — inline properties and Component rules — override them, while an important Theme default still beats an important author declaration. A Theme may be a ref or a computed source; like every provided Context value it stays reactive, and changing it republishes the defaults without converting them into inline properties.

#### Function: etaf-theme-provide (theme)

Provide THEME property defaults to the current Component subtree.

**Arguments.** THEME is a property plist such as `(:color "#F4F6FB" :bgcolor "#202634")`; every key is a keyword. It may also be a ref or a computed whose value is such a plist.

**Semantics.** The value is provided as the Context key `theme` to the current Component and its descendants, following the visibility and lifetime rules of [Context](context.md). Accepted style-property keys become Host defaults at UA origin, resolved against the same Theme before they reach Ebox; other keys remain ordinary token values. A reactive source is tracked, so a later write republishes the subtree. An invalid Theme shape or an invalid resolved default is rejected instead of publishing.

**Returns.** The provided value, as `etaf-provide` returns it.

**Errors.** `error→ etaf-context-error` with `("Theme defaults must be keyword/value pairs: %S")` when THEME is not an even-length plist, or `("Theme default must use a keyword: %S")` when a key is not a keyword.

**See also.** `etaf-theme-resolve-palette`, `etaf-theme-token`, and the Host defaults section of [Host](hosts.md).

## Resolving a palette

<!-- index: palette; light mode; dark mode; color pair -->

An application that ships both a light and a dark look keeps one palette of semantic roles and resolves it for an explicit mode. A palette value may be a plain color string (used in both modes), a `(LIGHT . DARK)` pair, a `(:light LIGHT :dark DARK)` plist, or nil; the result is an ordinary Theme plist that can be passed to `etaf-theme-provide`.

#### Function: etaf-theme-resolve-palette (palette mode)

Resolve semantic PALETTE token specs for explicit MODE.

**Arguments.** PALETTE is a keyword plist whose keys are Theme keys. Each value is a color string, a `(LIGHT . DARK)` pair, a `(:light LIGHT :dark DARK)` plist, or nil. MODE is `light` or `dark`.

**Semantics.** Each entry is resolved for MODE: a string is kept, a pair or plist contributes the corresponding light or dark value, and nil stays nil. The outcome contains the same keys and is a plain Theme value, so the caller can provide it and later re-resolve it for the other mode.

**Returns.** The resolved Theme plist.

**Errors.** `error→ etaf-context-error` with `("Theme palette mode must be light or dark: %S")` for a bad MODE, `("Theme palette must be a keyword plist: %S")` for a malformed palette, `("Theme palette key must be a keyword: %S")` for a non-keyword key, and `("Invalid ETAF palette color: %S")` for a value that is none of the four accepted shapes.

**Example.**

```elisp
(etaf-theme-resolve-palette
 '(:color "black" :bgcolor ("#FFF" . "#111") :accent (:light "#2563EB" :dark "#60A5FA"))
 'dark)
     ⇒ (:color "black" :bgcolor "#111" :accent "#60A5FA")
```

#### Function: etaf-theme-current-mode ()

Return the current frame color mode as `light` or `dark`.

**Semantics.** The mode is read from the frame's `background-mode` parameter: `dark` maps to `dark` and anything else to `light`. This is only the default argument for palette resolution — an application-owned light/dark toggle passes its own mode to `etaf-theme-resolve-palette` instead of changing the Emacs frame.

**Returns.** The symbol `light` or `dark`.

## Theme tokens

<!-- index: deferred token; token fallback; token transform; token resolution -->

A Theme token is deferred data. `etaf-theme-token` returns a small list that names a Theme key and carries a fallback; the list survives in a quoted static rule list, and ETAF replaces it with the Theme's value while lowering the declaration into Ebox. Because the substitution happens at the lowering boundary, many retained Hosts can share one static style instead of each carrying an inline dynamic property.

A token resolves when the declaration that contains it is lowered: an inline Host property resolves from the inherited Theme as the Host commits, a Component rule resolves when that instance's rule snapshot is built for the current Theme, a Host default from a Theme resolves as the default is computed, and a token nested in `:hover-style` resolves with the instance's styles. If the Theme has no value for the key, the token's default is used; a default that is itself a token is resolved first; a transform function, when given, is applied to the final value.

#### Function: etaf-theme-token (key &optional default transform)

Return a deferred Theme token for a static Component style.

**Arguments.** KEY is a keyword naming a Theme entry. DEFAULT is returned when the Theme has no value for KEY; it may be a nested token. TRANSFORM, when non-nil, is a pure function applied to the resolved value.

**Semantics.** The result is a list of the shape `(etaf-theme-token KEY DEFAULT [TRANSFORM])`. It is intentionally data: it can be placed directly in a quoted `((SELECTOR PROPERTY VALUE ...) ...)` rule list or returned from an inline property expression, and `etaf-theme-token-p` recognizes it. The token is replaced by its resolved value when the containing declaration is lowered, so a theme change re-lowers the static rules rather than rewriting each Host.

**Returns.** The deferred token list.

**Errors.** `error→ etaf-context-error` with `("Theme token keys must be keywords: %S")` when KEY is not a keyword, and `("Theme token transform must be callable: %S")` when TRANSFORM is neither nil nor callable.

**See also.** `etaf-theme-provide`, `etaf-theme-token-p`.

#### Function: etaf-theme-token-p (value)

Return non-nil when VALUE is a deferred ETAF Theme token.

**Semantics.** A value is a token when it is a proper list of two to four elements whose first element is the symbol `etaf-theme-token`, whose second element is a keyword, and whose optional fourth element is a function. Ordinary Theme plists and colors are not tokens.

**Returns.** Non-nil for a token, nil otherwise.

```elisp :run
(etaf-define-component demo-theme-chip ()
  :setup (etaf-theme-provide '(:chip-bg "#0F766E" :chip-fg "#ECFDF5"))
  :view (text "Online")
  :styles (("&" :background-color (etaf-theme-token :chip-bg "#334155")
               :color (etaf-theme-token :chip-fg "#F8FAFC"))))
(etaf-view (demo-theme-chip))
```

### The base token vocabulary

<!-- index: ui-fg; ui-bg; ui-border; ui-muted-fg; status color -->

The tokens in this section are the semantic color surface the official Component catalog reads. A component that uses a token supplies a built-in fallback, so a catalog that runs without a provided Theme still paints; providing that key in a Theme overrides the fallback for the whole subtree. The remaining, component-family tokens are the subject of the UI catalog chapter; the Theme token table appendix lists the full vocabulary.

Each entry names one role. A Theme may give the key any value the consuming declaration accepts; the base vocabulary uses colors.

#### Token: :ui-fg

The default foreground for catalog content.

**Semantics.** Official Components use it for ordinary text and glyphs, such as Label's default and strong variants, Selection rows, Table cells and the Data presentations. A Theme value under this key replaces the fallback.

#### Token: :ui-bg

The default background of application surfaces.

**Semantics.** Used by feedback surfaces, Data presentations and other application-level panels. It is a color for `:background-color`.

#### Token: :ui-border

The default border and divider color.

**Semantics.** Feedback Components use it for dividers and panel outlines; a consumer may transform the color into a full border declaration through its own style helper.

#### Token: :ui-muted-fg

The subdued foreground for secondary text.

**Semantics.** Used for hints, captions and inactive labels whose text should recede behind `:ui-fg`.

#### Token: :ui-accent

The accent color for emphasis and selection.

**Semantics.** Used by selection controls, media surfaces and the desktop shell for the selected state. It is the fill or text color that marks the active item.

#### Token: :ui-accent-fg

The foreground paired with `:ui-accent`.

**Semantics.** Names the text color for accent-filled surfaces, so a Theme can keep the accent fill and its foreground legible together.

#### Token: :ui-accent-soft-bg

The soft accent tint.

**Semantics.** Used for selected or secondary fills that carry less weight than a full `:ui-accent` surface, such as a selected desktop item background.

#### Token: :ui-disabled-fg

The foreground of a disabled control.

**Semantics.** Replaces `:ui-fg` while a control cannot be operated; used by Button, Checkbox and Selection.

#### Token: :ui-disabled-bg

The background of a disabled control.

**Semantics.** Keeps a disabled control's footprint visible while dimming its fill.

#### Token: :ui-disabled-border

The border color of a disabled control.

**Semantics.** Pairs with `:ui-disabled-bg` for outlined controls.

#### Token: :ui-danger-fg

The foreground of the danger status.

**Semantics.** Used for destructive or erroneous states, including Label's danger variant and feedback surfaces.

#### Token: :ui-danger-bg

The background of the danger status.

**Semantics.** The tint behind danger text in feedback surfaces.

#### Token: :ui-danger-border

The border of the danger status.

**Semantics.** Completes the danger triple with `:ui-danger-fg` and `:ui-danger-bg`.

#### Token: :ui-warning-fg

The foreground of the warning status.

**Semantics.** Used for cautionary states in feedback surfaces.

#### Token: :ui-warning-bg

The background of the warning status.

**Semantics.** The tint behind warning text.

#### Token: :ui-warning-border

The border of the warning status.

**Semantics.** Completes the warning triple.

#### Token: :ui-info-fg

The foreground of the informational status.

**Semantics.** Used for neutral notices and hints in feedback surfaces.

#### Token: :ui-info-bg

The background of the informational status.

**Semantics.** The tint behind informational text.

#### Token: :ui-info-border

The border of the informational status.

**Semantics.** Completes the informational triple.

#### Token: :ui-success-fg

The foreground of the success status.

**Semantics.** Used for confirming states, including Label's success variant and feedback surfaces.

#### Token: :ui-success-bg

The background of the success status.

**Semantics.** The tint behind success text.

#### Token: :ui-success-border

The border of the success status.

**Semantics.** Completes the success triple.

## Following the Emacs frame

<!-- index: frame background mode; theme toggle -->

ETAF does not install a theme hook and does not re-resolve a Theme when the Emacs frame changes: a Theme is application data, and the application decides when to rebuild it. The provided building blocks are `etaf-theme-current-mode`, which reports whether the current frame is light or dark, and `etaf-theme-resolve-palette`, which turns one palette into a Theme for an explicit mode. A common arrangement is to keep the palette in application data, resolve it for the mode when the application starts or when its own toggle changes, and provide the result; because a provided Theme may be a ref, re-providing the new mode republishes the subtree without re-rendering it.

## Rule files

<!-- index: rule file; .ecss; stylesheet reload -->

Rules written outside a Component definition can still become Component styles. An ECSS rule file is read as an ordered rule list (the rule-file interface of the ECSS part defines the reader), and `etaf-component-set-styles` accepts that list, so a stylesheet file, a preview tool or a hot-reload loop can replace a Component's rules without touching its definition. The `.ebox` file format and its companion rules belong to the Ebox part; a Component's own `:styles` clause remains static data and cannot itself read a file.
