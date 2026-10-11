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
