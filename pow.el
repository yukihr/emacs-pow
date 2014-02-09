;;; pow.el --- pow (http://pow.cx/) manager for emacs

;; Copyright (c) 2013  Free Software Foundation, Inc.

;; Author: yukihiro hara <yukihr@gmail.com>
;; URL: http://github.com/yukihr/emacs-pow
;; Keywords: develop, web, pow
;; Version: 0.0.1

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

(eval-when-compile (require 'cl))



;;
;; customs
;;

(defgroup pow nil
  "pow manager"
  :group 'development
  :prefix "pow-")

(defcustom pow-symlink-directory "~/.pow"
  "Directory for symlinks of pow apps."
  :type 'string
  :group 'pow)

(defcustom pow-url-format "http://%s.dev/"
  "Url format of rack application registered on Pow. This is passed to format function with one argument: app name ."
  :type 'string
  :group 'pow)

(defcustom pow-browse-url-function 'browse-url
  "Function to browse app, takes app url."
  :type 'function
  :group 'pow)



;;
;; helper
;;

(defun pow-rack-project-root-for-dir (dir)
  "Return the root directory of the rack project within which DIR is found."
  (setq dir (expand-file-name dir))
  (cond ((or (not (file-directory-p dir))
          ;;; regexp to match windows roots, tramp roots, or regular posix roots
          ;;; copied from rinari.el
          (string-match "\\(^[[:alpha:]]:/$\\|^/[^\/]+:/?$\\|^/$\\)" dir))
         nil)
        ((file-exists-p (expand-file-name "config.ru" dir)) dir)
        (t (pow-rack-project-root-for-dir (replace-regexp-in-string "[^/]+/?$" "" dir)))))

(defun pow-same-file-p (&rest paths)
  (reduce #'(lambda (l r)
              (when (and
                     (stringp l) (stringp r)
                     (equal (file-truename l) (file-truename r)))
                (file-truename r)))
          (mapcar #'(lambda (path)
                      (replace-regexp-in-string "/$" "" path)) paths)
          :start 0))

(defun pow-message (format-string &rest args)
  (message (apply 'format (concat "Pow: " format-string) args)))


;;
;; App
;;

(defstruct (pow-app
            (:constructor nil)
            (:constructor pow-app--inner-make))
  (symlink-directory pow-symlink-directory)
  path
  (name "")
  )

(defun make-pow-app (&rest options)
  (if (plist-get options :path)
      (setq options (plist-put options :path
                               (expand-file-name
                                (plist-get options :path)))))
  (let ((pow-app
         (apply 'pow-app--inner-make options)))
    (if (not (plist-get options :name))
        (pow-app-set-name-with-path pow-app))
    pow-app))

(defun pow-app-set-name-with-path (app)
  (let* ((path (pow-app-path app))
         (name
          (progn
            (string-match "\\/\\([^\\/]+\\)\\/?$" path)
            (match-string 1 path))))
    (setf (pow-app-name app) name)))

(defun pow-app-set-name-default (app)
  (setf (pow-app-name app) "default"))

(defun pow-app-url (app)
  (format pow-url-format (pow-app-name app)))

(defun pow-app-open (app)
  (let ((url (pow-app-url app)))
    (funcall pow-browse-url-function url)))

(defun pow-app-symlink-path (app)
  (expand-file-name
   (pow-app-name app)
   (pow-app-symlink-directory app)))

(defun pow-app-save (app)
  (make-symbolic-link (pow-app-path app)
                      (pow-app-symlink-path app)))

(defun pow-app-delete (app)
  (delete-file (pow-app-symlink-path app)))

(defun pow-app-restart (app)
  (let ((txt "restart.txt")
        (dir (concat (pow-app-path app) "/tmp")))
    (make-directory dir 'parents)
    (write-region "" nil (concat dir "/" txt) nil 'quiet)))

(defun pow-app-load-all ()
  (let* ((dir pow-symlink-directory)
         (symlinks (directory-files dir)))
    (remove-if
     #'nil
     (mapcar
      #'(lambda (symlink)
          (let ((symlink-path (expand-file-name symlink dir)))
            (when (and (not (equal "." symlink))
                       (not (equal ".." symlink))
                       (file-symlink-p symlink-path))
              (make-pow-app :path (file-chase-links symlink-path)
                            :name symlink)))
                    ) symlinks))))

(defun pow-app-load-for-project (project-dir)
  (remove-if #'(lambda (app)
                 (not (pow-same-file-p
                       (pow-app-path app) project-dir)))
             (pow-app-load-all)))

(defun pow-app-load-for-dir (dir)
  (let ((project-path (pow-rack-project-root-for-dir dir)))
    (when project-path
      (pow-app-load-for-project project-path))))



;;
;; user function
;;

(defmacro pow-with-rack-project-root (root-path &rest body)
  (declare (indent 1))
  `(let ((,root-path (pow-rack-project-root-for-dir default-directory)))
     (if ,root-path
         (progn ,@body)
       (pow-message "Not in rack project.."))))

(defun pow-register-project (&optional name)
  (interactive)
  (pow-with-rack-project-root path
    (let* ((app (make-pow-app :path path))
           (appname (pow-app-name app)))
      (if (null name)
          (setq name (read-string (format "App Name(%s):" appname)
                                  nil nil appname)))
      (setf (pow-app-name app) name)
      (condition-case err
          (progn
            (pow-app-save app)
            (pow-message "Registered app \"%s\"." name))
        (file-already-exists
         (pow-message "App \"%s\" is already registered.." name))))))

(defun pow-register-app-as-default ()
  (interactive)
  (pow-register-project "default"))

(defmacro pow-with-current-apps (apps &rest body)
  (declare (indent 1))
  `(let ((,apps (pow-app-load-for-dir default-directory)))
     (if (not (null ,apps))
         (progn ,@body)
       (pow-message "App for current project was not found.."))))

(defmacro pow-with-current-app (app &rest body)
  (declare (indent 1))
  `(pow-with-current-apps apps
     (if (eq (length apps) 1)
         (let ((,app (car apps)))
           (progn ,@body))
       (let* ((names (mapcar #'(lambda (-app) (pow-app-name -app)) apps))
              (name
               (completing-read (format "App Name(%s):" (car names))
                                names nil t nil nil (car names)))
              (,app
               (car (remove-if
                     #'(lambda (--app)
                         (not
                          (equal (pow-app-name --app) name)))
                     apps))))
         (if (not (null ,app))
             (progn ,@body)
           (pow-message "App \"%s\" is not found.." name))))))

(defun pow-unregister-project ()
  (interactive)
  (pow-with-current-app app
    (let ((appname (pow-app-name app)))
      (condition-case err
          (progn
            (pow-app-delete app)
            (pow-message "Unregistered app \"%s\"." appname))
        (file-error
         (pow-message "App \"%s\" couldn't be unregistered." appname))))))

(defun pow-open-app ()
  (interactive)
  (pow-with-current-app app (pow-app-open app)))

;; (defun pow-restart-app ()
;;   (interactive)
;;   (pow-with-current-app app
;;     (pow-app-restart app)
;;     (message "App will restart on next request.")))

(provide 'pow)
