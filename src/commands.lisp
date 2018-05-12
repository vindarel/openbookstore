(defpackage bookshops.commands
  (:use :cl
        :mito
        :cl-ansi-text)
  (:shadow :search
           :delete)
  (:import-from :bookshops
                :books)
  (:import-from :bookshops.models
                :book
                :make-book
                :save-book
                :find-book
                :find-book-noisbn
                :print-book
                :print-book-details
                :count-book
                :title
                :editor
                :authors
                :quantity
                :set-quantity
                :delete-books
                :price)
  (:export :main
           :search
           :add
           :details
           :stock
           :next
           :previous
           :stats
           :create
           :delete
           :*page-size*))
(in-package :bookshops.commands)

(defvar *page-size* 15
  "Maximum number of lines to show when printing results.")
(setf *page-size* 15)

(defvar *current-page* 1
  "Current page of the stock pager.")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Utils
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun percentage (low max)
  (* 100 (/ (float low)
            max)))

(defun sublist (seq start end)
  (if (> (length seq)
         end)
      (subseq seq start end)
      (subseq seq start (length seq))))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Commands
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar *last-results* nil
  "List of last search results (for now, a list of book objects).")

(defvar *last-page* nil
  "Sublist of search results. Used to autocomplete the ids of books lastly printed.")

(defvar *last-search* nil
  "List of keywords used on the last search. For example, \"stock ant\" to filter on titles.")

(defun search (query &rest rest)
  "Search for books with `query` on `datasource`, nicely print the result."
  ;; the &rest is for the readline repl, that gives many string arguments to this function.
  (let* ((query (str:unwords (cons query rest)))
         (results (books query))
         (i (length results)))
    (mapcar (lambda (it)
              (format t "~2@a- ~a, ~a~t~a~&" i (blue (title it)) (authors it) (price it))
              (decf i))
            (reverse results))))

(defun add (index)
  "Add this book (by index of the last search) into the DB."
  (when (stringp index)
    ;; generics ?
    (setf index (parse-integer index)))
  (decf index)
  (unless bookshops::*last-results*
    (format t "Please do a search before."))
  (when bookshops::*last-results*
    (let* ((bk (nth index bookshops::*last-results*)))
      (format t "Gonna register ~a~&" (title bk))
      (save-book bk)
      (print "done."))))

(defun total-pages (total)
  "Compute the number of pages given this total quantity."
  (multiple-value-bind (fl rest)
      (floor (/ total *page-size*))
    (if (= 0 rest)
        fl
        (incf fl))))

(defun next ()
  "Print next page of results (now Stock, should be the last function
  that printed results)."
  (when (< *current-page*
           (total-pages (length *last-results*)))
    (incf *current-page*))
  (print-page *last-results*))

(defun previous ()
  "Print the previous page of results (the stock for now)."
  (when (> *current-page* 1)
    (decf *current-page*))
  (print-page *last-results*))

(defun print-page (seq &optional (page *current-page*))
  "Usage: print-page <full list of results>,
   and it prints respecting the list page by page."
  (setf *last-results* seq)
  (setf *last-page* (sublist seq
                             (* (- page 1) *page-size*)
                             (*  page *page-size*)))
  (format t "Results: ~a. Page: ~a/~a~&"
          (length seq)
          page
          (total-pages (length seq)))
  (mapcar (lambda (it)
            (print-book it))
          *last-page*))

(defun stock (&optional title-kw &rest rest)
  "Show our stock (books in DB)."
  (let* ((query (if title-kw (str:join "%" (cons title-kw rest))))
         (results (find-book query)))
    (setf *last-search* query)
    (print-page results *current-page*)))

(defun details (pk)
  "Print all information about the book of the given id.

   You can complete the argument with the TAB key."
  (when (stringp pk)
    (parse-integer pk))
  (print-book-details pk))

;; Get a list of ids of the last search.
;; Specially handy when we have filtered the search.
(replic.completion:add-completion "details" (lambda ()
                                              (mapcar (lambda (it)
                                                        (prin1-to-string (object-id it)))
                                                      *last-page*)))

(defun stats (&optional arg)
  "Print some numbers about the stock.

   Prints the total number of books and ones without isbn.

   If given an argument (use the TAB key to choose it), print the list of results."
  (format t "Books in stock: ~a~&" (count-book))
  (let ((res (find-book-noisbn)))
    (format t "Books without isbn: ~a (~,2f%)~&" (length res) (percentage (length res) (count-book)))
    (when (string= arg "noisbn")
      (setf *current-page* 1)
      (format t "-----------------~&")
      (print-page res))))

(replic.completion:add-completion "stats" '("noisbn"))

(defun create (&optional what)
  "Create a new book."
  (unless what
    (setf what "book"))
  (when (symbolp what)
    (string-downcase (symbol-name what)))
  (when (string-equal what "book")
    (create-book)))

(defun create-book ()
  "Create a new book.."
  ;; next step: class and column introspection, data validation,
  ;; completion of fields etc.
  (let (bk title authors price quantity)
    (setf title (rl:readline :prompt (format nil (str:concat "Title"
                                                  (cl-ansi-text:red "*")
                                                  " ? "))))
    (when (str:blank? title)
      (error "The title field is mandatory, please try again."))
    (setf authors (rl:readline :prompt "Authors ? (comma separated) "))
    (setf price (rl:readline :prompt "Price ? [0]"))
    (if (str:blank? price)
        (setf price 0)
        (setf price (parse-integer price)))
    (setf quantity (rl:readline :prompt "Quantity ? [0]"))
    (if (str:blank? quantity)
        (setf quantity 0)
        (setf quantity (parse-integer quantity)))

    (setf bk (make-book :title title :authors authors :price price))
    (set-quantity bk quantity)
    ;; xxx save-book increments quantity
    (save-book bk)
    ;; set this for completion of ids of other commands.
    (setf *last-page* (list bk))
    (print-book bk)
    ))

(replic.completion:add-completion "create" '("book"))

(defun delete (&rest kw)
  "Delete (after confirmation) the books whose title match the given keywords.

   For example, `delete on time` will find 'once upon a time'."
  ;; xxx Doesn't work on the repl, needs a console readline.
  (let ((bklist (when kw
                  (find-book (str:join "%" kw)))))
    (if bklist
        (progn
          (print-page bklist)
          (finish-output)
          (when (replic:confirm "Do you want to delete those books ?")
            (delete-books bklist)))
        (format t "~&No results, nothing to do.~&"))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Dev
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun reset ()
  "For use in the repl."
  (setf *last-results* nil)
  (setf *last-search* nil)
  (setf *page-size* 15)
  (setf *current-page* 1))