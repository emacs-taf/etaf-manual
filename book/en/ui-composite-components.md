# Composite Components

Two catalog components exist to compose existing contracts rather than introduce new ones. `etaf-date-picker` is the catalog's native text field plus a date contract, and `etaf-command-palette` is a modal dialog around a selectable list. Both are controlled and stateless: the caller owns the value or the command registry, and the components only render and report. [Text Input Controls](ui-text-input-controls.md) defines the field they build on, [Overlays](ui-overlays.md) the dialog, [Navigation and Collections](ui-navigation-and-collections.md) the list, and [UI Overview](ui-overview.md) the shared contract.

## The date picker

<!-- index: etaf-date-picker; ISO date; draft value; submit validation -->

#### Component: etaf-date-picker (&key value label placeholder on-change disabled bind)

Render a semantic date input on the catalog's native text field.

**Arguments.** VALUE is the controlled value: an ISO `YYYY-MM-DD` string or nil. LABEL defaults to `"Date"`. PLACEHOLDER (default `"YYYY-MM-DD"`) shows while the field is empty. ON-CHANGE receives the accepted value: a complete date string, or nil when the field is emptied. DISABLED removes editing, and BIND replaces VALUE and ON-CHANGE with a writable ref, following `etaf-text-input`.

**Semantics.** Editing is native and in place, exactly as the text field describes. A partial date is a draft: keystrokes that do not yet form a complete date are not reported, and the last accepted value stays. Submitting rejects an entry that is neither empty nor a complete date with a readable error naming the label, instead of writing it. The check is a shape check — four digits, two digits, two digits — so a well-formed but non-existent date such as `2026-13-01` is accepted as a value; enforcing calendar validity is the application's business rule.

**Returns.** A View.

**Errors.** `error→ etaf-component-call-error` when VALUE is neither nil nor an ISO `YYYY-MM-DD` string. Submitting an invalid draft signals `user-error` with the label and the expected form and leaves the value unchanged.

**Example.**

```elisp
(etaf-date-picker :value "2026-01-15" :label "Due"
                  :on-change (lambda (date) (setq due date)))
```

**See also.** `etaf-text-input`, `etaf-calendar`.

## The command palette

<!-- index: etaf-command-palette; modal list; command registry -->

#### Component: etaf-command-palette (&key open title items on-select on-close)

Compose a modal Dialog and List for caller-owned command selection.

**Arguments.** OPEN is a value, ref or computed. TITLE defaults to `"Command palette"`. ITEMS follows `etaf-list`: item plists with a unique `:key`, a nonempty string `:title` and an optional `:description` — a command's name is its title, not a menu label. ON-SELECT receives the chosen key and ON-CLOSE is required.

**Semantics.** While open, the palette is a centered modal dialog of `(ch 56)` rows wide whose body is one selectable list and whose default footer offers a close button; Escape and the header `x` request ON-CLOSE like any dialog. The palette owns no command registry, filtering or execution: the application supplies the items, decides what a key means and closes the dialog.

**Returns.** A View.

**Errors.** `error→ etaf-component-call-error` when ON-CLOSE is not a function; the list's own item contract applies to ITEMS.

**Example.**

```elisp
(etaf-command-palette :open palette :on-close (lambda () (setf palette nil))
                      :items '((:key save :title "Save file")
                               (:key open :title "Open file"))
                      :on-select #'run-command)
```

**See also.** `etaf-list`, `etaf-dialog`.

## Markdown document rendering

<!-- index: markdown; document tree; palette; render callback -->

Markdown document rendering turns Markdown text into ordinary ETAF Views for a previewer, a manual reader or any other document view.  It works in two steps: `etaf-ui-markdown-parse` parses the text into a block tree that carries no presentation facts, and the render functions turn that tree plus an environment plist into Views.  Both steps are pure functions without a buffer, runtime state or file, so one code path serves headless tests and a mounted Component alike.

#### Function: etaf-ui-markdown-parse (text &optional flavor)

Parse Markdown TEXT into a document plist.

**Arguments.** TEXT is the Markdown source.  FLAVOR selects the dialect: a name from `etaf-ui-markdown-flavors` (`gfm` is the default), a feature plist overriding individual extension flags, or nil for `etaf-ui-markdown-flavor`.

**Semantics.** Parsing covers CommonMark block and inline structure plus the GitHub extensions: pipe tables, task list items, strikethrough, bare autolinks, footnotes and alert blocks; YAML front matter is stripped into document metadata.  A block is a plist whose `:type` is `heading`, `paragraph`, `code-block`, `blockquote`, `list`, `table`, `thematic-break`, `html-block` or `footnote-def`; an inline's `:type` is `text`, `code`, `emph`, `strong`, `strike`, `link`, `image`, `autolink`, `footnote-ref`, `html` or `break`.  The tree carries no presentation facts: the render functions own every style and ETAF node choice.  Headings get stable unique anchors, and link reference definitions and footnote definitions are collected while blocks are read and resolved into inline nodes.  Parsing is pure Elisp and reads no buffer, file or network.

