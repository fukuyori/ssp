;;;; formula.lisp
;;;; SSP v0.7.2 - 数式評価エンジン、許可関数リスト
;;;; v0.7.1: 循環参照検出改善、評価深さ制限

(in-package :ssexp)

;;;; =========================
;;;; 評価深さ追跡 (v0.7.1 新規)
;;;; =========================

(defvar *current-eval-depth* 0
  "現在の評価深さ")

(defun check-eval-depth ()
  "評価深さが制限を超えていないかチェック"
  (when (> *current-eval-depth* *max-eval-depth*)
    (error "評価深さ制限を超えました (~d)。循環参照の可能性があります。" 
           *max-eval-depth*)))

;;;; =========================
;;;; 位置参照関数
;;;; =========================

(defun this-row ()
  "現在のセルの行番号を返す（1始まり）"
  (1+ (eval-row)))

(defun this-col ()
  "現在のセルの列番号を返す（0始まり）"
  (eval-col))

(defun this-col-name ()
  "現在のセルの列名を返す"
  (string (code-char (+ (char-code #\A) (eval-col)))))

(defun this-cell-name ()
  "現在のセル名を返す"
  (cell-name (eval-col) (eval-row)))

(defun cell-at (row col)
  "行列番号でセルの値を取得（row:1始まり, col:0始まりまたは文字列）
   v0.7.1: 循環パス記録を追加"
  (let* ((actual-col (if (stringp col)
                         (- (char-code (char (string-upcase col) 0)) (char-code #\A))
                         col))
         (actual-row (1- row))  ; 1始まり→0始まり
         (name (cell-name actual-col actual-row)))
    (when (and (>= actual-col 0) (< actual-col (sheet-cols))
               (>= actual-row 0) (< actual-row (sheet-rows)))
      ;; 循環参照チェック (v0.7.1 強化)
      (if (eval-stack-member name)
          (progn
            (record-cycle-path (cons name *eval-stack*))
            (error "循環参照を検出: ~a" name))
          (let ((cell (get-cell name)))
            (cell-value cell))))))

(defun rel (drow dcol)
  "現在のセルからの相対位置のセル値を取得
   v0.7.1: 循環パス記録を追加"
  (let* ((new-col (+ (eval-col) dcol))
         (new-row (+ (eval-row) drow))
         (name (cell-name new-col new-row)))
    (if (and (>= new-col 0) (< new-col (sheet-cols))
             (>= new-row 0) (< new-row (sheet-rows)))
        ;; 循環参照チェック (v0.7.1 強化)
        (if (eval-stack-member name)
            (progn
              (record-cycle-path (cons name *eval-stack*))
              (error "循環参照を検出: ~a (rel ~d ~d)" name drow dcol))
            (let ((cell (get-cell name)))
              (cell-value cell)))
        ;; 範囲外はNIL
        nil)))

(defun rel-range (dr1 dc1 dr2 dc2)
  "相対位置で範囲を指定して値のリストを取得
   v0.7.1: 循環参照チェック強化"
  (let* ((r1 (+ (eval-row) dr1))
         (c1 (+ (eval-col) dc1))
         (r2 (+ (eval-row) dr2))
         (c2 (+ (eval-col) dc2))
         ;; 正規化
         (min-r (min r1 r2))
         (max-r (max r1 r2))
         (min-c (min c1 c2))
         (max-c (max c1 c2))
         (result nil))
    (loop for r from min-r to max-r do
      (loop for c from min-c to max-c do
        (when (and (>= c 0) (< c (sheet-cols))
                   (>= r 0) (< r (sheet-rows)))
          (let ((name (cell-name c r)))
            (unless (eval-stack-member name)
              (let ((val (cell-value (get-cell name))))
                (when val (push val result))))))))
    (nreverse result)))

;;;; =========================
;;;; ユーティリティ
;;;; =========================

(defun flatten (lst)
  "ネストしたリストを平坦化"
  (cond ((null lst) nil)
        ((atom lst) (list lst))
        (t (append (flatten (car lst))
                   (flatten (cdr lst))))))

(defun try-parse-number (val)
  "文字列を数値に変換。失敗時は元の値を返す"
  (if (stringp val)
      (let ((parsed (ignore-errors (read-from-string val))))
        (if (numberp parsed) parsed val))
      val))

;;;; =========================
;;;; 許可された関数リスト
;;;; =========================

(defparameter *allowed-functions*
  '(;; 算術演算
    + - * / mod rem 1+ 1-
    floor ceiling round truncate
    abs max min signum
    sqrt expt log exp isqrt
    sin cos tan asin acos atan sinh cosh tanh
    gcd lcm
    ;; 乱数
    random
    ;; ビット演算
    logand logior logxor lognot ash logcount
    ;; 比較
    = /= < > <= >=
    equal equalp eq eql
    ;; リスト操作
    car cdr cons list
    first second third fourth fifth sixth seventh eighth ninth tenth
    rest last butlast nthcdr
    append reverse length nth elt
    member assoc assoc-if rassoc rassoc-if
    find find-if position position-if
    getf get  ; plistアクセス
    mapcar mapc maplist mapcon mapcan
    remove remove-if remove-if-not remove-duplicates
    reduce count count-if count-if-not
    substitute substitute-if substitute-if-not
    subseq copy-list copy-seq copy-tree copy-alist
    list-length
    tree-equal sublis
    ;; ソート（非破壊的に実装）
    sort stable-sort
    ;; 条件チェック
    every some notevery notany
    ;; 集合演算
    intersection union set-difference set-exclusive-or subsetp
    ;; 検索
    search mismatch
    ;; リスト作成
    make-list iota pairlis acons
    ;; 文字列
    string-upcase string-downcase string-capitalize
    string-trim string-left-trim string-right-trim
    concatenate subseq char
    string= string/= string< string> string<= string>=
    string-equal string-not-equal
    string-lessp string-greaterp string-not-greaterp string-not-lessp
    parse-integer
    ;; 文字
    char-upcase char-downcase char-code code-char digit-char
    char= char/= char< char> char<= char>=
    char-equal char-not-equal char-lessp char-greaterp
    alpha-char-p digit-char-p upper-case-p lower-case-p
    alphanumericp graphic-char-p
    ;; 論理
    not null and or
    ;; 述語
    atom listp consp numberp integerp floatp rationalp realp complexp
    stringp symbolp characterp keywordp functionp
    zerop plusp minusp evenp oddp
    ;; 型
    type-of typep
    ;; 型変換
    float truncate round floor ceiling
    string coerce
    ;; ユーティリティ
    identity constantly values
    ;; 数学定数（変数として）
    pi
    ;; スプレッドシート専用
    sum avg cell-count range ref
    ;; 位置参照
    this-row this-col this-col-name this-cell-name
    cell-at rel rel-range
    ;; lambda / apply / funcall / let / setf
    lambda apply funcall let let* setf))

;;;; =========================
;;;; 数式評価エンジン（拡張版）
;;;; =========================

(defun cell-ref-p (sym)
  "シンボルがセル参照か判定。A1〜Z99形式を認識"
  (and (symbolp sym)
       (not (keywordp sym))
       (let ((name (symbol-name sym)))
         (and (>= (length name) 2)
              (<= (length name) 3)
              (alpha-char-p (char name 0))
              (every #'digit-char-p (subseq name 1))
              ;; 許可された関数名でないことを確認
              (not (member (string-upcase name) 
                          (mapcar #'symbol-name *allowed-functions*)
                          :test #'string=))))))

(defun parse-cell-coords (sym)
  "セル参照シンボルから座標(col row)を取得"
  (let* ((name (symbol-name sym))
         (col (- (char-code (char-upcase (char name 0))) (char-code #\A)))
         (row (1- (parse-integer (subseq name 1)))))
    (list col row)))

(defun get-cell-by-symbol (sym)
  "シンボル(A1等)からセル値を取得（生の値）"
  (let* ((coords (parse-cell-coords sym))
         (col (first coords))
         (row (second coords)))
    (cell-value (get-cell (cell-name col row)))))

(defun ref (name)
  "文字列でセル参照"
  (let* ((col (- (char-code (char-upcase (char name 0))) (char-code #\A)))
         (row (1- (parse-integer (subseq name 1)))))
    (cell-value (get-cell (cell-name col row)))))

(defun expand-range (start-sym end-sym)
  "範囲を展開してセル値のリストを返す"
  (let* ((start-coords (parse-cell-coords start-sym))
         (end-coords (parse-cell-coords end-sym))
         (col1 (first start-coords))
         (row1 (second start-coords))
         (col2 (first end-coords))
         (row2 (second end-coords))
         (min-col (min col1 col2))
         (max-col (max col1 col2))
         (min-row (min row1 row2))
         (max-row (max row1 row2))
         (values '()))
    (loop for r from min-row to max-row do
          (loop for c from min-col to max-col do
                (push (cell-value (get-cell (cell-name c r))) values)))
    (nreverse values)))

(defun allowed-function-p (sym)
  "関数が許可リストに含まれるか確認"
  (let ((name (string-upcase (symbol-name sym))))
    (member name (mapcar #'symbol-name *allowed-functions*)
            :test #'string=)))

(defun get-lisp-function (op-name)
  "関数名から実際の関数を取得。可変引数関数はリストを自動展開"
  (cond
    ;; スプレッドシート専用関数
    ((string-equal op-name "SUM")
     (lambda (&rest args)
       (apply #'+ (remove-if-not #'numberp (flatten args)))))
    ((string-equal op-name "AVG")
     (lambda (&rest args)
       (let ((nums (remove-if-not #'numberp (flatten args))))
         (if nums (float (/ (apply #'+ nums) (length nums))) 0))))
    ((string-equal op-name "CELL-COUNT")
     ;; スプレッドシート専用: 範囲内のセル数を数える
     (lambda (&rest args)
       (length (flatten args))))
    ;; COUNT は CL の count を使用（get-function-by-name で処理）
    ;; 位置参照関数
    ((string-equal op-name "THIS-ROW") #'this-row)
    ((string-equal op-name "THIS-COL") #'this-col)
    ((string-equal op-name "THIS-COL-NAME") #'this-col-name)
    ((string-equal op-name "THIS-CELL-NAME") #'this-cell-name)
    ((string-equal op-name "CELL-AT") #'cell-at)
    ((string-equal op-name "REL") #'rel)
    ((string-equal op-name "REL-RANGE") #'rel-range)
    ;; iota関数（範囲リスト生成）
    ((string-equal op-name "IOTA")
     (lambda (n &optional (start 0) (step 1))
       (loop for i from 0 below n collect (+ start (* i step)))))
    ;; 可変引数の算術演算（リスト自動展開）
    ((string-equal op-name "+")
     (lambda (&rest args)
       (apply #'+ (remove-if-not #'numberp (flatten args)))))
    ((string-equal op-name "-")
     (lambda (&rest args)
       (let ((nums (remove-if-not #'numberp (flatten args))))
         (if nums (apply #'- nums) 0))))
    ((string-equal op-name "*")
     (lambda (&rest args)
       (apply #'* (remove-if-not #'numberp (flatten args)))))
    ((string-equal op-name "/")
     (lambda (&rest args)
       (let ((nums (remove-if-not #'numberp (flatten args))))
         (if (and nums (not (member 0 (cdr nums))))
             (apply #'/ nums)
             "DIV/0!"))))
    ((string-equal op-name "MAX")
     (lambda (&rest args)
       (let ((nums (remove-if-not #'numberp (flatten args))))
         (if nums (apply #'max nums) 0))))
    ((string-equal op-name "MIN")
     (lambda (&rest args)
       (let ((nums (remove-if-not #'numberp (flatten args))))
         (if nums (apply #'min nums) 0))))
    ;; 標準Lisp関数
    (t 
     (let ((cl-sym (find-symbol op-name :cl)))
       (when (and cl-sym (fboundp cl-sym))
         (symbol-function cl-sym))))))

;;; lambda環境（動的束縛用）
(defparameter *lambda-env* nil)

(defun lookup-var (sym)
  "lambda環境から変数を探す
   環境は (("VAR" . (value)) ...) の形式で、値はconsセルに格納"
  (let ((pair (assoc (symbol-name sym) *lambda-env* :test #'string-equal)))
    (if pair
        (values (cadr pair) t)  ; (cdr pair) = (value), (cadr pair) = value
        (values nil nil))))

(defun set-var (sym new-value)
  "lambda環境の変数に値を設定"
  (let ((pair (assoc (symbol-name sym) *lambda-env* :test #'string-equal)))
    (if pair
        (progn
          (setf (car (cdr pair)) new-value)  ; 値を変更
          new-value)
        (error "Undefined variable: ~A" sym))))

(defun make-binding (name value)
  "変数束縛を作成（変更可能な形式）"
  (cons name (list value)))

(defun eval-formula (expr)
  "S式の数式を評価。Lispの非破壊関数をサポート。
   v0.7.1: 評価深さ制限を追加
   戻り値: 数値、文字列、リスト、シンボルなど任意のLisp値"
  ;; 深さチェック (v0.7.1)
  (incf *current-eval-depth*)
  (unwind-protect
      (progn
        (check-eval-depth)
        (cond
          ;; nil
          ((null expr) nil)
          ;; 数値・文字列はそのまま
          ((numberp expr) expr)
          ((stringp expr) expr)
          ;; キーワードシンボルはそのまま
          ((keywordp expr) expr)
          ;; クォートされた式
          ((and (listp expr) (eq (car expr) 'quote))
           (cadr expr))
          ;; シンボルの場合：lambda変数 > セル参照 > 定数 > そのまま
          ((symbolp expr)
           (multiple-value-bind (val found) (lookup-var expr)
             (cond
               ;; lambda変数に見つかった
               (found val)
               ;; セル参照
               ((cell-ref-p expr)
                (let ((val (get-cell-by-symbol expr)))
                  (if (stringp val) (try-parse-number val) val)))
               ;; PI定数
               ((string-equal (symbol-name expr) "PI") pi)
               ;; その他のシンボルはそのまま
               (t expr))))
          ;; リスト（関数呼び出し）
          ((listp expr)
           (let* ((op (car expr))
                  (op-name (if (symbolp op) (string-upcase (symbol-name op)) "")))
             (cond
               ;; ((lambda (x) ...) args...) - lambda式の直接呼び出し
               ((and (listp op)
                     (symbolp (car op))
                     (string-equal (symbol-name (car op)) "LAMBDA"))
                (let ((fn (eval-formula op))
                      (args (mapcar #'eval-formula (cdr expr))))
                  (if (functionp fn)
                      (apply fn args)
                      (format nil "ERR: not a function"))))
               ;; LAMBDA - 無名関数を作成
               ((string-equal op-name "LAMBDA")
                (let ((params (cadr expr))
                      (body (caddr expr)))
                  ;; クロージャとして現在の環境をキャプチャ
                  (let ((captured-env *lambda-env*))
                    (lambda (&rest args)
                      (let ((*lambda-env* (append (mapcar #'make-binding
                                                          (mapcar #'symbol-name params)
                                                          args)
                                                  captured-env)))
                        (eval-formula body))))))
               ;; 範囲指定 (range A1 A5)
               ((string-equal op-name "RANGE")
                (if (and (>= (length expr) 3)
                         (cell-ref-p (cadr expr))
                   (cell-ref-p (caddr expr)))
              (expand-range (cadr expr) (caddr expr))
              :error))
         ;; IF式（短絡評価）
         ((string-equal op-name "IF")
          (if (eval-formula (cadr expr))
              (eval-formula (caddr expr))
              (eval-formula (cadddr expr))))
         ;; COND式
         ((string-equal op-name "COND")
          (loop for clause in (cdr expr)
                when (eval-formula (car clause))
                return (eval-formula (cadr clause))))
         ;; LET - ローカル変数束縛（並列束縛）
         ((string-equal op-name "LET")
          (let* ((bindings (cadr expr))
                 (body (cddr expr))
                 ;; 全ての値を先に評価（並列束縛）
                 (new-bindings (mapcar (lambda (b)
                                         (make-binding 
                                           (symbol-name (if (listp b) (car b) b))
                                           (if (and (listp b) (cdr b))
                                               (eval-formula (cadr b))
                                               nil)))
                                       bindings)))
            (let ((*lambda-env* (append new-bindings *lambda-env*)))
              ;; bodyの全式を評価し、最後の値を返す
              (loop for form in body
                    for result = (eval-formula form)
                    finally (return result)))))
         ;; LET* - ローカル変数束縛（逐次束縛）
         ((string-equal op-name "LET*")
          (let ((bindings (cadr expr))
                (body (cddr expr)))
            ;; 束縛を順番に追加しながら評価
            (labels ((bind-sequentially (remaining-bindings)
                       (if (null remaining-bindings)
                           ;; 全束縛完了、bodyを評価
                           (loop for form in body
                                 for result = (eval-formula form)
                                 finally (return result))
                           ;; 次の束縛を処理
                           (let* ((b (car remaining-bindings))
                                  (var (symbol-name (if (listp b) (car b) b)))
                                  (val (if (and (listp b) (cdr b))
                                           (eval-formula (cadr b))
                                           nil)))
                             (let ((*lambda-env* (cons (make-binding var val) *lambda-env*)))
                               (bind-sequentially (cdr remaining-bindings)))))))
              (bind-sequentially bindings))))
         ;; SETF - ローカル変数への代入
         ((string-equal op-name "SETF")
          (let ((place (cadr expr))
                (value-expr (caddr expr)))
            (if (symbolp place)
                ;; 単純な変数への代入
                (let ((new-value (eval-formula value-expr)))
                  (set-var place new-value))
                (format nil "ERR: setf only supports local variables"))))
         ;; AND（短絡評価）
         ((string-equal op-name "AND")
          (loop for arg in (cdr expr)
                for val = (eval-formula arg)
                unless val return nil
                finally (return val)))
         ;; OR（短絡評価）
         ((string-equal op-name "OR")
          (loop for arg in (cdr expr)
                for val = (eval-formula arg)
                when val return val))
         ;; FUNCTION (#') - シンボルを関数として返す
         ((string-equal op-name "FUNCTION")
          (let ((fn-name (cadr expr)))
            (if (symbolp fn-name)
                (get-lisp-function (symbol-name fn-name))
                fn-name)))
         ;; MAPCAR（特別扱い：第一引数が関数）
         ((string-equal op-name "MAPCAR")
          (let* ((fn-expr (cadr expr))
                 (fn (cond
                       ;; #'func 形式
                       ((and (listp fn-expr) (eq (car fn-expr) 'function))
                        (get-lisp-function (symbol-name (cadr fn-expr))))
                       ;; lambda 形式
                       ((and (listp fn-expr) 
                             (string-equal (symbol-name (car fn-expr)) "LAMBDA"))
                        (eval-formula fn-expr))
                       ;; その他（評価）
                       (t (eval-formula fn-expr))))
                 (lists (mapcar #'eval-formula (cddr expr))))
            (if (functionp fn)
                (apply #'mapcar fn lists)
                (format nil "ERR: not a function"))))
         ;; FIND-IF / POSITION-IF
         ((or (string-equal op-name "FIND-IF")
              (string-equal op-name "POSITION-IF"))
          (let* ((fn-expr (cadr expr))
                 (fn (cond
                       ((and (listp fn-expr) (eq (car fn-expr) 'function))
                        (get-lisp-function (symbol-name (cadr fn-expr))))
                       ((and (listp fn-expr)
                             (string-equal (symbol-name (car fn-expr)) "LAMBDA"))
                        (eval-formula fn-expr))
                       (t (eval-formula fn-expr))))
                 (seq (eval-formula (caddr expr))))
            (if (functionp fn)
                (funcall (if (string-equal op-name "FIND-IF")
                             #'find-if
                             #'position-if)
                         fn seq)
                (format nil "ERR: not a function"))))
         ;; REDUCE
         ((string-equal op-name "REDUCE")
          (let* ((fn-expr (cadr expr))
                 (fn (cond
                       ((and (listp fn-expr) (eq (car fn-expr) 'function))
                        (get-lisp-function (symbol-name (cadr fn-expr))))
                       ((and (listp fn-expr)
                             (string-equal (symbol-name (car fn-expr)) "LAMBDA"))
                        (eval-formula fn-expr))
                       (t (eval-formula fn-expr))))
                 (lst (eval-formula (caddr expr)))
                 (rest-args (cdddr expr)))
            (if (functionp fn)
                (apply #'reduce fn lst rest-args)
                (format nil "ERR: not a function"))))
         ;; APPLY
         ((string-equal op-name "APPLY")
          (let* ((fn-expr (cadr expr))
                 (fn (cond
                       ((and (listp fn-expr) (eq (car fn-expr) 'function))
                        (get-lisp-function (symbol-name (cadr fn-expr))))
                       ((and (listp fn-expr)
                             (string-equal (symbol-name (car fn-expr)) "LAMBDA"))
                        (eval-formula fn-expr))
                       (t (eval-formula fn-expr))))
                 (args (mapcar #'eval-formula (cddr expr))))
            (if (functionp fn)
                ;; 最後の引数がリストならspread、そうでなければそのまま
                (let* ((last-arg (car (last args)))
                       (init-args (butlast args))
                       (all-args (if (listp last-arg)
                                     (append init-args last-arg)
                                     args)))
                  (apply fn all-args))
                (format nil "ERR: not a function"))))
         ;; FUNCALL
         ((string-equal op-name "FUNCALL")
          (let* ((fn-expr (cadr expr))
                 (fn (cond
                       ((and (listp fn-expr) (eq (car fn-expr) 'function))
                        (get-lisp-function (symbol-name (cadr fn-expr))))
                       ((and (listp fn-expr)
                             (string-equal (symbol-name (car fn-expr)) "LAMBDA"))
                        (eval-formula fn-expr))
                       (t (eval-formula fn-expr))))
                 (args (mapcar #'eval-formula (cddr expr))))
            (if (functionp fn)
                (apply fn args)
                (format nil "ERR: not a function"))))
         ;; REMOVE-IF / REMOVE-IF-NOT / COUNT-IF / COUNT-IF-NOT
         ((or (string-equal op-name "REMOVE-IF")
              (string-equal op-name "REMOVE-IF-NOT")
              (string-equal op-name "COUNT-IF")
              (string-equal op-name "COUNT-IF-NOT"))
          (let* ((fn-expr (cadr expr))
                 (fn (cond
                       ((and (listp fn-expr) (eq (car fn-expr) 'function))
                        (get-lisp-function (symbol-name (cadr fn-expr))))
                       ((and (listp fn-expr)
                             (string-equal (symbol-name (car fn-expr)) "LAMBDA"))
                        (eval-formula fn-expr))
                       (t (eval-formula fn-expr))))
                 (lst (eval-formula (caddr expr))))
            (if (functionp fn)
                (funcall (cond
                          ((string-equal op-name "REMOVE-IF") #'remove-if)
                          ((string-equal op-name "REMOVE-IF-NOT") #'remove-if-not)
                          ((string-equal op-name "COUNT-IF") #'count-if)
                          (t #'count-if-not))
                         fn lst)
                (format nil "ERR: not a function"))))
         ;; SUBSTITUTE / SUBSTITUTE-IF / SUBSTITUTE-IF-NOT
         ((or (string-equal op-name "SUBSTITUTE")
              (string-equal op-name "SUBSTITUTE-IF")
              (string-equal op-name "SUBSTITUTE-IF-NOT"))
          (if (string-equal op-name "SUBSTITUTE")
              ;; (substitute new old seq)
              (let ((new (eval-formula (cadr expr)))
                    (old (eval-formula (caddr expr)))
                    (seq (eval-formula (cadddr expr))))
                (substitute new old seq))
              ;; (substitute-if new pred seq) / (substitute-if-not new pred seq)
              (let* ((new (eval-formula (cadr expr)))
                     (fn-expr (caddr expr))
                     (fn (cond
                           ((and (listp fn-expr) (eq (car fn-expr) 'function))
                            (get-lisp-function (symbol-name (cadr fn-expr))))
                           ((and (listp fn-expr)
                                 (string-equal (symbol-name (car fn-expr)) "LAMBDA"))
                            (eval-formula fn-expr))
                           (t (eval-formula fn-expr))))
                     (seq (eval-formula (cadddr expr))))
                (if (functionp fn)
                    (funcall (if (string-equal op-name "SUBSTITUTE-IF")
                                 #'substitute-if
                                 #'substitute-if-not)
                             new fn seq)
                    (format nil "ERR: not a function")))))
         ;; EVERY / SOME / NOTEVERY / NOTANY
         ((or (string-equal op-name "EVERY")
              (string-equal op-name "SOME")
              (string-equal op-name "NOTEVERY")
              (string-equal op-name "NOTANY"))
          (let* ((fn-expr (cadr expr))
                 (fn (cond
                       ((and (listp fn-expr) (eq (car fn-expr) 'function))
                        (get-lisp-function (symbol-name (cadr fn-expr))))
                       ((and (listp fn-expr)
                             (string-equal (symbol-name (car fn-expr)) "LAMBDA"))
                        (eval-formula fn-expr))
                       (t (eval-formula fn-expr))))
                 (seqs (mapcar #'eval-formula (cddr expr))))
            (if (functionp fn)
                (apply (cond
                         ((string-equal op-name "EVERY") #'every)
                         ((string-equal op-name "SOME") #'some)
                         ((string-equal op-name "NOTEVERY") #'notevery)
                         (t #'notany))
                       fn seqs)
                (format nil "ERR: not a function"))))
         ;; ASSOC-IF / RASSOC-IF
         ((or (string-equal op-name "ASSOC-IF")
              (string-equal op-name "RASSOC-IF"))
          (let* ((fn-expr (cadr expr))
                 (fn (cond
                       ((and (listp fn-expr) (eq (car fn-expr) 'function))
                        (get-lisp-function (symbol-name (cadr fn-expr))))
                       ((and (listp fn-expr)
                             (string-equal (symbol-name (car fn-expr)) "LAMBDA"))
                        (eval-formula fn-expr))
                       (t (eval-formula fn-expr))))
                 (alist (eval-formula (caddr expr))))
            (if (functionp fn)
                (funcall (if (string-equal op-name "ASSOC-IF")
                             #'assoc-if
                             #'rassoc-if)
                         fn alist)
                (format nil "ERR: not a function"))))
         ;; SORT（非破壊的：コピーしてからソート、:key対応）
         ((string-equal op-name "SORT")
          (let* ((args (cdr expr))
                 (seq (eval-formula (first args)))
                 (pred-expr (second args))
                 (pred (cond
                         ((null pred-expr) #'<)
                         ((and (listp pred-expr) (eq (car pred-expr) 'function))
                          (get-lisp-function (symbol-name (cadr pred-expr))))
                         ((and (listp pred-expr)
                               (string-equal (symbol-name (car pred-expr)) "LAMBDA"))
                          (eval-formula pred-expr))
                         (t (eval-formula pred-expr))))
                 ;; :key キーワード引数を探す
                 (key-pos (position :key args :test #'(lambda (k x) 
                                                        (and (symbolp x)
                                                             (string-equal (symbol-name x) "KEY")))))
                 (key-fn (when key-pos
                           (let ((key-expr (nth (1+ key-pos) args)))
                             (cond
                               ((and (listp key-expr) (eq (car key-expr) 'function))
                                (get-lisp-function (symbol-name (cadr key-expr))))
                               ((and (listp key-expr)
                                     (string-equal (symbol-name (car key-expr)) "LAMBDA"))
                                (eval-formula key-expr))
                               ;; :key :age のようなキーワードアクセス
                               ((keywordp key-expr)
                                (lambda (x) (getf x key-expr)))
                               (t (eval-formula key-expr)))))))
            (if (functionp pred)
                (if key-fn
                    (sort (copy-seq seq) pred :key key-fn)
                    (sort (copy-seq seq) pred))
                (format nil "ERR: not a function"))))
         ;; STABLE-SORT（非破壊的、:key対応）
         ((string-equal op-name "STABLE-SORT")
          (let* ((args (cdr expr))
                 (seq (eval-formula (first args)))
                 (pred-expr (second args))
                 (pred (cond
                         ((null pred-expr) #'<)
                         ((and (listp pred-expr) (eq (car pred-expr) 'function))
                          (get-lisp-function (symbol-name (cadr pred-expr))))
                         ((and (listp pred-expr)
                               (string-equal (symbol-name (car pred-expr)) "LAMBDA"))
                          (eval-formula pred-expr))
                         (t (eval-formula pred-expr))))
                 (key-pos (position :key args :test #'(lambda (k x)
                                                        (and (symbolp x)
                                                             (string-equal (symbol-name x) "KEY")))))
                 (key-fn (when key-pos
                           (let ((key-expr (nth (1+ key-pos) args)))
                             (cond
                               ((and (listp key-expr) (eq (car key-expr) 'function))
                                (get-lisp-function (symbol-name (cadr key-expr))))
                               ((and (listp key-expr)
                                     (string-equal (symbol-name (car key-expr)) "LAMBDA"))
                                (eval-formula key-expr))
                               ((keywordp key-expr)
                                (lambda (x) (getf x key-expr)))
                               (t (eval-formula key-expr)))))))
            (if (functionp pred)
                (if key-fn
                    (stable-sort (copy-seq seq) pred :key key-fn)
                    (stable-sort (copy-seq seq) pred))
                (format nil "ERR: not a function"))))
         ;; LIST（特別扱い：リストを作成）
         ((string-equal op-name "LIST")
          (mapcar #'eval-formula (cdr expr)))
         ;; QUOTE
         ((string-equal op-name "QUOTE")
          (cadr expr))
         ;; CONCATENATE（型指定付き）
         ((string-equal op-name "CONCATENATE")
          (let ((type (eval-formula (cadr expr)))
                (args (mapcar #'eval-formula (cddr expr))))
            (apply #'concatenate type args)))
         ;; 許可された関数
         ((allowed-function-p op)
          (let ((func (get-lisp-function op-name))
                (args (mapcar #'eval-formula (cdr expr))))
            (if func
                (handler-case (apply func args)
                  (error (e) (format nil "ERR:~A" (type-of e))))
                (format nil "ERR:~A undefined" op-name))))
         ;; 許可されていない関数
         (t (format nil "ERR:~A not allowed" op-name)))))
          ;; その他
          (t expr)))
    ;; 深さカウンタを戻す (v0.7.1)
    (decf *current-eval-depth*)))

;;;; =========================
;;;; 値の表示
;;;; =========================

(defun format-value (val)
  "任意のLisp値を表示用文字列に変換"
  (cond
    ((null val) "")  ; nilは空表示
    ((eq val t) "T")
    ((stringp val) val)
    ((numberp val)
     (if (floatp val)
         (format nil "~,4G" val)  ; 小数は適度な精度で
         (princ-to-string val)))
    ((keywordp val) (format nil ":~A" (symbol-name val)))
    ((symbolp val) (symbol-name val))
    ((listp val) (princ-to-string val))  ; リストは省略せず表示
    (t (princ-to-string val))))

