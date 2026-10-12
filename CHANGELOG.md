# Changelog

All notable changes to the ETAF Reference Manual and the `etaf-manual` package are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- The Emacs manual reader: `etaf-manual-open`, `etaf-manual-close` and
  `etaf-manual-lookup`, plus the headless session API
  (`etaf-manual-reader-create`, `etaf-manual-reader-state`,
  `etaf-manual-reader-view` and the navigation functions).  The reader shows
  an adaptive two-column layout with a collapsible navigation column,
  definition cards, language and palette switches, an index jump, and
  runnable examples that render in place with source, preview and
  side-by-side modes.  Every line keeps the standard line height, so
  scrolling never shifts the layout.  The reader's keys are declared on the page Host as
  `:keys', so `?' opens the ETAF key help listing them with their labels.
  A long chapter shows its first sections at once and appends the rest while
  Emacs is idle; a lookup renders through its entry immediately.
- The generated concept index groups terms under symbols and A–Z, filing
  Chinese terms by the Pinyin of their first character; the symbol index
  groups functions, macros, variables, hooks and errors by package and the
  other entries by kind.
- The Introduction and the Reactivity chapter in English and Simplified Chinese.
- The `etaf-manual` package: `etaf-manual-book`, `etaf-manual-definition`, `etaf-manual-example-view`, the `etaf-manual-language` option and the `etaf-manual-error` condition.
- A gate that checks the book against the provider packages: signatures, public names, versions, links, coverage, translation structure and one line per paragraph. Runnable examples are mounted by the acceptance tests.
