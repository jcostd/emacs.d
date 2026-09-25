;;; ascetic-edit.el --- Surgical text manipulation -*- lexical-binding: t -*-

;; Copyright (C) 2026 Jacopo Costantini
;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; Package-Requires: ((emacs "30.0"))
;; License: GNU General Public License version 3 (or later)

;;; Commentary:

;; Vim's determinism without Vim: text objects, syntactic expansion,
;; surround, line surgery, numbers.  Dependency-free; structure comes
;; from `syntax-ppss', the engine Emacs already runs for parens and
;; strings.
;;
;; Mechanism only.  This file binds no global key -- see init.el.
;;
;; Already in Emacs, so absent here:
;;   duplicate-dwim      line, region in place, rectangle      (29)
;;                       30: *-final-position lands on the copy
;;   insert-pair  M-(    wrap N sexps from `insert-pair-alist'
;;   electric-pair-mode  wraps an active region on open paren
;;   delete-indentation  M-^  join; argument takes the line below
;;   back-to-indentation M-m  first non-blank; C-a stays column 0
;;   comment-line        C-x C-;  line or region
;;   cycle-spacing       M-SPC  squash, one, none              (29)
;;   zap-up-to-char      M-Z  vi's t{char}
;;   undo-redo           redo without a tree                   (28)
;;   mark-defun          C-M-h  the level above every level here
;;   rectangle-mark-mode C-x SPC  column edits, instead of cursors
;;
;; Renounced on purpose:
;;   change (vi: ci")    an inner object plus `delete-selection-mode'
;;   shrink selection    would need session state; C-x C-x undoes it
;;   avy, easymotion     isearch is already incremental

;;; Code:

;;; BOUNDS

(defun ascetic-edit--sexp-bounds (start &optional outer)
  "Bounds of the sexp opening at START.  OUTER keeps the delimiters.
Inner bounds are nil when the sexp is empty; outer bounds never are."
  (ignore-errors
    (save-excursion
      (goto-char start)
      (let ((beg (point)))
        (forward-sexp 1)
        (let ((end (point)))
          (if outer
              (cons beg end)
            (and (> (1- end) (1+ beg)) (cons (1+ beg) (1- end)))))))))

(defun ascetic-edit--bounds (type &optional outer)
  "Bounds of TYPE at point: `symbol', `string' or `parens'.
OUTER includes the delimiters.  Return (BEG . END), or nil."
  (pcase type
    ('symbol (bounds-of-thing-at-point 'symbol))
    ('string (let ((s (syntax-ppss)))
               (and (nth 3 s) (ascetic-edit--sexp-bounds (nth 8 s) outer))))
    ('parens (let ((s (syntax-ppss)))
               (and (nth 1 s) (ascetic-edit--sexp-bounds (nth 1 s) outer))))))

