;;; ascetic-read.el --- Plan 9 inspired text completion UI -*- lexical-binding: t -*-

;; Copyright (C) 2026 Jacopo Costantini

;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; Package-Requires: ((emacs "30.0"))

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Stream-based completion UI inspired by Plan 9 and Acme.
;; Candidates are rendered as ephemeral overlay text below the prompt,
;; never in a separate window.  The layout is immutable: no window
;; splits, no geometry changes, no visual disruption.
;;
;; INTERACTION MODEL
;; Input drives selection.  There is no candidate navigation.
;; Type to filter.  Use numeric chords to materialize:
;;   M-1  insert first candidate    M-2  insert second    ...up to M-9
;;   M-RET / M-j  insert and exit with top candidate
;;   TAB          expand to longest common prefix
;;   RET          commit current input as-is
;;
;; SORTING
;; Candidates are sorted by recency (O(1) hash lookup against minibuffer
;; history), then by length.  The sort respects `display-sort-function'
;; from completion metadata when provided by the collection.
;;
;; REMOTE PATHS
;; On TRAMP paths, candidate computation runs synchronously to avoid
;; timing issues with remote filesystems.  On local paths, `while-no-input'
;; ensures the UI stays responsive during large collections.
;;
;; ECOSYSTEM COMPATIBILITY
;; ascetic-read hooks into `completing-read-function' — the standard
;; extension point.  Consult works as a backend without modification.
;; Packages that read `completion--string' text properties from a
;; *Completions* buffer (Embark, Marginalia) are not supported by design:
;; candidates exist only as overlay display text, not as buffer objects.
;; Extensions may use `ascetic-read-setup-hook' to bind local keys or
;; modify minibuffer state without touching the global setup hooks.
;;
;; KNOWN LIMITATIONS
;; - `completing-read-multiple' falls back to default Emacs UI.
;; - `completion-pcm--filename-try-filter' is an internal Emacs API
;;   used for file extension filtering; may change in future versions.
;; - Candidates containing embedded newlines render without special handling.

;;; Code:

(defgroup ascetic-read nil
  "Plan 9 inspired completion engine."
  :group 'minibuffer)

(defcustom ascetic-max-candidates 5
  "Maximum number of candidates to display."
  :type 'integer
  :group 'ascetic-read)

(defvar ascetic-input-filter-function #'identity
  "Transform minibuffer input before candidate computation.
Set to a custom function to intercept or rewrite input.")

(defvar ascetic-read-setup-hook nil
  "Hook run after ascetic-read minibuffer setup is complete.
Useful for third-party extensions to bind local keys or modify state
without polluting the global `minibuffer-setup-hook'.")

;; Note: The following variables are dynamically bound in `ascetic-completing-read'.
;; This is robust for standard usage, but be mindful of edge cases in deeply
;; nested recursive minibuffer sessions.
(defvar ascetic-read--collection nil
  "Active collection.")

(defvar ascetic-read--predicate nil
  "Active predicate.")

(defvar ascetic-read--require-match nil
  "Strict match flag.")

(defvar ascetic-read--overlay nil
  "Rendering overlay.")

(defvar ascetic-read--current-candidates nil
  "Displayed candidates.")

(defvar ascetic-read--current-base-size 0
  "Candidate base size.")

(defvar ascetic-read--history-hash nil
  "O(1) history index.")

(defvar-local ascetic-read--last-input nil
  "Input the overlay was last computed for.")

(defvar-local ascetic-read--history-base nil
  "Prefix `ascetic-read--history-hash' is keyed under.")

(defun ascetic-read--remote-p (path)
  "Return t if PATH is a remote TRAMP path."
  (string-match-p "\\`/[^/|:]+:" (substitute-in-file-name path)))

(defun ascetic-read--smart-sort (completions)
  "Sort COMPLETIONS by history rank, then length, then text."
  (let ((h ascetic-read--history-hash))
    (sort completions :in-place t
          :key (lambda (c)
                 (list (if h (gethash c h most-positive-fixnum) 0)
                       (length c) c)))))

