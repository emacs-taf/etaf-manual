# ETAF Reference Manual

[中文](README.zh-CN.md)

The ETAF Reference Manual documents every public interface of the core ETAF packages: ecss, ekp, ebox, etaf, etaf-ui and etaf-db. Like the Emacs Lisp Reference Manual, it is organized by subsystem and object, gives one definition entry for each public function, macro, variable, hook, error, component, Host, property, style property and theme token, and explains how each subsystem works through concepts and public interfaces. It is written in English and Simplified Chinese.

This repository holds the book source and the `etaf-manual` package, which reads the book as data for Emacs tools and the site build. The book is checked against the code: a build fails when a signature differs from its package's Commentary, when the text names a symbol that is not public, when a stated version is out of date, when a translation diverges, or when a runnable example fails to mount.

The book currently contains the Reactivity chapter; the other chapters are being written. The interactive reader in Emacs and the HTML edition are not implemented yet.

## Requirements

Emacs 29.1 or later, ETAF 0.2.1 and etaf-ui 0.1.0. The gate also reads the ecss, ekp, ebox, etaf, etaf-ui and etaf-db checkouts, which it expects next to this repository.

## Use

Add the repository root to `load-path`, together with ETAF and its dependencies, then require the package:

```elisp
(require 'etaf-manual)

(plist-get (etaf-manual-definition 'etaf-ref) :chapter)
     ⇒ reactivity
```

To read a chapter, open its Markdown file below `book/en/` or `book/zh-CN/`. The supported API is listed in the Commentary of [`etaf-manual.el`](etaf-manual.el).

## Documentation

- [Writing the manual](docs/manual.md): the book format, the gate and the commands.
- [Reactivity](book/en/reactivity.md): refs, computed values, effects, watchers, scopes and the update cycle.

## Development

Run `make setup-hooks` after cloning. `make book-check` runs the gate, `make coverage` prints how many interfaces of each package have an entry, and `make check` adds structure, compilation, the public scenarios in [tests/acceptance.json](tests/acceptance.json), the API boundary check and the gate's tool tests.