(defun ascetic-edit--target ()
  "Bounds of the region, else of the symbol at point."
  (or (and (use-region-p) (cons (region-beginning) (region-end)))
      (ascetic-edit--bounds 'symbol)
      (user-error "Ascetic: no target")))

(defun ascetic-edit--pair ()
  "Outer bounds of the innermost string or bracket pair at point.
Single-char delimiters only."
  (or (ascetic-edit--bounds 'string t)
      (ascetic-edit--bounds 'parens t)
      (user-error "Ascetic: no pair")))

(defun ascetic-edit--select (bounds what)
  "Make BOUNDS the region.  WHAT names the object for the error."
  (unless bounds (user-error "Ascetic: no %s" what))
  (goto-char (car bounds))
  (push-mark nil t t)
  (goto-char (cdr bounds)))

;;; OBJECTS

(defmacro ascetic-edit--defobject (name type outer doc)
  "Define ascetic-edit-NAME, selecting TYPE at point.
OUTER keeps the delimiters.  DOC is the docstring."
  (declare (indent 3) (doc-string 4))
  `(defun ,(intern (concat "ascetic-edit-" name)) ()
     ,doc
     (interactive)
     (ascetic-edit--select (ascetic-edit--bounds ',type ,outer)
                           ,(symbol-name type))))

(ascetic-edit--defobject "inner-symbol" symbol nil
  "Select the symbol at point (vi: viw).")

(ascetic-edit--defobject "inner-string" string nil
  "Select the string contents at point (vi: vi\").")

(ascetic-edit--defobject "outer-string" string t
  "Select the string with its quotes (vi: va\").")

(ascetic-edit--defobject "inner-parens" parens nil
  "Select the bracketed contents at point (vi: vib).")

(ascetic-edit--defobject "outer-parens" parens t
  "Select the brackets and their contents (vi: vab).")

;;; LEVELS

(defun ascetic-edit--levels ()
  "Bounds enclosing point, innermost first, inner before outer."
  (let* ((s (syntax-ppss))
         (open (nth 1 s))
         (lv (and (nth 3 s)
                  (list (ascetic-edit--sexp-bounds (nth 8 s))
                        (ascetic-edit--sexp-bounds (nth 8 s) t)))))
    (while open
      (setq lv (nconc lv (list (ascetic-edit--sexp-bounds open)
                               (ascetic-edit--sexp-bounds open t)))
            open (nth 1 (syntax-ppss open))))
    (delq nil lv)))

(defun ascetic-edit-expand ()
  "Grow the region to the next enclosing syntactic level."
  (interactive)
  (let ((beg (if (use-region-p) (region-beginning) (point)))
        (end (if (use-region-p) (region-end) (point)))
        (lv  (cons (ascetic-edit--bounds 'symbol) (ascetic-edit--levels)))
        (hit nil))
    (while (and lv (not hit))
      (let ((b (pop lv)))
        ;; wider on at least one side, or the region never moves
        (when (and b (<= (car b) beg) (>= (cdr b) end)
                   (or (< (car b) beg) (> (cdr b) end)))
          (setq hit b))))
    (ascetic-edit--select hit "wider level")))

;;; VERBS

(defun ascetic-edit--close (char)
  "Closing mate of CHAR.  Unpaired chars close with themselves."
  (or (alist-get char '((?\( . ?\)) (?\[ . ?\]) (?\{ . ?\}) (?< . ?>)))
      char))

(defun ascetic-edit-delete ()
  "Delete region or symbol at point.  The kill ring stays clean."
  (interactive)
  (let ((b (ascetic-edit--target)))
    (delete-region (car b) (cdr b))))

(defun ascetic-edit-surround (char)
  "Wrap region or symbol at point in CHAR (vi: ys).
For a region and a bracket, `electric-pair-mode' already does this."
  (interactive "cSurround with: ")
  (let ((b (ascetic-edit--target))
        (close (ascetic-edit--close char)))
    (atomic-change-group
      (save-excursion
        (goto-char (cdr b)) (insert-char close)
        (goto-char (car b)) (insert-char char))
      (deactivate-mark))))

(defun ascetic-edit-unsurround ()
  "Drop the innermost delimiters around point (vi: ds)."
  (interactive)
  (let ((b (ascetic-edit--pair)))
    (atomic-change-group
      (save-excursion
        (goto-char (1- (cdr b))) (delete-char 1)
        (goto-char (car b))      (delete-char 1)))))

(defun ascetic-edit-resurround (char)
  "Replace the innermost delimiters with CHAR (vi: cs)."
  (interactive "cSurround with: ")
  (let ((b (ascetic-edit--pair))
        (close (ascetic-edit--close char)))
    (atomic-change-group
      (save-excursion
        (goto-char (1- (cdr b))) (delete-char 1) (insert-char close)
        (goto-char (car b))      (delete-char 1) (insert-char char)))))

;;; LINES

(defun ascetic-edit--move (n)
  "Move the line or region N lines down.  Negative N moves up."
  (atomic-change-group
    ;; a last line with no newline glues onto its neighbour
    (save-excursion
      (goto-char (point-max))
      (unless (bolp) (insert "\n")))
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
Point keeps its line offset and its column: the copy is ready to edit.
Line-wise always: a partial line is a whole line to `comment-region'."
  (interactive)
  (let* ((col (current-column))
	 (beg (save-excursion
                (goto-char (if (use-region-p) (region-beginning) (point)))
                (line-beginning-position)))
         (end (save-excursion
                (goto-char (if (use-region-p) (region-end) (point)))
                ;; as in --move: a region ending at bol leaves that line
                (when (and (use-region-p) (bolp) (> (point) beg))
                  (backward-char))
                (line-end-position)))
	 (n (count-lines beg end))
         ;; point's line inside the block; past it counts as the last
         (off (count-lines beg (save-excursion
                                 (goto-char (min (point) end))
                                 (line-beginning-position))))
         (text (buffer-substring beg end)))
    (atomic-change-group
      (save-excursion (goto-char end) (insert "\n" text))
      (save-excursion (comment-region beg end))
      (deactivate-mark)
      (goto-char beg)
      (forward-line (+ n off))
      (move-to-column col))))

(defun ascetic-edit-open-below ()
  "Open an indented line below (vi: o)."
  (interactive)
  (end-of-line)
  (newline-and-indent))

(defun ascetic-edit-open-above ()
  "Open an indented line above (vi: O)."
  (interactive)
  (beginning-of-line)
  (open-line 1)
  (indent-according-to-mode))

;;; NUMBERS

(defun ascetic-edit--number-here ()
  "Bounds of the integer under point, or nil.
A leading minus counts, unless it follows a word: foo-1 is a name."
  (save-excursion
    (skip-chars-backward "0-9")
    (and (looking-at "[0-9]+")
         (let ((end (match-end 0)))
           (when (and (eq (char-before) ?-)
                      (not (memq (char-syntax (or (char-before (1- (point))) ?\s))
                                 '(?w ?_))))
             (backward-char))
           (cons (point) end)))))

(defun ascetic-edit--number-bounds ()
  "Bounds of the integer at point, else of the next one on the line."
  (or (save-excursion
        (or (ascetic-edit--number-here)
            (progn (skip-chars-forward "^0-9" (line-end-position))
                   (ascetic-edit--number-here))))
      (user-error "Ascetic: no number")))

(defun ascetic-edit--number-add (n)
  "Add N to the integer at point."
  (let* ((b (ascetic-edit--number-bounds))
         (v (+ n (string-to-number (buffer-substring (car b) (cdr b))))))
    (atomic-change-group
      (delete-region (car b) (cdr b))
      (goto-char (car b))
      (insert (number-to-string v)))))

(defun ascetic-edit-number-increase (&optional n)
  "Add N to the integer at point (vi: C-a)."
  (interactive "p")
  (ascetic-edit--number-add (or n 1)))

(defun ascetic-edit-number-decrease (&optional n)
  "Subtract N from the integer at point (vi: C-x)."
  (interactive "p")
  (ascetic-edit--number-add (- (or n 1))))

;;; MAPS
;; Policy lives in init.el.  These are structure, not taste.

(defvar-keymap ascetic-edit-inner-map
  :doc "Text objects.  Lower case inner, upper case around."
  "s" #'ascetic-edit-inner-symbol
  "q" #'ascetic-edit-inner-string
  "Q" #'ascetic-edit-outer-string
  "p" #'ascetic-edit-inner-parens
  "P" #'ascetic-edit-outer-parens)

(defvar-keymap ascetic-edit-move-repeat-map
  :doc "Keep moving without the modifier."
  :repeat t
  "<up>"   #'ascetic-edit-move-up
  "<down>" #'ascetic-edit-move-down)

;; No repeat map for `ascetic-edit-expand': a bare letter would eat
;; the letter itself for `repeat-exit-timeout' seconds.

(defvar-keymap ascetic-edit-number-repeat-map
  :doc "Keep adjusting without the modifier."
  :repeat t
  "+" #'ascetic-edit-number-increase
  "-" #'ascetic-edit-number-decrease)

(provide 'ascetic-edit)
;;; ascetic-edit.el ends here
