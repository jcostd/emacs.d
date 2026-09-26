;;; ascetic-read.el --- Completion as a stream, after Acme -*- lexical-binding: t -*-

;; Copyright (C) 2026 Jacopo Costantini

;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; Package-Requires: ((emacs "30.1"))

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Candidates stream below the prompt as overlay text: no window,
;; no cursor, no selection.  Only the echo area grows.
;;
;;   TAB        longest common prefix
;;   RET        the input as typed
;;   M-RET M-j  the top candidate
;;   M-1..M-9   candidate N, into the input
;;
;; Bare keys edit the input; Meta takes from a stream.  A total
;; shows flush right when some candidates are hidden.
;;
;; Ranked by history, then length, unless the table sorts.  Keeps
;; the `completing-read' contract, but never asks to confirm.
;; Extend through `ascetic-read-map'.
;;
;; Unhandled: `completing-read-multiple', annotations, groups.

;;; Code:

;;; STATE

(defgroup ascetic-read nil
  "Completion as a stream."
  :group 'minibuffer)

(defcustom ascetic-read-max-candidates 5
  "Candidates shown.  Nine have chords."
  :type 'natnum
  :group 'ascetic-read)

;; Minibuffer-local, killed by `minibuffer-mode' on entry: every read
;; starts clean, nested reads never meet.  Table and predicate are
;; Emacs's own `minibuffer-completion-*'.
(defvar-local ascetic-read--require-match nil
  "REQUIRE-MATCH of this read.")

(defvar-local ascetic-read--overlay nil
  "Overlay carrying the stream.")

(defvar-local ascetic-read--all nil
  "The whole stream, sorted.  The screen shows its head.")

(defvar-local ascetic-read--base 0
  "Length of the input prefix candidates leave alone.")

(defvar-local ascetic-read--history nil
  "Hash: history tail to rank, newest 0.")

(defvar-local ascetic-read--last-input nil
  "Input the stream was computed for.")

(defvar-local ascetic-read--history-base nil
  "Prefix `ascetic-read--history' is keyed under.")

;;; RANK

(defun ascetic-read--sort (completions)
  "Sort COMPLETIONS by history, then length, then text."
  (let ((h ascetic-read--history))
    (sort completions :in-place t
          :key (lambda (c)
                 (list (gethash c h most-positive-fixnum) (length c) c)))))

