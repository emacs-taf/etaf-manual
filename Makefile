.DEFAULT_GOAL := check
.NOTPARALLEL:
EMACS ?= emacs
PYTHON ?= python3
LOAD_PATH = -L . -L lisp -L ../etaf -L ../etaf-ui -L ../ebox -L ../ecss -L ../ekp
SOURCES = lisp/etaf-manual-book.el etaf-manual.el scripts/check-book.el

.PHONY: all compile book-check coverage tool-check check clean

all: check

compile:
	rm -f *.elc lisp/*.elc scripts/*.elc tests/*.elc
	$(EMACS) -Q --batch $(LOAD_PATH) \
		--eval "(progn (require 'cl-lib) (setq load-prefer-newer t byte-compile-error-on-warn t))" \
		--eval '(unless (cl-every (function byte-compile-file) (quote ($(foreach file,$(SOURCES),"$(file)")))) (kill-emacs 1))'

# Validate book/ against the sibling provider checkouts; see docs/manual.md.
book-check:
	$(EMACS) -Q --batch -L . -L lisp --eval '(setq load-prefer-newer t)' -l scripts/check-book.el

# Print how many interfaces of each package already have a definition entry.
coverage:
	$(EMACS) -Q --batch -L . -L lisp --eval '(setq load-prefer-newer t)' -l scripts/check-book.el --coverage

tool-check:
	EMACS="$(EMACS)" $(PYTHON) -m unittest discover -s tests/tools -p 'test_*.py'

check: structure-check compile book-check acceptance api-check tool-check

clean:
	rm -f *.elc lisp/*.elc scripts/*.elc tests/*.elc

.PHONY: structure-check setup-hooks
structure-check:
	python3 scripts/check-repository.py
setup-hooks:
	git config --local core.hooksPath .githooks

.PHONY: acceptance
acceptance:
	python3 scripts/run-acceptance.py --emacs "$(EMACS)"

.PHONY: api-check
api-check:
	$(EMACS) -Q --batch -L . -L lisp $(API_PROVIDER_PATH) --eval '(setq load-prefer-newer t)' -l scripts/check-api.el
API_PROVIDER_PATH = -L ../ecss -L ../ekp -L ../ebox -L ../etaf -L ../etaf-ui -L ../etaf-db -L ../ebox-playground -L ../etaf-playground

.PHONY: test
test: acceptance
