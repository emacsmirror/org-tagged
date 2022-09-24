;;; org-tagged.el --- Dynamic block for tagged org-mode todos -*- lexical-binding: t -*-
;; Copyright (C) 2022 Christian Köstlin

;; This file is NOT part of GNU Emacs.

;; Author: Christian Köstlin <christian.koestlin@gmail.com>
;; Keywords: org-mode, org, gtd, tools
;; Package-Requires: ((s "1.13.0") (dash "2.19.1") (emacs "28.1") (org "9.5.2"))
;; Package-Version: 0.0.4
;; Homepage: http://github.com/gizmomogwai/org-tagged

;;; Commentary:
;; To create a tagged table for an org file, simply put the dynamic block
;; `
;; #+BEGIN: tagged :columns "%10tag1(Tag1)|tag2" :match "kanban"
;; #+END:
;; '
;; somewhere and run `C-c C-c' on it.

;;; Code:
(require 's)
(require 'dash)
(require 'org)
(require 'org-table)

(defun org-tagged--get-data-from-heading ()
  "Extract the needed information from a heading.
Return a list with
- the heading
- the tags as list of strings."
  (list
    (nth 4 (org-heading-components))
    (remove "" (s-split ":" (or (nth 5 (org-heading-components)) "")))))

(defun org-tagged--row-for (heading item-tags columns)
  "Create a row for a HEADING and its ITEM-TAGS for a table with COLUMNS."
  (let ((result  (format "|%s|" (s-join "|"
    (--map
      (if (-elem-index (nth 1 it) item-tags)
        (s-truncate (nth 0 it) heading)
        "")
      columns)))))
    (if (eq (length result) (1+ (length columns))) nil result)))

(defun org-tagged-version ()
  "Print org-tagge version."
  (interactive)
  (message "org-tagged 0.0.4"))

(defun org-tagged--parse-column (column-description)
  "Parse a column from a COLUMN-DESCRIPTION.
Each column description consists of:
- maximum length (defaults to 1000)
- tag to select the elements that go into the column
- title of the column (defaults to the tag)"
  (string-match
    (rx
      string-start
      (optional (and "%" (group (one-or-more digit))))
      (group (minimal-match (1+ anything)))
      (optional (and "(" (group (+? anything)) ")"))
      string-end)
    column-description)
  (list
    (string-to-number (or (match-string 1 column-description) "1000"))
    (match-string 2 column-description)
    (or (match-string 3 column-description) (match-string 2 column-description))))

(defun org-tagged--get-columns (columns-description)
  "Parse the column descriptions out of COLUMNS-DESCRIPTION.
The columns are separated by `|'."
  (--map (org-tagged--parse-column it) (s-split "|" columns-description)))


(defun org-tagged--calculate-preview (columns match)
  "Calculate the org-tagged header for COLUMNS and MATCH."
  (s-join " " (delq nil
                (list "#+BEGIN: tagged"
                  (format ":columns \"%s\"" columns)
                  (if match (format ":match \"%s\"" match) nil)))))

(defun org-tagged--update-preview (preview columns match)
  "Update the PREVIEW widget with the org-tagged header for COLUMNS and MATCH."
  (widget-value-set preview (org-tagged--calculate-preview columns match)))

(defun org-tagged--show-configure-buffer (buffer beginning parameters)
  "Create the configuration form for BUFFER.
BEGINNING the position there and
PARAMETERS the org-tagged parameters."
  (switch-to-buffer "*org-tagged-configure*")
  (let (
         (inhibit-read-only t)
         (columns (plist-get parameters :columns))
         (columns-widget nil)
         (match (plist-get parameters :match))
         (match-widget nil))
    (erase-buffer)
    (remove-overlays)

    (widget-insert (propertize "Columns: " 'face 'font-lock-keyword-face))
    (setq match-widget (widget-create 'editable-field
                         :value (format "%s" (or columns ""))
                         :size 40
                         :notify (lambda (widget &rest _ignore)
                                   (setq columns (widget-value widget))
                                   (org-tagged--update-preview preview columns match))))
    (widget-insert "\n")
    (widget-insert (propertize "  select columns in the format [%LENGTH]TAG[(TITLE)]|..." 'face 'font-lock-doc-face))
    (widget-insert "\n\n")

    (widget-insert (propertize "Match: " 'face 'font-lock-keyword-face))
    (setq match-widget (widget-create 'editable-field
                         :value (format "%s" (or match ""))
                         :size 40
                         :notify (lambda (widget &rest _ignore)
                                   (setq match (widget-value widget))
                                   (org-tagged--update-preview preview columns match))))
    (widget-insert "\n")
    (widget-insert (propertize "  match to tags e.g. urgent|important" 'face 'font-lock-doc-face))

    (widget-insert "\n\n")

    (widget-insert (propertize "Result: " 'face 'font-lock-keyword-face))
    (setq preview
      (widget-create 'const))

    (widget-create 'push-button
      :notify (lambda(_widget &rest _ignore)
                (with-current-buffer buffer
                  (goto-char beginning)
                  (kill-line)
                  (insert (org-tagged--calculate-preview columns match)))
                (kill-buffer)
                (org-ctrl-c-ctrl-c))
      (propertize "Apply" 'face 'font-lock-comment-face))
    (widget-insert " ")
    (widget-create 'push-button
      :notify (lambda (_widget &rest _ignore)
                (kill-buffer))
      (propertize "Cancel" 'face 'font-lock-string-face))

    (org-tagged--update-preview preview columns match)
    (use-local-map widget-keymap)
    (widget-setup)))


;;;###autoload
(defun org-dblock-write:tagged (params)
  "Create a tagged dynamic block.
PARAMS must contain: `:tags`."
  (insert
    (let*
      (
        (columns
          (org-tagged--get-columns (plist-get params :columns)))
        (todos
          (org-map-entries 'org-tagged--get-data-from-heading (plist-get params :match)))
        (table
          (s-join "\n" (remove nil (--map (org-tagged--row-for (nth 0 it) (nth 1 it) columns) todos)))))
      (format "|%s|\n|--|\n%s" (s-join "|" (--map (nth 2 it) columns)) table)))
  (org-table-align))

(defun org-tagged-initialize ()
  "Create an org-tagged dynamic block at the point."
  (interactive)
  (save-excursion
    (insert "#+BEGIN: tagged :columns \"%25tag1(Title)|tag2\" :match \"kanban\"\n#+END:\n"))
  (org-ctrl-c-ctrl-c))

(defun org-tagged-configure-block ()
  "Configure the current org-tagged dynamic block."
  (interactive)
  (let* (
          (beginning (org-beginning-of-dblock))
          (parameters (org-prepare-dblock)))
    (org-tagged--show-configure-buffer (current-buffer) beginning parameters)))


(provide 'org-tagged)
;;; org-tagged.el ends here

