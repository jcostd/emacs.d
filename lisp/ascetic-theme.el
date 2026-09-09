;;; ascetic-theme.el --- Ascetic theme engine -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jacopo Costantini
;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; License: GNU General Public License version 3 (or later)

;;; Commentary:
;; Mechanism, not policy.  Themes supply ten colours; this supplies
;; the faces and the metrology.
;;
;; Structure lives in weight and slant.  Colour is spent only on
;; tokens the eye must hunt.
;;
;; Ladder  paper paper-1 paper-2 rule ink -- monotone toward ink in
;;         both polarities.  No name encodes a direction.
;; Signal  alarm figure literal caution mute -- ordered by urgency.
;;
;; Contrast figures live next to the colours they describe.  They were
;; measured with APCA 0.98G-4g; remeasure there if a colour moves.

;;; Code:

(defconst ascetic-theme-faces
  '(;; frame
    `(default                    ((t :background ,paper :foreground ,ink)))
    `(cursor                     ((t :background ,ink)))
    `(fringe                     ((t :background ,paper :foreground ,mute)))
    `(vertical-border            ((t :foreground ,rule)))
    `(window-divider             ((t :foreground ,rule)))
    `(window-divider-first-pixel ((t :foreground ,rule)))
    `(window-divider-last-pixel  ((t :foreground ,rule)))
    `(fill-column-indicator      ((t :foreground ,rule)))
    `(hl-line                    ((t :background ,paper-1)))
    `(highlight                  ((t :background ,paper-1)))
    `(region                     ((t :background ,paper-2 :extend t)))
    `(secondary-selection        ((t :background ,paper-1 :extend t)))
    `(trailing-whitespace        ((t :background ,paper-2)))
    `(shadow                     ((t :foreground ,mute)))
    `(link                       ((t :foreground ,figure :underline t)))
    `(link-visited               ((t :foreground ,figure :underline t)))
    `(line-number                ((t :foreground ,mute)))
    `(line-number-current-line   ((t :foreground ,ink :weight bold)))
    `(escape-glyph  ((t :foreground ,caution)))
    `(nobreak-space ((t :foreground ,caution :underline t)))
    `(homoglyph     ((t :foreground ,caution)))
    `(glyphless-char ((t :foreground ,mute)))

    ;; mode line, header, tabs
    `(mode-line ((t :background ,paper-1 :foreground ,ink
                    :box (:line-width -1 :color ,rule))))
    ;; ancillary text: recedes on purpose, below the body floor
    `(mode-line-inactive ((t :background ,paper-2 :foreground ,mute
                             :box (:line-width -1 :color ,rule))))
    `(mode-line-buffer-id ((t :weight bold)))
    `(minibuffer-depth-indicator ((t :foreground ,caution :weight bold)))
    `(header-line ((t :background ,paper-1 :foreground ,ink)))
    `(tab-bar     ((t :background ,paper-2 :foreground ,mute)))
    `(tab-bar-tab ((t :background ,paper-1 :foreground ,ink :weight bold
                      :box (:line-width -1 :color ,rule))))
    ;; a tab label is a control, not prose: mute is the wrong role
    `(tab-bar-tab-inactive ((t :background ,paper-2 :foreground ,ink
                               :box (:line-width -1 :color ,rule))))
    `(tab-bar-tab-group-current  ((t :foreground ,literal :weight bold)))
    `(tab-bar-tab-group-inactive ((t :foreground ,mute :slant italic)))
    `(tab-bar-tab-ungrouped      ((t :foreground ,mute)))

    ;; which-key is built in on 30; its defaults are outside the palette
    `(which-key-key-face                 ((t :foreground ,literal :weight bold)))
    `(which-key-command-description-face ((t :foreground ,ink)))
    `(which-key-group-description-face   ((t :foreground ,figure :weight bold)))
    `(which-key-separator-face           ((t :foreground ,mute)))

    ;; search
    `(isearch             ((t :background ,literal :foreground ,paper :weight bold)))
    `(isearch-fail        ((t :background ,alarm :foreground ,paper)))
    `(lazy-highlight      ((t :background ,paper-1 :foreground ,literal :weight bold)))
    `(match               ((t :background ,paper-1 :foreground ,literal :weight bold)))
    `(show-paren-match    ((t :background ,paper-1 :weight bold)))
    `(show-paren-mismatch ((t :background ,alarm :foreground ,paper)))

    ;; minibuffer, completion
    `(minibuffer-prompt            ((t :foreground ,literal :weight bold)))
    `(eshell-prompt                ((t :foreground ,literal :weight bold)))
    `(comint-highlight-prompt      ((t :foreground ,literal :weight bold)))
    `(completions-common-part      ((t :foreground ,literal)))
    `(completions-first-difference ((t :foreground ,alarm :weight bold)))
    `(completions-annotations      ((t :foreground ,mute :slant italic)))
    `(icomplete-first-match        ((t :weight bold)))
    `(icomplete-selected-match     ((t :background ,paper-1 :foreground ,literal :weight bold)))
    `(icomplete-section            ((t :foreground ,mute :slant italic)))
    `(completion-preview           ((t :foreground ,mute :slant italic)))
    `(completion-preview-common    ((t :foreground ,mute :weight bold)))
    `(completion-preview-exact     ((t :foreground ,literal :slant italic)))

    ;; syntax -- structure is typography, never hue
    `(font-lock-keyword-face       ((t :weight bold)))
    `(font-lock-type-face          ((t :weight bold)))
    `(font-lock-function-name-face ((t :weight bold)))
    `(font-lock-builtin-face       ((t :slant italic)))
    `(font-lock-preprocessor-face  ((t :slant italic)))
    `(font-lock-negation-char-face ((t :weight bold)))
    `(font-lock-string-face        ((t :foreground ,literal)))
    `(font-lock-constant-face      ((t :foreground ,figure)))
    `(font-lock-number-face        ((t :foreground ,figure)))
    `(font-lock-warning-face       ((t :foreground ,caution :weight bold)))
    `(font-lock-comment-face       ((t :foreground ,mute :slant italic)))
    `(font-lock-comment-delimiter-face ((t :foreground ,mute :slant italic)))
    `(font-lock-doc-face           ((t :foreground ,mute :slant italic)))
    `(font-lock-doc-markup-face    ((t :foreground ,mute :slant italic)))
    ;; Emacs 30 tree-sitter: call sites are not landmarks
    `(font-lock-function-call-face ((t :weight normal)))
    ;; escapes must stay inside the literal, marked by weight
    `(font-lock-escape-face        ((t :foreground ,literal :weight bold)))

    ;; diagnostics
    `(error   ((t :foreground ,alarm   :weight bold)))
    `(warning ((t :foreground ,caution :weight bold)))
    `(success ((t :foreground ,literal)))
    ;; dark band is narrow: the wave carries what Lc cannot
    `(flymake-error   ((t :underline (:style wave :color ,alarm))))
    `(flymake-warning ((t :underline (:style wave :color ,caution))))
    `(flymake-note    ((t :underline (:style wave :color ,figure))))
    `(eglot-mode-line ((t :weight bold)))
    `(compilation-error   ((t :foreground ,alarm   :weight bold)))
    `(compilation-warning ((t :foreground ,caution :weight bold)))
    `(compilation-info    ((t :foreground ,figure  :weight bold)))
    `(compilation-line-number    ((t :foreground ,mute)))
    `(compilation-column-number  ((t :foreground ,mute)))
    `(compilation-mode-line-fail ((t :foreground ,alarm :weight bold)))
    `(compilation-mode-line-run  ((t :foreground ,caution)))
    `(compilation-mode-line-exit ((t :foreground ,literal)))

    ;; dired, diff
    `(dired-directory  ((t :weight bold)))
    `(dired-symlink    ((t :slant italic)))
    `(dired-ignored    ((t :foreground ,mute)))
    `(diff-header      ((t :weight bold)))
    `(diff-file-header ((t :weight bold)))
    `(diff-added       ((t :foreground ,literal)))
    `(diff-removed     ((t :foreground ,alarm)))
    `(diff-refine-added   ((t :foreground ,literal :weight bold)))
    `(diff-refine-removed ((t :foreground ,alarm   :weight bold)))
    `(diff-indicator-added   ((t :foreground ,literal :weight bold)))
    `(diff-indicator-removed ((t :foreground ,alarm   :weight bold)))
    ;; two-way only: split is horizontal, A/B is all we ever see
    `(ediff-current-diff-A ((t :background ,paper-2)))
    `(ediff-current-diff-B ((t :background ,paper-2)))
    `(ediff-fine-diff-A    ((t :background ,paper-1 :foreground ,alarm   :weight bold)))
    `(ediff-fine-diff-B    ((t :background ,paper-1 :foreground ,literal :weight bold)))
    `(ediff-even-diff-A    ((t :background ,paper-1)))
    `(ediff-even-diff-B    ((t :background ,paper-1)))
    `(ediff-odd-diff-A     ((t :background ,paper-1)))
    `(ediff-odd-diff-B     ((t :background ,paper-1)))

    ;; web-mode ships its own palette; overrule it
    `(web-mode-html-tag-face         ((t :foreground ,ink :weight bold)))
    `(web-mode-html-tag-bracket-face ((t :foreground ,mute)))
    `(web-mode-html-attr-name-face   ((t :foreground ,ink)))
    `(web-mode-html-attr-value-face  ((t :foreground ,literal)))
    `(web-mode-jsx-tag-face          ((t :foreground ,ink :weight bold)))
    `(web-mode-jsx-attr-name-face    ((t :foreground ,ink)))
    `(web-mode-block-delimiter-face  ((t :foreground ,literal :weight bold)))
    `(web-mode-block-control-face    ((t :foreground ,ink :weight bold)))
    `(web-mode-variable-name-face    ((t :foreground ,ink)))
    `(web-mode-symbol-face           ((t :foreground ,figure)))
    `(web-mode-part-face             ((t :background unspecified)))
    `(web-mode-block-face            ((t :background unspecified)))
    `(web-mode-current-element-highlight-face ((t :background ,paper-1))))
  "Face specs.  Palette symbols are bound by `ascetic-theme-define'.")

(defmacro ascetic-theme-define (theme &rest palette)
  "Apply `ascetic-theme-faces' to THEME under PALETTE bindings.
PALETTE is a list of (SYM HEX).  Byte-compile to catch a colour
that is declared and unused, or used and undeclared."
  (declare (indent 1))
  `(let ,palette
     (custom-theme-set-faces ',theme ,@ascetic-theme-faces)))

(provide 'ascetic-theme)
;;; ascetic-theme.el ends here
