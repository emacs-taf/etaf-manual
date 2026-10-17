# Writing the ETAF Reference Manual

[中文](manual.zh-CN.md)

This manual is for people who write or check chapters of the ETAF Reference Manual, and for tools that read the book through the `etaf-manual` package. It describes the source layout, the chapter format, what the gate checks and the commands that run it. The supported Lisp API is listed in the Commentary of [`etaf-manual.el`](../etaf-manual.el).

## What the manual contains

The book documents the public interfaces of the core packages: ecss, ekp, ebox, etaf, etaf-ui and etaf-db. It explains how each subsystem works, including data flow, ordering, invariants, errors and cost, through concepts and public interfaces. It does not name private functions, internal data structures or symbols that are absent from a package's Commentary, even when their names have no double hyphen. It describes only implemented behavior; a planned capability is at most mentioned as not implemented yet. It is a reference, organized by subsystem and object, not a tutorial.

## Source layout

| Path | Content |
| --- | --- |
| `book/book.json` | The book description: title, languages, packages, parts, chapters, appendices and indices |
| `book/en/ID.md` | The English chapter with identifier ID |
| `book/zh-CN/ID.md` | The Simplified Chinese translation of the same chapter |
| `etaf-manual.el`, `lisp/` | The package that reads the book as data |
| `scripts/check-book.el` | The gate |
| `scripts/check-references.py` | Checks that site links from other repositories resolve to a chapter and heading |
| `site/` | The website that publishes the book at <https://etaf.top> |
| `tests/` | The runnable-example and book-reading scenarios, and the gate's tool tests |

English is the primary language. Every chapter exists in every language, with the same file name.

`site/` is an Astro project that publishes the book.  `site/scripts/export-site.el`
reads the parsed book and writes the pages and the sidebar under
`site/src/content/` (generated content is untracked); `site/astro.config.mjs`
configures Starlight with English at the root and Simplified Chinese under
`/zh-cn/`; `site/scripts/publish.py` builds the site and deploys it as a new
release behind the `current` symlink.  Chapter links inside the pages are
rewritten to site routes, and `elisp :run` and `:figure` fences become plain
`elisp` blocks with a label, because a static page cannot mount a view.
The exporter also regenerates a bilingual not-found page with installation and
manual links. `site/src/content/i18n/` owns the localized accessibility text.
The Markdown processor preserves literal punctuation so chapter anchors stay
aligned with the book.

The landing page is a standalone Astro page, not a Starlight splash:
`site/src/components/Landing.astro` renders it from the copy, screenshots
and repository links in `site/src/data/landing.mjs`, and
`site/src/pages/index.astro` and `site/src/pages/zh-cn/index.astro` select
the language.  Starlight's content flow, heading wrappers and column width
fight a free layout, so Starlight keeps only the reading pages.  Both share
`site/src/styles/brand.css`, which holds the faces and the light and dark
palettes; `site/src/styles/custom.css` maps them onto Starlight and sets the
reading sizes.  The colour theme is stored under the `starlight-theme` key,
so a choice on either side carries over.

The site keeps an editorial look, so change these tokens rather than adding
local styles:

- Faces: Source Serif 4 for Latin text and headings, LXGW WenKai for Chinese
  text, Noto Serif SC for Chinese headings, and IBM Plex Mono with WenKai
  Mono for code and small labels.  Fonts are self-hosted from fontsource
  packages split by unicode-range; WenKai comes from its webfont CDN.
- Reading: 18px body text with a 1.75 line height (1.85 for Chinese) in a
  44rem column; navigation and the page outline stay at 15px and 14px.
- Colour: warm paper and ink, with the violet of the ETAF mark only for
  links and small accents.  No gradients, glows, glass blur or imitation
  window frames.
- Layout: no element scrolls sideways at any width, including code blocks
  and tables, which wrap; check 390 and 360 CSS pixels after a change.

## Publishing the site and packages

`make site-publish` rebuilds the site, uploads regular files over noninteractive
SSH and deploys them behind `current`. It preserves the existing `packages/`
directory. Use `PUBLISH_ARGS=--build-only` for a local build, or `--no-build` for
an already built site. The host must already serve `/srv/etaf.top/current` over
HTTPS; publication does not change Caddy or SSH configuration.

To publish a site and a validated workspace package release together:

```sh
make site-publish PUBLISH_ARGS='--packages /path/to/release'
```

`PUBLISH_ARGS='--packages-only /path/to/release'` updates only the package archive,
without rebuilding or changing the current pages. Both package modes require the
sibling workspace's `scripts/package-release.py stage` gate: a sealed checkpoint,
matching validation hashes and every supported target through both installation
paths. Partial diagnostics are rejected. Only the index, public manifest and
listed source tarballs are uploaded; installation reports and logs stay private.
The workspace tool manual owns the build and installation-check workflow.

The default SSH route is through `lightos` to `root@aliyun-hk`.
`ETAF_TOP_ROOT=direct` selects a direct connection; `ETAF_TOP_HOST` overrides the
host and `ETAF_TOP_KEEP` controls retained site releases (default 5, minimum 2).
The host needs Python 3.10+. A deployment lock serializes site and package
publication. Tar paths, file types, checksums and the public allowlist are checked
before the atomic switch. Existing package filenames cannot change bytes, and
package versions cannot go backward. Historical tarballs are carried into each
new release even when older site releases are pruned.

Each package publication also writes `packages/index.html`, generated from the
manifest: the install snippet, every package with its version, requirements and
checksum, and links to the manual. `package.el` still reads only
`archive-contents`, but a browser opening the bare directory then sees the
archive instead of a 404. The page is regenerated on every release and is not
part of the package manifest.

After switching, the deployer reads the served index and package bytes over HTTPS.
A failed check restores the previous `current`, then checks it again; a recovery
network failure is reported as unverified rather than successful rollback.
The client also reads back `current`. On transport interruption, inspect that link
before retrying; a lost SSH response is not evidence that publication failed.

## The book description

`book/book.json` is a JSON object with these fields:

| Field | Value |
| --- | --- |
| `title` | An object mapping each language to the book title |
| `languages` | Language codes; the first is the reference for translation checks |
| `packages` | The documented packages, whose entry files provide Commentary records and versions |
| `references` | Other repositories the text may name, such as the playgrounds; their Commentary records are also public |
| `coverage` | Packages and vocabularies whose every interface must have a definition entry |
| `parts` | Objects with `id`, a localized `title` and the `chapters` they contain, in reading order |
| `appendices` | Objects with `id`, a localized `title` and either a chapter file below `LANGUAGE/ID.md` or `generate`, the name of an implemented generator |
| `indices` | Objects with `id`, `generate` and a localized `title` |

Parts are numbered with Roman numerals, chapters with integers across the whole book and appendices with letters, all in the order of this file. Numbers are therefore not stable: refer to a chapter by its title, and link to it by file name.

A generated appendix or index has no source file. The package builds its Markdown from the definition entries and index markers, parses it with the same chapter parser and keeps it in the chapter's `:content`, so generated content is checked, translated and read like a written chapter.

## Chapter format

A chapter is a Markdown file. Write each paragraph, list item and table row on one line, and let the renderer fill it to the window: a line break inside a Chinese paragraph would render as a space.

### Chapter structure

A chapter uses these parts in this order, omitting those it does not need: a lead without a heading that says what the chapter covers; a Model section with the concepts and how they relate; Interface sections, one per object, each giving the concept, then the definition entries, then how the entries work together; a Semantic details section with ordering, edge cases, mechanisms and cost; and an Errors and recovery section. Mechanisms are explained through concepts and public interfaces, never by naming internal functions or data structures.

### Headings

- `#` is the chapter title; a chapter has exactly one.
- `##` and `###` are sections.
- `####` is always a definition entry. Headings deeper than level four are not allowed.

Every heading has an anchor computed as on GitHub: the text is lowercased, link text replaces each link, letters, digits, marks, hyphens and underscores are kept, spaces become hyphens, and everything else is dropped. A repeated anchor gets `-1`, `-2` and so on. `## Errors and recovery` therefore has the anchor `errors-and-recovery`, and `## 错误与恢复` has `错误与恢复`.

### Definition entries

A definition entry heading is `#### KIND: NAME SIGNATURE`. The kind label is English in every language.