**Returns.** A document plist: `:meta` (front matter alist), `:title`, `:children` (top-level blocks with heading anchors), `:outline` (document-order `(LEVEL TEXT ID)`), `:footnotes` (with `:label`, `:number` and `:children`) and `:features` (the resolved extension plist).

**Errors.** An unknown dialect name signals `error→ etaf-ui-markdown-error`.

**Example.**

```elisp
(etaf-ui-markdown-parse "# Title\n\nBody.\n")
```

**See also.** `etaf-ui-markdown-view-blocks`, `etaf-ui-markdown-flavors`.

#### Function: etaf-ui-markdown-view-block (block env)

Render one block as an ETAF View, or nil when it has no rendered content.  BLOCK is one top-level block of `etaf-ui-markdown-parse` and ENV is the environment plist described by `etaf-ui-markdown-view-blocks`.  A block that expands to several Views is wrapped in one column, so callers own one node per block for scrolling, selection or per-block references.

#### Function: etaf-ui-markdown-view-blocks (blocks env &optional tight)

Return the list of Views for BLOCKS in document order, or nil for empty input.  Consecutive blocks are separated by one blank line unless TIGHT is non-nil.  The list carries no container, so callers wrap it themselves; render the `:footnotes` Views and append them when the document's footnote definitions belong in the flow.  ENV's `:palette` is required: an alist of semantic color keys (`:ink`, `:muted`, `:faint`, `:heading`, `:accent`, `:accent-soft`, `:panel`, `:code-bg` (optional; inline code and code blocks use it when present and fall back to `:panel`), `:border`, `:quote-bg`, `:quote-bar`, `:table-header`, `:table-stripe`, `:ok`, `:ok-soft`, `:warn`, `:warn-soft`, `:danger`, `:danger-soft`, `:important` and `:important-soft`); every color is read through it, so a palette change never leaks a half-updated set of colors, and an unknown key signals `error→ etaf-ui-markdown-error`.  The remaining entries are callbacks: `:open-link` receives a link URL, and every rendered link also carries the `:accent-soft` palette color as its pointer-hover face; `:footnote-jump` receives a footnote label; `:render-media (kind node env)` returns the View for media, where KIND is `image`, `video`, `inline-image` or `html-media`, and without it media falls back to its alt text or URL; `:render-code-block (block env)` may return a View for a code block and nil keeps the default fenced block; `:code-link (text)` is called with the text of every code span and may return a URL or a (URL . HELP) cons to make that span a link, which keeps the code style and calls `:open-link` with URL when activated, its help echo being HELP or URL; `:alert-labels` overrides the callout labels kind by kind; and `:features`, the document's resolved extension plist, gates whether alert blocks render as callouts; `:line-grid` non-nil keeps every line at the standard line height, for documents that scroll beside other content: headings and footnote references keep the body font size, a level-1 heading uses the accent color and a level-2 heading gains a left accent bar, so scrolling never changes the height of the lines it reveals.  Table columns share the width in proportion to their widest cell, keep a short unbreakable run such as a CJK word whole, and wrap longer cells at word boundaries.  HTML comments render as nothing.

#### Variable: etaf-ui-markdown-flavor

Default markdown dialect of `etaf-ui-markdown-parse`.

**Semantics.** An explicit FLAVOR argument wins over it.  `gfm` enables the GitHub extensions and front matter, `commonmark` parses the core specification only, and a feature plist toggles individual extensions.

**See also.** `etaf-ui-markdown-parse`, `etaf-ui-markdown-flavors`.

#### Variable: etaf-ui-markdown-flavors

Named dialects and the extension flags they enable.

**Semantics.** `commonmark` is the CommonMark core; `gfm` adds the GitHub extensions the renderer also treats as its default: tables, task lists, strikethrough, bare autolinks, footnotes and alert blocks, plus front matter, which is a document convention rather than a markdown extension.

**See also.** `etaf-ui-markdown-parse`.

#### Error: etaf-ui-markdown-error

The condition of a rejected markdown document operation.

**Semantics.** An unknown dialect name signals it during parsing; a missing `:palette` or a color key the palette does not define signals it during rendering, before any View is published.  The data is a list carrying a description string.

**Recovery.** A failure produces no half-rendered document: a failed parse has no block tree and a failed render publishes no View.  Fix the dialect or supply the palette keys and call again.

**See also.** `etaf-ui-markdown-parse`, `etaf-ui-markdown-view-blocks`.

## Errors and recovery

- The date picker separates a draft from an error: text that is not yet a complete date is simply not reported, and submitting it signals `user-error` without writing the value; cancelling the session restores the activation value.
- The palette composes the list's validation: a malformed item list fails the render with `etaf-component-call-error` before any surface appears, and a missing close callback fails the same way.
- Both components are stateless: a rejected input leaves the caller's value and the mounted instance as they were.

**See also.** [UI Overview](ui-overview.md#errors-and-recovery).

```elisp :run
(etaf-view
 (column :width '(ch 60) :height '(lh 18) :item-gap '(lh 1)
   (etaf-date-picker :value "2026-01-15" :label "Due")
   (etaf-command-palette :open t :on-close #'ignore :on-select #'ignore
                         :items '((:key save :title "Save file")))))
```
