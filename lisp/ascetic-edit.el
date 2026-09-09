;;; ascetic-edit.el --- Surgical text manipulation -*- lexical-binding: t -*-

;; Copyright (C) 2026 Jacopo Costantini
;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; Package-Requires: ((emacs "30.0"))
;; License: GNU General Public License version 3 (or later)

;;; Commentary:

;; Vim's determinism without Vim: inner text objects, line moving,
;; surround.  Dependency-free; structure comes from `syntax-ppss',
;; the same engine the editor already uses for parens and strings.
;;
;; Mechanism only.  This file binds no global key -- see init.el.
;;
;; Not reimplemented here, because Emacs already has them:
;;   duplicate-dwim      line or region, rectangles included  (29)
;;   insert-pair  M-(    wrap N sexps from `insert-pair-alist'
;;   electric-pair-mode  wraps an active region on open paren
;;   delete-indentation  join, with argument for the line below

;;; Code:

;;; TEXT OBJECTS

(defun ascetic-edit--inner-sexp (start)
  "Inner bounds of the sexp opening at START, or nil if empty."
  (ignore-errors
    (save-excursion
      (goto-char start)
      (let ((beg (1+ (point))))
        (forward-sexp 1)
        (let ((end (1- (point))))
          (and (> end beg) (cons beg end)))))))

(defun ascetic-edit--bounds-for (type)
  "Inner bounds of TYPE at point: `symbol', `string' or `parens'.
Return (BEG . END), or nil."
  (pcase type
    ('symbol (or (bounds-of-thing-at-point 'symbol)
                 (bounds-of-thing-at-point 'word)))
    ('string (let ((s (syntax-ppss)))
               (and (nth 3 s) (ascetic-edit--inner-sexp (nth 8 s)))))
    ('parens (let ((s (syntax-ppss)))
               (and (nth 1 s) (ascetic-edit--inner-sexp (nth 1 s)))))))

(defun ascetic-edit--target ()
  "Bounds of the region, or of the symbol at point."
  (or (and (use-region-p) (cons (region-beginning) (region-end)))
      (ascetic-edit--bounds-for 'symbol)
      (user-error "Ascetic: no target")))

;;; SELECTIONS

(defun ascetic-edit--select (bounds what)
  "Make BOUNDS the region.  WHAT names the object for the error."
  (unless bounds (user-error "Ascetic: not inside %s" what))
  (goto-char (car bounds))
  (push-mark nil t t)
  (goto-char (cdr bounds)))

(defun ascetic-edit-inner-symbol ()
  "Select the symbol at point (vi: viw)."
  (interactive)
  (ascetic-edit--select (ascetic-edit--target) "a symbol"))

(defun ascetic-edit-inner-string ()
  "Select the string contents at point (vi: vi\")."
  (interactive)
  (ascetic-edit--select (ascetic-edit--bounds-for 'string) "a string"))

(defun ascetic-edit-inner-parens ()
  "Select the parenthesised contents at point (vi: vib)."
  (interactive)
  (ascetic-edit--select (ascetic-edit--bounds-for 'parens) "parentheses"))

;;; VERBS

(defun ascetic-edit-delete ()
  "Delete region or symbol at point, without touching the kill ring."
  (interactive)
  (let ((b (ascetic-edit--target)))
    (delete-region (car b) (cdr b))))

(defun ascetic-edit-surround (char)
  "Wrap region or symbol at point in CHAR.
Brackets close with their mate; anything else closes with itself.
For a region and a bracket, `electric-pair-mode' already does this."
  (interactive "cSurround with: ")
  (atomic-change-group
    (let* ((b (ascetic-edit--target))
           (close (or (alist-get char '((?\( . ?\)) (?\[ . ?\])
                                        (?\{ . ?\}) (?<  . ?>)))
                      char)))
      (save-excursion
        (goto-char (cdr b)) (insert-char close)
        (goto-char (car b)) (insert-char char))
      (deactivate-mark))))

;;; LINES

(defun ascetic-edit--move (n)
  "Move the line or region N lines down.  Negative N moves up."
  (atomic-change-group
    (let* ((region (use-region-p))
           (beg (save-excursion
                  (goto-char (if region (region-beginning) (point)))
                  (line-beginning-position)))
           (end (save-excursion
                  (goto-char (if region (region-end) (point)))
                  (if (and region (bolp) (> (point) beg))
                      (point)
                    (line-beginning-position 2))))
           (pt (- (point) beg))
           (mk (and region (- (mark) beg))))
      (when (if (< n 0) (= beg (point-min)) (= end (point-max)))
        (user-error "Ascetic: no room to move"))
      (let ((text (delete-and-extract-region beg end)))
        (forward-line n)
        (let ((home (point)))
          (insert text)
          (when region
            (push-mark (+ home mk) t t)
            (setq deactivate-mark nil))
          (goto-char (+ home pt)))))))

(defun ascetic-edit-move-up (&optional n)
  "Move the line or region up N lines."
  (interactive "p")
  (ascetic-edit--move (- (or n 1))))

(defun ascetic-edit-move-down (&optional n)
  "Move the line or region down N lines."
  (interactive "p")
  (ascetic-edit--move (or n 1)))

(defun ascetic-edit-duplicate-and-comment ()
  "Copy the line or region below, comment the original, land on the copy.
Line-wise always: a partial line is a whole line to `comment-region'."
  (interactive)
  (let* ((beg (save-excursion
                (goto-char (if (use-region-p) (region-beginning) (point)))
                (line-beginning-position)))
         (end (save-excursion
                (goto-char (if (use-region-p) (region-end) (point)))
                (line-end-position)))
         (text (buffer-substring beg end)))
    (goto-char end)
    (insert "\n" text)
    (save-excursion (comment-region beg end))
    (goto-char (- (point) (length text)))))

(defun ascetic-edit-open-below ()
  "Open an indented line below (vi: o)."
  (interactive)
  (end-of-line)
  (newline-and-indent))

(defun ascetic-edit-open-above ()
  "Open an indented line above (vi: O)."
  (interactive)
  (beginning-of-line)
  (newline)
  (forward-line -1)
  (indent-according-to-mode))

;;; MAPS
;; Policy lives in init.el.  These two are structure, not taste.

(defvar-keymap ascetic-edit-inner-map
  :doc "Inner text objects."
  "s" #'ascetic-edit-inner-symbol
  "q" #'ascetic-edit-inner-string
  "p" #'ascetic-edit-inner-parens)

(defvar-keymap ascetic-edit-move-repeat-map
  :doc "Keep moving without the modifier."
  :repeat t
  "<up>"   #'ascetic-edit-move-up
  "<down>" #'ascetic-edit-move-down)

(provide 'ascetic-edit)
;;; ascetic-edit.el ends here