(defun ascetic-read--history-index (base)
  "Rank history entries by what follows BASE.
Candidates are tails; a tail also ranks its first directory."
  (unless (equal base ascetic-read--history-base)
    (let ((hv minibuffer-history-variable)
          (h (make-hash-table :test #'equal))
          (i 0))
      (when (and (symbolp hv) (boundp hv) (consp (symbol-value hv)))
        (dolist (e (symbol-value hv))
          (when (and (stringp e) (string-prefix-p base e))
            (let* ((k (substring e (length base)))
                   (p (string-search "/" k)))
              (unless (gethash k h) (puthash k i h))
              (when p
                (let ((d (substring k 0 (1+ p))))
                  (unless (gethash d h) (puthash d i h))))))
          (setq i (1+ i))))
      (setq ascetic-read--history h
            ascetic-read--history-base base))))

;;; DRAW

(defun ascetic-read--line (s)
  "Return S on one line: newlines as ^J, cut to the window."
  (truncate-string-to-width
   (string-replace "\n" (propertize "^J" 'face 'escape-glyph) s)
   (- (window-max-chars-per-line) 2) nil nil t))

(defun ascetic-read--count (total shown)
  "Return TOTAL flush right if SHOWN hides some, else nil.
A complete stream is its own count."
  (when (> total shown)
    (let ((n (number-to-string total)))
      (concat (propertize " " 'display `(space :align-to (- right ,(1+ (length n)))))
              (propertize n 'face 'shadow)))))

(defun ascetic-read--render (cands total)
  "Draw CANDS numbered below the input, TOTAL beside it."
  (let* ((i 0)
         (lines (mapconcat
                 (lambda (c)
                   (concat "\n"
                           (propertize (format "%d " (setq i (1+ i))) 'face 'shadow)
                           ;; hilit mutates: spare the table's string
                           (ascetic-read--line
                            (completion-lazy-hilit (copy-sequence c)))))
                 cands))
         (s (and cands
                 (concat " " (ascetic-read--count total (length cands)) lines))))
    ;; cursor before the stream
    (when s (put-text-property 0 1 'cursor t s))
    (overlay-put ascetic-read--overlay 'after-string s)))

;;; ENGINE

(defun ascetic-read--remote-p (path)
  "Non-nil if PATH is remote."
  (string-match-p "\\`/[^/|:]+:" (substitute-in-file-name path)))

(defun ascetic-read--compute (input md)
  "Return (CANDIDATES BASE) for INPUT under metadata MD.
CANDIDATES is the whole stream, sorted."
  (let* ((all (completion-all-completions
               input minibuffer-completion-table minibuffer-completion-predicate
               (length input) md))
         (tail (last all))
         (base (or (cdr tail) 0)))
    (when tail (setcdr tail nil))
    ;; internal API: drops ignored extensions, ./ and ../
    (when (eq (completion-metadata-get md 'category) 'file)
      (setq all (completion-pcm--filename-try-filter all)))
    (let ((sorter (completion-metadata-get md 'display-sort-function)))
      ;; history only if we sort
      (unless sorter
        (ascetic-read--history-index (substring input 0 base))
        (setq sorter #'ascetic-read--sort))
      (list (funcall sorter all) base))))

(defun ascetic-read--update (&optional block)
  "Recompute and redraw the stream.  BLOCK: typeahead cannot abort."
  ;; an error in `post-command-hook' unhooks us
  (with-demoted-errors "ascetic-read: %S"
    (let* ((non-essential t)
           (input (minibuffer-contents-no-properties))
           (md (completion-metadata input minibuffer-completion-table
                                    minibuffer-completion-predicate))
           ;; a throw inside TRAMP can wedge it
           (block (or block
                      (and (eq (completion-metadata-get md 'category) 'file)
                           (or (ascetic-read--remote-p input)
                               (ascetic-read--remote-p default-directory)))))
           (state (if block
                      (ascetic-read--compute input md)
                    (while-no-input (ascetic-read--compute input md)))))
      ;; t: aborted by typeahead, keep the old stream
      (pcase state
        (`(,all ,base)
         (setq ascetic-read--last-input input
               ascetic-read--all all
               ascetic-read--base base)
         (ascetic-read--render (take ascetic-read-max-candidates all)
                               (length all)))))))

(defun ascetic-read--sync (&optional block)
  "Recompute if the input moved.  BLOCK as in `ascetic-read--update'."
  (unless (equal (minibuffer-contents-no-properties) ascetic-read--last-input)
    (ascetic-read--update block)))

;;; EDIT

(defun ascetic-read--replace (beg text)
  "Replace the input from BEG with TEXT.
Bare, as in `completion--replace', unless properties are allowed."
  (delete-region beg (point-max))
  (insert (if minibuffer-allow-text-properties
              text
            (substring-no-properties text))))

(defun ascetic-read--insert-nth (n)
  "Insert candidate N."
  ;; act on what was typed, not on what is shown
  (ascetic-read--sync t)
  ;; numbered only on screen
  (if-let* ((c (and (< n ascetic-read-max-candidates)
                    (nth n ascetic-read--all))))
      (ascetic-read--replace (+ (minibuffer-prompt-end) ascetic-read--base) c)
    (minibuffer-message "No candidate %d" (1+ n))))

(defun ascetic-read--fix-case (input)
  "Respell INPUT as the table does, if only case differs.
As `completing-read' does: *SCRATCH* must find *scratch*."
  (when completion-ignore-case
    (let ((c (try-completion input minibuffer-completion-table
                             minibuffer-completion-predicate)))
      (when (and (stringp c) (not (equal c input))
                 (= (length c) (length input)))
        (ascetic-read--replace (minibuffer-prompt-end) c)))))

;;; COMMANDS

(defun ascetic-read-insert ()
  "Insert the candidate the key numbers: M-3, the third."
  (interactive)
  (let ((d (event-basic-type last-command-event)))
    ;; nth reads a negative index as 0
    (unless (and (characterp d) (<= ?1 d ?9))
      (user-error "Bind `ascetic-read-insert' to M-1..M-9"))
    (ascetic-read--insert-nth (- d ?1))))

(defun ascetic-read-exit ()
  "Exit with the input as typed.  Never ask to confirm."
  (interactive)
  (let ((input (minibuffer-contents-no-properties))
        (rm ascetic-read--require-match))
    (cond
     ;; empty: the caller owns the default
     ((string-empty-p input) (exit-minibuffer))
     ((test-completion input minibuffer-completion-table
                       minibuffer-completion-predicate)
      (ascetic-read--fix-case input)
      (exit-minibuffer))
     ;; 29: REQUIRE-MATCH may be a predicate
     ((if (functionp rm) (not (funcall rm input)) (eq rm t))
      (minibuffer-message "Match required"))
     (t (exit-minibuffer)))))

(defun ascetic-read-exit-first ()
  "Exit with the top candidate."
  (interactive)
  (ascetic-read--sync t)
  (if ascetic-read--all
      (progn (ascetic-read--insert-nth 0)
             (exit-minibuffer))         ; from the table: it matches
    (ascetic-read-exit)))

(defun ascetic-read-complete ()
  "Expand the input to the longest common prefix."
  (interactive)
  (let ((input (minibuffer-contents-no-properties))
        (beg (minibuffer-prompt-end)))
    (pcase (completion-try-completion
            input minibuffer-completion-table minibuffer-completion-predicate
            (- (point) beg))
      ('t (minibuffer-message "Sole completion"))
      (`(,text . ,pos)
       (unless (string= text input)
         (ascetic-read--replace beg text)
         (goto-char (+ beg pos))))
      (_ (minibuffer-message "No match")))))

(defvar-keymap ascetic-read-map
  :doc "Bare keys edit the input; Meta takes from a stream."
  :parent minibuffer-local-map
  "TAB"   #'ascetic-read-complete
  "M-RET" #'ascetic-read-exit-first
  "M-j"   #'ascetic-read-exit-first
  "C-n"   #'ignore                      ; no cursor to move
  "C-p"   #'ignore
  ;; every exit keeps the contract
  "<remap> <exit-minibuffer>"                  #'ascetic-read-exit
  ;; history is Meta too: M-n M-p
  "<remap> <previous-line-or-history-element>" #'ignore
  "<remap> <next-line-or-history-element>"     #'ignore)

;; all nine: the limit may grow
(dotimes (i 9)
  (keymap-set ascetic-read-map (format "M-%d" (1+ i))
              #'ascetic-read-insert))

;;; ENTRY

(defun ascetic-read--setup (table pred require-match)
  "Arm the minibuffer for TABLE, PRED and REQUIRE-MATCH."
  ;; local, as in `completing-read-default'
  (setq-local minibuffer-completion-table table
              minibuffer-completion-predicate pred
              ascetic-read--require-match require-match
              ;; 30: paint only what is shown
              completion-lazy-hilit t
              ;; advancing: pinned to point-max
              ascetic-read--overlay (make-overlay (point-max) (point-max) nil t t))
  ;; once per command, after its edits
  (add-hook 'post-command-hook #'ascetic-read--sync nil t)
  (ascetic-read--update))

(defun ascetic-read (prompt collection &optional predicate require-match
                                       initial-input hist def inherit-input-method)
  "Read a string with completion as a stream.
See `completing-read' for PROMPT, COLLECTION, PREDICATE, REQUIRE-MATCH,
INITIAL-INPUT, HIST, DEF and INHERIT-INPUT-METHOD."
  ;; one-shot: nested reads stay plain.  appended: after the caller's
  ;; own setup, where read-file-name sets its dir
  (let ((raw (minibuffer-with-setup-hook
                 (:append (lambda ()
                            (ascetic-read--setup
                             collection predicate require-match)))
               (read-from-minibuffer prompt initial-input ascetic-read-map
                                     nil hist def inherit-input-method))))
    ;; as in `completing-read-default'
    (if (and (string-empty-p raw) def)
        (if (consp def) (car def) def)
      raw)))

;;;###autoload
(define-minor-mode ascetic-read-mode
  "Toggle completion as a stream.

\\{ascetic-read-map}"
  :global t
  (if ascetic-read-mode
      (setq completing-read-function #'ascetic-read)
    (setq completing-read-function #'completing-read-default)))

(provide 'ascetic-read)
;;; ascetic-read.el ends here
