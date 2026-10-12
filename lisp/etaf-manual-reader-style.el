;;; etaf-manual-reader-style.el --- Layout and surface design of the manual reader -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; The design system of the manual reader: one place that names every
;; surface, spacing and text rank the document application uses.  Views
;; compose these builders instead of styling themselves, so the header, the
;; navigation column, the article cards and the example viewers share one
;; look and a palette or spacing change lands in a single place.
;;
;; A rendering environment (`env') is a plist with `:palette' (semantic color
;; alist), `:theme' (palette name), `:viewport' (READER, WIDTH-IN-CHARACTERS
;; or nil when unknown) and `:reader' (the session).  The markdown renderer
;; receives the same environment, so document text and application chrome
;; read the same colors.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'etaf)
(require 'etaf-ui)

(defconst etaf-manual-reader--measure-max 96
  "Widest reading measure of the article column, in character cells.")

(defconst etaf-manual-reader--measure-min 44
  "Narrowest reading measure that still keeps prose readable.")

(defconst etaf-manual-reader--sidebar-width 34
  "Width of the navigation column in character cells.")

(defconst etaf-manual-reader--wide-threshold 104
  "Frame width, in character cells, that keeps the navigation column beside
the article; narrower frames collapse it into the overview screen.")

(defconst etaf-manual-reader--compact-threshold 88
  "Frame width, in character cells, below which the chrome drops details.
The brand, the breadcrumb, the language switch and the key hints all shorten
so nothing is truncated on a narrow frame.")

(defconst etaf-manual-reader--gutter '(lh 1)
  "Vertical padding inside panels and chrome bars, in line heights.")

(defconst etaf-manual-reader--inline-pad '((lh 0) (ch 2))
  "Horizontal padding inside panels and chrome bars.")

(defconst etaf-manual-reader--card-pad '((lh 1) (ch 2))
  "Padding inside document cards and callouts.")

;;;; Colors

(defun etaf-manual-reader--color (env key)
  "Return ENV's semantic color for KEY."
  (or (cdr (assq key (plist-get env :palette)))
      (signal 'etaf-manual-error
              (list (format "Unknown manual reader color: %S" key)))))

;;;; Surfaces

(defun etaf-manual-reader--border (env)
  "Return ENV's one-pixel rule."
  (list '(px 1) 'solid (etaf-manual-reader--color env :border)))

(defun etaf-manual-reader--page (env children &optional height)
  "Wrap CHILDREN in the reader page surface: full size, page colors.
The page is a flex column so the body owns the space left between the header
and the footer; a plain column would not distribute that remainder.  HEIGHT
overrides the page height; the reader passes one row less than the reported
viewport, because a graphical frame can reserve its last text row for the
window chrome while the runtime still counts it."
  (etaf-node 'flex
             (list :flex-direction 'column
                   :align-items 'stretch
                   :gap '((lh 0) (ch 0))
                   :width '(vw 100)
                   :height (or height '(vh 100))
                   :background-color (etaf-manual-reader--color env :bg)
                   :color (etaf-manual-reader--color env :ink)
                   :overflow 'hidden)
             children))

(defun etaf-manual-reader--surface (env children &optional props)
  "Return a bordered panel containing CHILDREN.
PROPS override the panel's own style."
  (etaf-node 'box
             (append (list :width 'stretch
                           :background-color (etaf-manual-reader--color env :panel)
                           :border (etaf-manual-reader--border env)
                           :padding etaf-manual-reader--card-pad
                           :box-sizing 'border-box)
                     props)
             children))

(defun etaf-manual-reader--chrome (env children &optional props)
  "Return a chrome bar (header or footer) containing CHILDREN."
  (etaf-node 'row
             (append (list :width 'stretch
                           :padding etaf-manual-reader--inline-pad
                           :item-gap '(ch 2)
                           :cross-align 'center
                           :background-color (etaf-manual-reader--color env :panel))
                     props)
             children))

(defun etaf-manual-reader--rule (env)
  "Return a one-line divider in ENV's border color."
  (etaf-node 'box
             (list :width 'stretch :height '(px 1)
                   :background-color (etaf-manual-reader--color env :border))
             nil))

(defun etaf-manual-reader--spacer (&optional lines)
  "Return an empty spacer LINES lines tall."
  (etaf-node 'box (list :height (list 'lh (or lines 1))) nil))

;;;; Text ranks

(defun etaf-manual-reader--brand (env text)
  "Return the application brand TEXT."
  (etaf-node 'text
             (list :font-weight 'bold
                   :color (etaf-manual-reader--color env :ink))
             (list text)))

(defun etaf-manual-reader--section-title (env text)
  "Return a section title above the article."
  (etaf-node 'text
             (list :font-weight 'bold
                   :font-size (round (* (etaf-manual-reader--base-pixels) 1.4))
                   :color (etaf-manual-reader--color env :heading))
             (list text)))

(defun etaf-manual-reader--label (env text)
  "Return small-caps-like secondary label TEXT."
  (etaf-node 'text
             (list :color (etaf-manual-reader--color env :muted)
                   :font-size (round (* (etaf-manual-reader--base-pixels) 0.85)))
             (list text)))

(defun etaf-manual-reader--mono (env text &optional props)
  "Return TEXT in the frame's fixed-pitch family with PROPS."
  (etaf-node 'text
             (append (list :font-family (etaf-manual-reader--mono-family)
                           :color (etaf-manual-reader--color env :ink))
                     props)
             (list text)))

(defun etaf-manual-reader--mono-family ()
  "Return the family of the frame's fixed-pitch font, or nil."
  (let ((family (face-attribute 'fixed-pitch :family nil t)))
    (and (stringp family) (not (string-empty-p family)) family)))

(defun etaf-manual-reader--base-pixels ()
  "Return the frame's default font size in CSS reference pixels."
  (let ((height (face-attribute 'default :height nil t)))
    (if (numberp height)
        (max 8 (round (/ (* height 4.0) 30.0)))
      16.0)))

;;;; Measurement

(defun etaf-manual-reader--viewport-columns (env)
  "Return ENV's frame width in character cells, or nil when unknown."
  (plist-get env :viewport))

(defun etaf-manual-reader--wide-p (env)
  "Return non-nil when ENV frames the two-column layout."
  (let ((columns (etaf-manual-reader--viewport-columns env)))
    (or (null columns)
        (>= columns etaf-manual-reader--wide-threshold))))

(defun etaf-manual-reader--compact-p (env)
  "Return non-nil when ENV asks for the compact chrome."
  (let ((columns (etaf-manual-reader--viewport-columns env)))
    (and columns (< columns etaf-manual-reader--compact-threshold))))

(defun etaf-manual-reader--measure (env)
  "Return the article measure in character cells for ENV."
  (let* ((columns (etaf-manual-reader--viewport-columns env))
         (sidebar (if (etaf-manual-reader--wide-p env)
                      etaf-manual-reader--sidebar-width
                    0))
         (available (if columns
                        (- columns sidebar 4)
                      etaf-manual-reader--measure-max)))
    (max etaf-manual-reader--measure-min
         (min etaf-manual-reader--measure-max available))))

;;;; Shared small pieces

(defun etaf-manual-reader--kbd-hint (env keys label)
  "Return a key hint cell: KEYS in a kbd chip, then LABEL."
  (etaf-node 'row
             (list :item-gap '(ch 1) :cross-align 'center)
             (list (etaf-node 'etaf-kbd (list :keys keys) nil)
                   (etaf-manual-reader--label env label))))

(defun etaf-manual-reader--state-line (env text &optional tone)
  "Return a one-line state TEXT tinted with semantic TONE."
  (etaf-node 'text
             (list :color (etaf-manual-reader--color env (or tone :muted)))
             (list text)))

(provide 'etaf-manual-reader-style)
;;; etaf-manual-reader-style.el ends here