| Kind | Names | Checked against |
| --- | --- | --- |
| `Function` | a function | its Commentary record |
| `Macro` | a macro | its Commentary record |
| `Variable` | a variable or user option | its Commentary record |
| `Hook` | a hook variable | its Commentary record |
| `Error` | an error condition | its Commentary record |
| `Component` | a component and its props | its Commentary record |
| `Host` | a Host kind, such as `text` | the Hosts ETAF defines |
| `Property` | a semantic or event property of Hosts, such as `:role` | the properties ETAF reads |
| `Style` | a style property, such as `:padding` | the style properties Ebox defines |
| `Token` | a theme token, such as `:ui-fg` | the tokens of the component catalog |
| `Syntax` | a form of View syntax, such as `expr` | not checked |

Copy the signature from the Commentary record; whitespace differences are ignored. Consecutive entry headings form a group that shares one description. The body starts with a one-sentence summary, followed by labeled paragraphs in this order, each only when it has content:

| English | Chinese | Content |
| --- | --- | --- |
| `**Arguments.**` | `**参数。**` | Each argument, its accepted values and its default |
| `**Semantics.**` | `**语义。**` | What happens, in order, including edge cases and timing |
| `**Returns.**` | `**返回。**` | The value returned |
| `**Errors.**` | `**错误。**` | Each condition, written ``error→ `CONDITION` `` with its data and when it is signaled |
| `**Example.**` | `**示例。**` | A short example |
| `**See also.**` | `**参见。**` | Related entries |

A style entry starts with a table giving the value syntax, the initial value, what the property applies to, whether it is inherited and whether it affects paint or geometry. Key bindings have no entry kind: list them in a table of key, command and context in the entry or section that owns the keymap.

### Notation

| Mark | Meaning |
| --- | --- |
| `⇒` | The value of the form before it |
| `▷` | What the buffer shows |
| `error→` | The form signals the condition that follows |
| `-\|` | Text written to `*Messages*` |

A result line written as a `;; ⇒` comment is checked: the gate evaluates the top-level form before the line and compares the value with the text after `⇒`. A result that describes an object without a stable printed form instead of giving a value ends with a `; display` comment and is not compared.

In signatures, argument names are lowercase. In prose, refer to an argument in uppercase, as in "SOURCE is a ref".

### Index terms

Put `<!-- index: TERM; TERM -->` on its own line after a heading to mark index terms for that section. The concept index is generated from these terms and the symbol index from the definition entries.

### Runnable examples

A fenced block opened with ```` ```elisp :run ```` is a runnable example. The package reads each top-level form and evaluates it with lexical binding, with etaf and etaf-ui loaded; the value of the last form must be an ETAF View. Separate top-level forms do not share local bindings. Name components defined in an example `demo-…`. A View child computed by Lisp must be wrapped as `(expr FORM)`. The acceptance tests mount every runnable example in every language, so an example that fails to evaluate, fails to mount or emits a warning fails `make check`.

An example must serve the entry or section it illustrates: give it a real task whose result is visible, keep it focused on that one feature, and do not assemble a multi-feature demo for it. An inline `**Example.**` block follows the same rule.

### Inline figures

A fenced block opened with ```` ```elisp :figure ````, optionally followed by a caption on the same line, is an inline figure. The package evaluates its last form to an ETAF View and the reader renders the View directly in the chapter as a static illustration, without run or stop controls, so a figure shows a box model, a layout or a component where prose alone is not enough. Figures are evaluated once when their section is rendered; the acceptance tests mount every figure in every language, so a figure that fails to evaluate or mount fails `make check`. Use a `:run` example instead when the reader should operate the result, and give each figure a caption that says what it shows.

### Links and names

Link to another chapter by its file name, optionally followed by a heading anchor, such as `reactivity.md` or `reactivity.md#scopes`, and only to chapters that exist. Refer to an unwritten chapter in plain text by its title. When that chapter is written, update those mentions to links in the same delivery.

A code span that names a symbol with a package prefix, such as `etaf-ref`, must name a Commentary record of a documented package or reference, or the name of a package or reference. Write other names, such as applications outside the book, as plain text. A code span that gives a package and a version, such as `etaf 0.2.1`, must match the `Version:` header of that package's entry file.

### Translations

Every language has the same chapters, the same sequence of section levels, the same definition entries with the same signatures, the same number of runnable examples and the same number of inline figures. Keep the code of runnable examples and figures identical; comments in other code blocks may be translated. Keep these terms untranslated in Chinese: Runtime, Host, Context, View, Action, Theme and Scope.

