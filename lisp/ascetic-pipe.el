;;; ascetic-pipe.el --- Sam's pipes on the minibuffer -*- lexical-binding: t -*-

;; Copyright (C) 2026 Jacopo Costantini
;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; Package-Requires: ((emacs "30.1"))
;; License: GNU General Public License version 3 (or later)

;;; Commentary:

;; Sam's I/O commands on the minibuffer.  Dot is the completion
;; set, asked of Emacs, not of the UI: any `completing-read' will do.
;;
;;           reads    writes
;;   >  CMD  dot      *Pipe*                      (sam: >)
;;   |  CMD  dot      point, where you came from  (sam: |)
;;   <  CMD  nothing  the input                   (sam: <)
;;
;; Empty CMD: > shows dot in its native view, | inserts it.
;; C-u: CMD is a Lisp function, called on each line.  < has no
;; Lisp form: dot is not its input.
;;
;; > and | quit the minibuffer and act where it was called.
;; Commands run to the end: C-g stops them, M-& is for jobs.
;; Commands run where the candidates live.  Order is sort's job,
;; arguments xargs's.  In buffers Emacs is sam already: M-|,
;; C-u M-|, C-u M-!.

;;; Code:

(defconst ascetic-pipe--symbol-types
  '(command function variable face symbol-help)
  "Types whose lines Lisp receives as symbols.")

;;; STREAM

(defun ascetic-pipe--stream ()
  "Return (DIR TYPE LINES): this minibuffer's completion set.
LINES live in DIR; TYPE is the table's category."
  (let* ((input (minibuffer-contents-no-properties))
         (table minibuffer-completion-table)
         (pred minibuffer-completion-predicate)
         (md (completion-metadata input table pred))
         (type (completion-metadata-get md 'category))
         (all (and table (completion-all-completions
                          input table pred (length input) md)))
         (tail (last all))
         (base (or (cdr tail) 0)))
    (when tail (setcdr tail nil))
    ;; internal API: drops ignored extensions, ./ and ../
    (when (eq type 'file)
      (setq all (completion-pcm--filename-try-filter all)))
    (list (if (eq type 'file)
              ;; the table's grammar: ~, //, $VAR
              (expand-file-name
               (substitute-in-file-name (substring input 0 base)))
            default-directory)
          type
          (mapcar #'substring-no-properties all))))

(defun ascetic-pipe--lines (strings)
  "STRINGS as text, one per line."
  (mapconcat (lambda (s) (concat s "\n")) strings))

(defun ascetic-pipe--arg (type line)
  "LINE as Lisp wants it under TYPE: a symbol where TYPE hold symbols."
  (if (memq type ascetic-pipe--symbol-types) (intern line) line))

;;; RUN

(defun ascetic-pipe--run (cmd &optional stdin)
  "Run CMD, feeding STDIN.  Return its output."
  (with-temp-buffer
    ;; sh, not `shell-file-name': the far side of TRAMP has one too
    (let ((p (make-process :name "ascetic-pipe" :buffer (current-buffer)
                           :command (list "sh" "-c" cmd)
                           :connection-type 'pipe
                           :sentinel #'ignore
                           :noquery t
                           :file-handler t)))
      (when stdin (process-send-string p stdin))
      (process-send-eof p)
      ;; timers inhibit quit: let C-g through
      (unless (with-local-quit (while (accept-process-output p)) t)
        (signal 'quit nil))
      (buffer-string))))

;;; SINKS

(defun ascetic-pipe--show (text)
  "Show TEXT alone in *Pipe*, in `default-directory'."
  (let ((dir default-directory))
    (with-current-buffer (get-buffer-create "*Pipe*")
      (erase-buffer)
      (insert text)
      ;; acme's wdir: the output is text to act on, from here
      (setq default-directory dir)
      (display-buffer (current-buffer)))))

(defun ascetic-pipe--view (type lines)
  "Show LINES in the native view of TYPE."
  (pcase type
    ('file   (dired (cons default-directory lines)))
    ('buffer (ibuffer nil "*Pipe Buffers*"
                      `((name . ,(concat "\\`" (regexp-opt lines) "\\'")))))
    (_ (ascetic-pipe--show (ascetic-pipe--lines lines)))))

;;; ENGINE

(defun ascetic-pipe--read (op n lisp)
  "Read a command for OP over N candidates.  LISP: a function symbol."
  (if lisp
      (let ((f (completing-read (format "%d %s '" n op) obarray #'functionp t)))
        (if (string-empty-p f) (user-error "Pipe: no function") (intern f)))
    (string-trim (read-shell-command (format "%d %s " n op)))))

(defun ascetic-pipe--act (op lisp sink)
  "Read a command for OP, quit the minibuffer, call SINK where it served.
SINK takes CMD, TYPE and LINES.  LISP as in `--read'."
  (unless (minibufferp) (user-error "Pipe: not in a minibuffer"))
  ;; before any read: the nested one is a minibuffer too
  (pcase-let* ((win (minibuffer-selected-window))
               (`(,dir ,type ,lines) (ascetic-pipe--stream))
               (_ (unless lines (user-error "Pipe: empty stream")))
               ;; shell completion sees the stream's directory
               (cmd (let ((default-directory dir))
                      (ascetic-pipe--read op (length lines) lisp))))
    (unless (eq minibuffer-history-variable t)
      (add-to-history minibuffer-history-variable
                      (minibuffer-contents-no-properties)))
    ;; a sink can't run in the minibuffer: leave, then act
    (run-at-time 0 nil (lambda ()
                         (with-selected-window win
                           (let ((default-directory dir))
                             (funcall sink cmd type lines)))))
    (abort-recursive-edit)))

;;; COMMANDS

(defun ascetic-pipe-to (&optional lisp)
  "Send the stream to a command's stdin, output in *Pipe* (sam: >).
Empty: the stream in its native view.  With LISP, call a function
on each line instead."
  (interactive "P")
  (ascetic-pipe--act
   ">" lisp
   (lambda (cmd type lines)
     (cond ((symbolp cmd)
            (dolist (l lines) (funcall cmd (ascetic-pipe--arg type l))))
           ((string-empty-p cmd) (ascetic-pipe--view type lines))
           (t (ascetic-pipe--show
               (ascetic-pipe--run cmd (ascetic-pipe--lines lines))))))))

(defun ascetic-pipe-through (&optional lisp)
  "Pipe the stream through a command, output at point (sam: |).
Empty: the stream itself.  With LISP, insert a function of each
line instead."
  (interactive "P")
  (ascetic-pipe--act
   "|" lisp
   (lambda (cmd type lines)
     (insert
      (cond ((symbolp cmd)
             (ascetic-pipe--lines
              (mapcar (lambda (l)
                        (format "%s" (funcall cmd (ascetic-pipe--arg type l))))
                      lines)))
            ((string-empty-p cmd) (ascetic-pipe--lines lines))
            (t (ascetic-pipe--run cmd (ascetic-pipe--lines lines))))))))

(defun ascetic-pipe-from ()
  "Replace the input with a command's output (sam: <).
The minibuffer stays open: dot follows the new input."
  (interactive)
  (unless (minibufferp) (user-error "Pipe: not in a minibuffer"))
  (let* ((default-directory (car (ascetic-pipe--stream)))
         (cmd (string-trim (read-shell-command "< "))))
    (unless (string-empty-p cmd)
      (let ((out (string-trim-right (ascetic-pipe--run cmd))))
        (delete-minibuffer-contents)
        (insert out)))))

(provide 'ascetic-pipe)
;;; ascetic-pipe.el ends here