(defun ascetic-read--update-completions ()
  "Compute completions synchronously and render overlay."
  (when ascetic-read--overlay
    ;; Move overlay strictly to the end to prevent cursor trapping
    (move-overlay ascetic-read--overlay (point-max) (point-max) (current-buffer))
    (let* ((raw-content (minibuffer-contents-no-properties))
           (content (funcall ascetic-input-filter-function raw-content)))
      (let* ((metadata (completion-metadata content ascetic-read--collection ascetic-read--predicate))
             (category (completion-metadata-get metadata 'category))
             (is-remote (and (eq category 'file)
                             (or (ascetic-read--remote-p content)
                                 (ascetic-read--remote-p default-directory))))
             (compute-engine
              (lambda ()
		(let ((non-essential t)
                      (gc-cons-threshold (* 64 1024 1024)))
                  (let* ((completions (completion-all-completions
				       content ascetic-read--collection ascetic-read--predicate (length content)))
			 (last-cell (last completions))
			 (base-size (if (and last-cell (numberp (cdr last-cell)))
					(prog1 (cdr last-cell) (setcdr last-cell nil))
				      0))
                         (_ (ascetic-read--history-index (substring content 0 base-size)))
			 ;; Note: Internal Emacs API `completion-pcm--filename-try-filter'.
			 ;; Subject to change, but highly optimized for file ignoring.
			 (filtered (if (and completions (eq category 'file))
				       (completion-pcm--filename-try-filter completions)
                                     completions))
			 (sort-fn (or (completion-metadata-get metadata 'display-sort-function)
				      #'ascetic-read--smart-sort))
			 (lst (when filtered
				(take ascetic-max-candidates (funcall sort-fn filtered)))))
                    (cons lst base-size)))))
             (state (if is-remote
                        (funcall compute-engine)
                      (while-no-input (funcall compute-engine)))))
        (when (consp state)
          (setq ascetic-read--last-input raw-content)
          (let ((lst (car state))
                (base-size (cdr state)))
	    (setq ascetic-read--current-candidates lst)
	    (setq ascetic-read--current-base-size base-size)
	    (if lst
                (let ((text (concat " \n  " (mapconcat #'completion-lazy-hilit lst "\n  "))))
                  ;; Anchor the cursor exactly on the first space of the overlay.
                  ;; Since updates are now synchronous, this guarantees zero visual flicker,
                  ;; though behavior with variable-pitch fonts/scaling should be monitored.
                  (put-text-property 0 1 'cursor t text)
                  (overlay-put ascetic-read--overlay 'after-string text))
	      (overlay-put ascetic-read--overlay 'after-string ""))))))))

(defun ascetic-read--on-change ()
  "Refresh the overlay if the last command moved the input."
  (unless (equal (minibuffer-contents-no-properties) ascetic-read--last-input)
    (ascetic-read--update-completions)))

(defun ascetic-read--history-index (base)
  "Key the history index by what follows BASE in each entry.
File history holds whole paths; candidates are only their tails."
  (unless (equal base ascetic-read--history-base)
    (let ((hv minibuffer-history-variable)
          (h (make-hash-table :test #'equal))
          (i 0))
      (when (and (symbolp hv) (boundp hv) (consp (symbol-value hv)))
        (dolist (e (symbol-value hv))
          (when (and (stringp e) (string-prefix-p base e))
            (let ((k (substring e (length base))))
              (unless (gethash k h) (puthash k i h))))
          (setq i (1+ i))))
      (setq ascetic-read--history-hash h
            ascetic-read--history-base base))))

(defun ascetic-read-refresh ()
  "Force a synchronous refresh of the completion overlay."
  (interactive)
  (when (and ascetic-read--overlay (minibufferp))
    (ascetic-read--update-completions)))

(defun ascetic-read--insert-nth (n)
  "Materialize candidate N into the prompt."
  (let ((candidate (nth n ascetic-read--current-candidates)))
    (if candidate
        (progn
          (delete-region (+ (minibuffer-prompt-end) ascetic-read--current-base-size) (point-max))
          (insert candidate))
      (minibuffer-message "No candidate %d" (1+ n)))))

(defun ascetic-read--insert-by-chord ()
  "Extract digit from key and materialize candidate."
  (interactive)
  (let ((idx (- (event-basic-type last-command-event) ?1)))
    (ascetic-read--insert-nth idx)))

(defun ascetic-read--submit-raw ()
  "Commit prompt state, bypassing confirmation."
  (interactive)
  (let ((input (minibuffer-contents-no-properties)))
    (cond
     ;; null input always exits: the caller owns the default
     ((string-empty-p input) (exit-minibuffer))
     ((eq ascetic-read--require-match t)
      (if (test-completion input ascetic-read--collection ascetic-read--predicate)
          (exit-minibuffer)
        (minibuffer-message "Strict match required")))
     (t (exit-minibuffer)))))

(defun ascetic-read--submit-first ()
  "Commit the top candidate immediately."
  (interactive)
  (if ascetic-read--current-candidates
      (let ((candidate (car ascetic-read--current-candidates)))
        (delete-region (+ (minibuffer-prompt-end) ascetic-read--current-base-size) (point-max))
        (insert candidate)
        ;; Candidate sourced from `completion-all-completions' inherently
        ;; passes `test-completion'. Safe to bypass manual validation and exit.
        (exit-minibuffer))
    (ascetic-read--submit-raw)))

(defun ascetic-read--expand-lcp ()
  "Expand input to longest common prefix."
  (interactive)
  (let* ((input (minibuffer-contents-no-properties))
         (start-pos (minibuffer-prompt-end))
         (try (completion-try-completion
               input ascetic-read--collection ascetic-read--predicate (- (point) start-pos))))
    (cond ((eq try t)
           (minibuffer-message "Sole completion"))
          ((consp try)
           (let ((new-text (car try))
                 (new-pos (cdr try)))
             (unless (string= input new-text)
               (delete-region start-pos (point-max))
               (insert new-text)
               (goto-char (+ start-pos new-pos)))))
          (t
           (minibuffer-message "No expansion possible")))))

(defvar-keymap ascetic-minibuffer-map
  :doc "Keymap mapping structural intent over visual navigation."
  :parent minibuffer-local-map
  "C-n"   #'ignore
  "C-p"   #'ignore
  "TAB"   #'ascetic-read--expand-lcp
  "RET"   #'ascetic-read--submit-raw
  "M-RET" #'ascetic-read--submit-first
  "M-j"   #'ascetic-read--submit-first)

;; all nine: `ascetic-max-candidates' may grow at runtime
(dotimes (i 9)
  (keymap-set ascetic-minibuffer-map (format "M-%d" (1+ i))
              #'ascetic-read--insert-by-chord))

(defun ascetic-read--minibuffer-setup ()
  "Initialize session context."
  (make-local-variable 'ascetic-read--current-candidates)
  (make-local-variable 'ascetic-read--current-base-size)
  (make-local-variable 'ascetic-read--history-hash)
  ;; 30: styles defer their faces; only the shown few get painted
  (setq-local completion-lazy-hilit t
              ascetic-read--overlay (make-overlay (point-max) (point-max))
              ascetic-read--history-base nil
              ascetic-read--last-input nil)
  ;; once per command, after all its edits; local, dies with the session
  (add-hook 'post-command-hook #'ascetic-read--on-change nil t)
  (ascetic-read--update-completions)
  (run-hooks 'ascetic-read-setup-hook))

(defun ascetic-completing-read (prompt collection &optional predicate require-match
                                       initial-input hist def inherit-input-method)
  "Entry point for ascetic completion.
PROMPT is displayed to the user.  Candidates are drawn from COLLECTION
and optionally filtered by PREDICATE.  REQUIRE-MATCH enforces a valid
match.  INITIAL-INPUT, HIST, DEF and INHERIT-INPUT-METHOD have their
standard `completing-read' meanings."
  (let ((ascetic-read--collection collection)
        (ascetic-read--predicate predicate)
        (ascetic-read--require-match require-match)
        (minibuffer-completion-table collection)
        (minibuffer-completion-predicate predicate))
    ;; one-shot: a nested read-string stays plain
    (let ((raw (minibuffer-with-setup-hook #'ascetic-read--minibuffer-setup
                 (read-from-minibuffer prompt initial-input ascetic-minibuffer-map
                                       nil hist def inherit-input-method))))
      (cond ((not (string-empty-p raw)) raw)
            ((consp def) (car def))
            ((stringp def) def)
            (t raw)))))

;;;###autoload
(define-minor-mode ascetic-read-mode
  "Toggle Plan 9 inspired completion UI."
  :global t
  (if ascetic-read-mode
      (setq completing-read-function #'ascetic-completing-read)
    (setq completing-read-function #'completing-read-default)))

(provide 'ascetic-read)
;;; ascetic-read.el ends here