## What the gate checks

The gate reads the book and the sibling provider checkouts and reports each problem as `FILE:LINE: MESSAGE`. As a tool test, `scripts/check-references.py` validates external repository links and anchors that point into this book.

| Message | Cause |
| --- | --- |
| `Missing chapter`, `Chapter needs a level-1 title`, `Chapter has several titles` | A chapter file is missing or its title is wrong |
| `Level-4 headings are definition entries`, `Headings deeper than level 4` | A heading is not a valid section or entry |
| `Unclosed code fence` | A fenced block does not end |
| `chapter is not listed in book.json` | A Markdown file in a language directory is not part of the book |
| `KIND NAME is not a Commentary record` | A Commentary-checked entry names no record of that kind |
| `signature of NAME differs from PACKAGE Commentary: SIGNATURE` | The entry signature differs from the record |
| `unknown KIND NAME` | A Host, Property, Style or Token entry names no such item |
| `duplicate KIND entry for NAME` | Two entries of one kind name the same item |
| `` `NAME' is not a public interface `` | A code span names a symbol that is not public |
| `` `NAME' has no definition entry `` | A code span names a covered public interface without an entry |
| `NAME has no definition entry (coverage: SUBJECT)` | A covered package or vocabulary has an interface without an entry |
| `PACKAGE is version X, not Y` | A version span differs from the package |
| `link to unknown chapter: TARGET`, `link to unknown heading: TARGET` | A link has no target |
| `hard-wrapped line: write each paragraph on one line` | A paragraph or list item continues on the next line |
| `result line claims X but the form returns Y`, `result line is no readable value: TEXT`, `result line has no preceding form`, `result form signals ERROR` | A `;; ⇒` result line does not match the value of the form before it, or a bare `⇒` line does not follow a complete form or name a readable value |
| `appendix does not list KIND NAME` | Appendix A, B or D misses a public error condition, hook or variable of a core package |
| `definition entries differ from LANGUAGE`, `section structure differs from LANGUAGE`, `runnable examples differ from LANGUAGE`, `index terms differ from LANGUAGE` | A translation does not match the reference language |
| `generated NAME does not link KIND NAME`, `generated concept index does not link TARGET` / `does not list TERM` | Generated content misses an interface or index term it promises |
| `Unknown generated content` | `generate` names no implemented generator |
| `provider checkout missing: DIRECTORY`, `cannot read provider source`, `cannot load provider package PACKAGE` | A provider cannot be read or loaded |

## Commands

Run these from the repository root, with the provider repositories checked out as siblings:

| Command | Effect |
| --- | --- |
| `make book-check` | Run the gate |
| `make coverage` | Run the gate and print how many interfaces of each package and vocabulary have an entry |
| `make test` | Run the public scenarios in `tests/acceptance.json`, including mounting every runnable example |
| `make check` | Structure, compilation, gate, scenarios, API boundary and tool tests |
| `make site` | Build the website from `book/` into `site/dist/` |
| `make site-publish` | Build the website and publish it to <https://etaf.top> |

The gate can also run directly: `emacs -Q --batch -L . -L lisp -l scripts/check-book.el [--book DIRECTORY] [--providers DIRECTORY] [--coverage]`. `--book` defaults to `book/` and `--providers` to the parent directory.

Other repositories link chapters with site URLs such as `https://etaf.top/zh-cn/ebox-node-construction/`. `scripts/check-references.py` resolves every such link against the book (the chapter must exist and a section anchor must name one of its headings), and the tool tests run it over the workspace; the retired repository paths are reported as problems.

When a package changes a public interface, update the affected chapters in every language in the same delivery. When every interface of a package has an entry, add the package to `coverage` so the gate keeps it complete.

## Reading the book from Lisp

```elisp
(require 'etaf-manual)

(plist-get (etaf-manual-definition 'etaf-ref) :chapter)
     ⇒ reactivity

(mapcar (lambda (chapter) (plist-get chapter :title))
        (plist-get (etaf-manual-book "zh-CN") :chapters))
     ⇒ ("引言" "响应式系统")
```

`etaf-manual-book` caches the parsed book until a source file changes and signals `etaf-manual-error` for malformed sources. `etaf-manual-example-view` evaluates a runnable example and returns its View for `etaf-mount`.
