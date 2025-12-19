;;;; core.lisp
;;;; SSP - セル操作、依存関係、Undo/Redo、ファイルI/O

(in-package :ssexp)

;;;; =========================
;;;; 列幅・行高さ管理
;;;; =========================

(defun init-sizes ()
  "列幅・行高さを初期化"
  (setf *col-widths* (make-array (sheet-cols) :initial-element +default-cell-w+))
  (setf *row-heights* (make-array (sheet-rows) :initial-element +default-cell-h+)))

(defun col-width (x)
  "列xの幅を取得"
  (if (and *col-widths* (< x (length *col-widths*)))
      (aref *col-widths* x)
      +default-cell-w+))

(defun row-height (y)
  "行yの高さを取得"
  (if (and *row-heights* (< y (length *row-heights*)))
      (aref *row-heights* y)
      +default-cell-h+))

(defun set-col-width (x w)
  "列xの幅を設定"
  (when (and *col-widths* (< x (length *col-widths*)))
    (setf (aref *col-widths* x) (max +min-cell-w+ w))))

(defun set-row-height (y h)
  "行yの高さを設定"
  (when (and *row-heights* (< y (length *row-heights*)))
    (setf (aref *row-heights* y) (max +min-cell-h+ h))))

(defun col-left (x)
  "列xの左端X座標を取得"
  (let ((pos +header-w+))
    (dotimes (i x pos)
      (incf pos (col-width i)))))

(defun row-top (y)
  "行yの上端Y座標を取得"
  (let ((pos +header-h+))
    (dotimes (i y pos)
      (incf pos (row-height i)))))

(defun total-width ()
  "全列の合計幅"
  (let ((w +header-w+))
    (dotimes (x (sheet-cols) w)
      (incf w (col-width x)))))

(defun total-height ()
  "全行の合計高さ"
  (let ((h +header-h+))
    (dotimes (y (sheet-rows) h)
      (incf h (row-height y)))))

(defun find-col-at (px)
  "X座標pxから列インデックスを取得（ヘッダー内なら-1）"
  (if (< px +header-w+)
      -1
      (let ((x 0)
            (pos +header-w+))
        (loop while (and (< x (sheet-cols)) (>= px pos))
              do (incf pos (col-width x))
                 (incf x))
        (1- x))))

(defun find-row-at (py)
  "Y座標pyから行インデックスを取得（ヘッダー内なら-1）"
  (if (< py +header-h+)
      -1
      (let ((y 0)
            (pos +header-h+))
        (loop while (and (< y (sheet-rows)) (>= py pos))
              do (incf pos (row-height y))
                 (incf y))
        (1- y))))

(defun near-col-border-p (px tolerance)
  "X座標pxが列境界の近くにあるか判定。境界の列インデックスを返す（なければnil）"
  (let ((pos +header-w+))
    (dotimes (x (sheet-cols))
      (incf pos (col-width x))
      (when (<= (- pos tolerance) px (+ pos tolerance))
        (return-from near-col-border-p x))))
  nil)

(defun near-row-border-p (py tolerance)
  "Y座標pyが行境界の近くにあるか判定。境界の行インデックスを返す（なければnil）"
  (let ((pos +header-h+))
    (dotimes (y (sheet-rows))
      (incf pos (row-height y))
      (when (<= (- pos tolerance) py (+ pos tolerance))
        (return-from near-row-border-p y))))
  nil)

;;;; =========================
;;;; 範囲選択
;;;; =========================

(defun clear-selection ()
  "選択をクリア"
  (setf (selection-start-x) nil
        (selection-start-y) nil
        (selection-end-x) nil
        (selection-end-y) nil
        (selecting-p) nil))

(defun has-selection-p ()
  "範囲選択があるか"
  (and (selection-start-x) (selection-start-y) (selection-end-x) (selection-end-y)))

(defun selection-bounds ()
  "選択範囲の境界を返す (min-x min-y max-x max-y)"
  (when (has-selection-p)
    (values (min (selection-start-x) (selection-end-x))
            (min (selection-start-y) (selection-end-y))
            (max (selection-start-x) (selection-end-x))
            (max (selection-start-y) (selection-end-y)))))

(defun cell-in-selection-p (x y)
  "セル(x,y)が選択範囲内にあるか"
  (when (has-selection-p)
    (multiple-value-bind (min-x min-y max-x max-y) (selection-bounds)
      (and (<= min-x x max-x)
           (<= min-y y max-y)))))

;;;; =========================
;;;; 行・列の挿入・削除
;;;; =========================

(defun shift-cell-name-row (name delta)
  "セル名の行番号をdeltaだけシフト。範囲外ならnilを返す"
  (let* ((col-char (char name 0))
         (row-num (parse-integer (subseq name 1)))
         (new-row (+ row-num delta)))
    (if (and (>= new-row 1) (<= new-row (sheet-rows)))
        (format nil "~a~d" col-char new-row)
        nil)))

(defun shift-cell-name-col (name delta)
  "セル名の列をdeltaだけシフト。範囲外ならnilを返す"
  (let* ((col-char (char name 0))
         (col-idx (- (char-code (char-upcase col-char)) (char-code #\A)))
         (new-col (+ col-idx delta))
         (row-str (subseq name 1)))
    (if (and (>= new-col 0) (< new-col (sheet-cols)))
        (format nil "~a~a" (code-char (+ (char-code #\A) new-col)) row-str)
        nil)))

;;; データ存在チェック
(defun row-has-data-p (row-idx)
  "指定行にデータ（値または数式）があるかチェック"
  (loop for x from 0 below (sheet-cols)
        for cell = (get-cell-raw (cell-name x row-idx))
        thereis (and cell (or (cell-value cell) (cell-formula cell)))))

(defun col-has-data-p (col-idx)
  "指定列にデータ（値または数式）があるかチェック"
  (loop for y from 0 below (sheet-rows)
        for cell = (get-cell-raw (cell-name col-idx y))
        thereis (and cell (or (cell-value cell) (cell-formula cell)))))

;;; 確認ダイアログ
(defun confirm-dialog (title message)
  "確認ダイアログを表示。OKならt、キャンセルならnilを返す"
  ;; tk_messageBoxの結果を直接取得
  (format-wish "senddatastring [tk_messageBox -type okcancel -icon warning -title {~a} -message {~a}]"
               title message)
  (string= (ltk::read-data) "ok"))

;;; 数式参照の更新（全セル対象）
;;; セル位置（cell-row, cell-col）は移動後の位置
;;; 移動前の位置を逆算して補正を行う

(defun rel-symbol-p (sym)
  "シンボルがREL（パッケージ不問）かチェック"
  (and (symbolp sym)
       (string-equal (symbol-name sym) "REL")))

(defun rel-range-symbol-p (sym)
  "シンボルがREL-RANGE（パッケージ不問）かチェック"
  (and (symbolp sym)
       (string-equal (symbol-name sym) "REL-RANGE")))

(defun update-formula-ref-for-row-insert (formula at-row cell-row cell-col)
  "行挿入時の数式参照更新。
   - 絶対参照: at-row以降の行参照を+1
   - 相対参照(rel): 移動前の参照先がat-rowより前なら補正
   - 相対範囲(rel-range): 同様に補正
   注: cell-rowは移動後の位置"
  (cond
    ((null formula) nil)
    ((numberp formula) formula)
    ((stringp formula) formula)
    ((keywordp formula) formula)
    ((symbolp formula)
     (let ((name (symbol-name formula)))
       (if (and (>= (length name) 2)
                (alpha-char-p (char name 0))
                (every #'digit-char-p (subseq name 1)))
           (let* ((row-num (parse-integer (subseq name 1)))
                  (row-idx (1- row-num)))
             (if (>= row-idx at-row)
                 ;; 挿入位置以降なら+1
                 (let ((new-name (shift-cell-name-row name 1)))
                   (if new-name (intern new-name :ssexp) formula))
                 formula))
           formula)))
    ((listp formula)
     (cond
       ;; REL の特別処理
       ((and (rel-symbol-p (car formula))
             (= (length formula) 3)
             (numberp (second formula))
             (numberp (third formula)))
        (let ((row-offset (second formula))
              (col-offset (third formula)))
          (cond
            ;; セルが移動した（現在at-rowより下にある）
            ((> cell-row at-row)
             (let* ((orig-cell-row (1- cell-row))  ; 移動前の位置
                    (orig-target-row (+ orig-cell-row row-offset)))
               (if (< orig-target-row at-row)
                   ;; 参照先は移動しなかった、オフセットを調整
                   (list 'rel (1- row-offset) col-offset)
                   ;; 参照先も移動した、オフセットはそのまま
                   (list 'rel row-offset col-offset))))
            ;; セルが移動していない
            ((< cell-row at-row)
             (let ((target-row (+ cell-row row-offset)))
               (if (>= target-row at-row)
                   ;; 参照先が移動した、オフセットを調整
                   (list 'rel (1+ row-offset) col-offset)
                   ;; 参照先も移動しなかった、オフセットはそのまま
                   (list 'rel row-offset col-offset))))
            ;; cell-row == at-row は挿入された空セル
            (t formula))))
       ;; REL-RANGE の特別処理
       ((and (rel-range-symbol-p (car formula))
             (= (length formula) 5)
             (every #'numberp (cdr formula)))
        (let ((start-row-off (second formula))
              (start-col-off (third formula))
              (end-row-off (fourth formula))
              (end-col-off (fifth formula)))
          (cond
            ((> cell-row at-row)
             (let* ((orig-cell-row (1- cell-row))
                    (orig-start-row (+ orig-cell-row start-row-off))
                    (orig-end-row (+ orig-cell-row end-row-off)))
               (list 'rel-range
                     (if (< orig-start-row at-row) (1- start-row-off) start-row-off)
                     start-col-off
                     (if (< orig-end-row at-row) (1- end-row-off) end-row-off)
                     end-col-off)))
            ((< cell-row at-row)
             (let ((start-target (+ cell-row start-row-off))
                   (end-target (+ cell-row end-row-off)))
               (list 'rel-range
                     (if (>= start-target at-row) (1+ start-row-off) start-row-off)
                     start-col-off
                     (if (>= end-target at-row) (1+ end-row-off) end-row-off)
                     end-col-off)))
            (t formula))))
       ;; 通常のリスト処理
       (t (mapcar (lambda (x) (update-formula-ref-for-row-insert x at-row cell-row cell-col)) formula))))
    (t formula)))

(defun update-formula-ref-for-row-delete (formula at-row cell-row cell-col)
  "行削除時の数式参照更新。
   - 絶対参照: at-rowへの参照は#REF!、at-rowより後は-1
   - 相対参照(rel): 参照先が削除行なら#REF!、移動前の参照先がat-rowより前なら補正
   - 相対範囲(rel-range): 同様に補正
   注: cell-rowは移動後の位置"
  (cond
    ((null formula) nil)
    ((numberp formula) formula)
    ((stringp formula) formula)
    ((keywordp formula) formula)
    ((symbolp formula)
     (let ((name (symbol-name formula)))
       (if (and (>= (length name) 2)
                (alpha-char-p (char name 0))
                (every #'digit-char-p (subseq name 1)))
           (let* ((row-num (parse-integer (subseq name 1)))
                  (row-idx (1- row-num)))
             (cond
               ((= row-idx at-row)
                (intern "#REF!" :ssexp))
               ((> row-idx at-row)
                (let ((new-name (shift-cell-name-row name -1)))
                  (if new-name (intern new-name :ssexp) formula)))
               (t formula)))
           formula)))
    ((listp formula)
     (cond
       ;; REL の特別処理
       ((and (rel-symbol-p (car formula))
             (= (length formula) 3)
             (numberp (second formula))
             (numberp (third formula)))
        (let ((row-offset (second formula))
              (col-offset (third formula)))
          (cond
            ;; セルが移動した（削除後、at-row以降にある = 移動前はat-row+1以降）
            ((>= cell-row at-row)
             (let* ((orig-cell-row (1+ cell-row))  ; 移動前の位置
                    (orig-target-row (+ orig-cell-row row-offset)))
               (cond
                 ((= orig-target-row at-row)
                  '(quote |#REF!|))
                 ((< orig-target-row at-row)
                  ;; 参照先は移動しなかった、オフセットを調整
                  (list 'rel (1+ row-offset) col-offset))
                 ;; 参照先も移動した、オフセットはそのまま
                 (t (list 'rel row-offset col-offset)))))
            ;; セルが移動していない
            (t
             (let ((target-row (+ cell-row row-offset)))
               (cond
                 ((= target-row at-row)
                  '(quote |#REF!|))
                 ((> target-row at-row)
                  ;; 参照先が移動した、オフセットを調整
                  (list 'rel (1- row-offset) col-offset))
                 (t (list 'rel row-offset col-offset))))))))
       ;; REL-RANGE の特別処理
       ((and (rel-range-symbol-p (car formula))
             (= (length formula) 5)
             (every #'numberp (cdr formula)))
        (let ((start-row-off (second formula))
              (start-col-off (third formula))
              (end-row-off (fourth formula))
              (end-col-off (fifth formula)))
          (cond
            ((>= cell-row at-row)
             (let* ((orig-cell-row (1+ cell-row))
                    (orig-start-row (+ orig-cell-row start-row-off))
                    (orig-end-row (+ orig-cell-row end-row-off)))
               (if (or (= orig-start-row at-row) (= orig-end-row at-row))
                   '(quote |#REF!|)
                   (list 'rel-range
                         (if (< orig-start-row at-row) (1+ start-row-off) start-row-off)
                         start-col-off
                         (if (< orig-end-row at-row) (1+ end-row-off) end-row-off)
                         end-col-off))))
            (t
             (let ((start-target (+ cell-row start-row-off))
                   (end-target (+ cell-row end-row-off)))
               (if (or (= start-target at-row) (= end-target at-row))
                   '(quote |#REF!|)
                   (list 'rel-range
                         (if (> start-target at-row) (1- start-row-off) start-row-off)
                         start-col-off
                         (if (> end-target at-row) (1- end-row-off) end-row-off)
                         end-col-off)))))))
       ;; 通常のリスト処理
       (t (mapcar (lambda (x) (update-formula-ref-for-row-delete x at-row cell-row cell-col)) formula))))
    (t formula)))

(defun update-formula-ref-for-col-insert (formula at-col cell-row cell-col)
  "列挿入時の数式参照更新。
   - 絶対参照: at-col以降の列参照を+1
   - 相対参照(rel): 移動前の参照先がat-colより前なら補正
   - 相対範囲(rel-range): 同様に補正
   注: cell-colは移動後の位置"
  (cond
    ((null formula) nil)
    ((numberp formula) formula)
    ((stringp formula) formula)
    ((keywordp formula) formula)
    ((symbolp formula)
     (let ((name (symbol-name formula)))
       (if (and (>= (length name) 2)
                (alpha-char-p (char name 0))
                (every #'digit-char-p (subseq name 1)))
           (let* ((col-idx (- (char-code (char-upcase (char name 0))) (char-code #\A))))
             (if (>= col-idx at-col)
                 ;; 挿入位置以降なら+1
                 (let ((new-name (shift-cell-name-col name 1)))
                   (if new-name (intern new-name :ssexp) formula))
                 formula))
           formula)))
    ((listp formula)
     (cond
       ;; REL の特別処理
       ((and (rel-symbol-p (car formula))
             (= (length formula) 3)
             (numberp (second formula))
             (numberp (third formula)))
        (let ((row-offset (second formula))
              (col-offset (third formula)))
          (cond
            ;; セルが移動した（現在at-colより右にある）
            ((> cell-col at-col)
             (let* ((orig-cell-col (1- cell-col))  ; 移動前の位置
                    (orig-target-col (+ orig-cell-col col-offset)))
               (if (< orig-target-col at-col)
                   ;; 参照先は移動しなかった、オフセットを調整
                   (list 'rel row-offset (1- col-offset))
                   ;; 参照先も移動した、オフセットはそのまま
                   (list 'rel row-offset col-offset))))
            ;; セルが移動していない
            ((< cell-col at-col)
             (let ((target-col (+ cell-col col-offset)))
               (if (>= target-col at-col)
                   ;; 参照先が移動した、オフセットを調整
                   (list 'rel row-offset (1+ col-offset))
                   ;; 参照先も移動しなかった、オフセットはそのまま
                   (list 'rel row-offset col-offset))))
            ;; cell-col == at-col は挿入された空セル
            (t formula))))
       ;; REL-RANGE の特別処理
       ((and (rel-range-symbol-p (car formula))
             (= (length formula) 5)
             (every #'numberp (cdr formula)))
        (let ((start-row-off (second formula))
              (start-col-off (third formula))
              (end-row-off (fourth formula))
              (end-col-off (fifth formula)))
          (cond
            ((> cell-col at-col)
             (let* ((orig-cell-col (1- cell-col))
                    (orig-start-col (+ orig-cell-col start-col-off))
                    (orig-end-col (+ orig-cell-col end-col-off)))
               (list 'rel-range
                     start-row-off
                     (if (< orig-start-col at-col) (1- start-col-off) start-col-off)
                     end-row-off
                     (if (< orig-end-col at-col) (1- end-col-off) end-col-off))))
            ((< cell-col at-col)
             (let ((start-target (+ cell-col start-col-off))
                   (end-target (+ cell-col end-col-off)))
               (list 'rel-range
                     start-row-off
                     (if (>= start-target at-col) (1+ start-col-off) start-col-off)
                     end-row-off
                     (if (>= end-target at-col) (1+ end-col-off) end-col-off))))
            (t formula))))
       ;; 通常のリスト処理
       (t (mapcar (lambda (x) (update-formula-ref-for-col-insert x at-col cell-row cell-col)) formula))))
    (t formula)))

(defun update-formula-ref-for-col-delete (formula at-col cell-row cell-col)
  "列削除時の数式参照更新。
   - 絶対参照: at-colへの参照は#REF!、at-colより後は-1
   - 相対参照(rel): 参照先が削除列なら#REF!、移動前の参照先がat-colより前なら補正
   - 相対範囲(rel-range): 同様に補正
   注: cell-colは移動後の位置"
  (cond
    ((null formula) nil)
    ((numberp formula) formula)
    ((stringp formula) formula)
    ((keywordp formula) formula)
    ((symbolp formula)
     (let ((name (symbol-name formula)))
       (if (and (>= (length name) 2)
                (alpha-char-p (char name 0))
                (every #'digit-char-p (subseq name 1)))
           (let* ((col-idx (- (char-code (char-upcase (char name 0))) (char-code #\A))))
             (cond
               ((= col-idx at-col)
                (intern "#REF!" :ssexp))
               ((> col-idx at-col)
                (let ((new-name (shift-cell-name-col name -1)))
                  (if new-name (intern new-name :ssexp) formula)))
               (t formula)))
           formula)))
    ((listp formula)
     (cond
       ;; REL の特別処理
       ((and (rel-symbol-p (car formula))
             (= (length formula) 3)
             (numberp (second formula))
             (numberp (third formula)))
        (let ((row-offset (second formula))
              (col-offset (third formula)))
          (cond
            ;; セルが移動した（削除後、at-col以降にある = 移動前はat-col+1以降）
            ((>= cell-col at-col)
             (let* ((orig-cell-col (1+ cell-col))  ; 移動前の位置
                    (orig-target-col (+ orig-cell-col col-offset)))
               (cond
                 ((= orig-target-col at-col)
                  '(quote |#REF!|))
                 ((< orig-target-col at-col)
                  ;; 参照先は移動しなかった、オフセットを調整
                  (list 'rel row-offset (1+ col-offset)))
                 ;; 参照先も移動した、オフセットはそのまま
                 (t (list 'rel row-offset col-offset)))))
            ;; セルが移動していない
            (t
             (let ((target-col (+ cell-col col-offset)))
               (cond
                 ((= target-col at-col)
                  '(quote |#REF!|))
                 ((> target-col at-col)
                  ;; 参照先が移動した、オフセットを調整
                  (list 'rel row-offset (1- col-offset)))
                 (t (list 'rel row-offset col-offset))))))))
       ;; REL-RANGE の特別処理
       ((and (rel-range-symbol-p (car formula))
             (= (length formula) 5)
             (every #'numberp (cdr formula)))
        (let ((start-row-off (second formula))
              (start-col-off (third formula))
              (end-row-off (fourth formula))
              (end-col-off (fifth formula)))
          (cond
            ((>= cell-col at-col)
             (let* ((orig-cell-col (1+ cell-col))
                    (orig-start-col (+ orig-cell-col start-col-off))
                    (orig-end-col (+ orig-cell-col end-col-off)))
               (if (or (= orig-start-col at-col) (= orig-end-col at-col))
                   '(quote |#REF!|)
                   (list 'rel-range
                         start-row-off
                         (if (< orig-start-col at-col) (1+ start-col-off) start-col-off)
                         end-row-off
                         (if (< orig-end-col at-col) (1+ end-col-off) end-col-off)))))
            (t
             (let ((start-target (+ cell-col start-col-off))
                   (end-target (+ cell-col end-col-off)))
               (if (or (= start-target at-col) (= end-target at-col))
                   '(quote |#REF!|)
                   (list 'rel-range
                         start-row-off
                         (if (> start-target at-col) (1- start-col-off) start-col-off)
                         end-row-off
                         (if (> end-target at-col) (1- end-col-off) end-col-off))))))))
       ;; 通常のリスト処理
       (t (mapcar (lambda (x) (update-formula-ref-for-col-delete x at-col cell-row cell-col)) formula))))
    (t formula)))

;;; 全セルの数式参照を更新
(defun update-all-formulas-with-position (update-fn)
  "全セルの数式を更新関数で更新。update-fnは (formula row col) を受け取る"
  (map-sheet (lambda (name cell)
               (when (cell-formula cell)
                 (let* ((coords (parse-cell-name name))
                        (col (first coords))
                        (row (second coords)))
                   (setf (cell-formula cell)
                         (funcall update-fn (cell-formula cell) row col)))))))

(defun insert-row (at-row &optional force)
  "指定行に空行を挿入（at-row以降を下にシフト、最終行は破棄）
   force=tの場合は確認なしで実行"
  (when (and (>= at-row 0) (< at-row (sheet-rows)))
    ;; 最終行にデータがあるかチェック
    (when (and (not force) (row-has-data-p (1- (sheet-rows))))
      (unless (confirm-dialog "Insert Row" 
                              (format nil "Row ~a contains data and will be deleted. Continue?" (sheet-rows)))
        (return-from insert-row nil)))
    ;; 最終行のセルを削除
    (loop for x from 0 below (sheet-cols) do
      (remove-cell (cell-name x (1- (sheet-rows)))))
    ;; 下から上に向かってセルを移動（最終行-1から挿入行まで）
    (loop for y from (- (sheet-rows) 2) downto at-row do
      (loop for x from 0 below (sheet-cols) do
        (let* ((src-name (cell-name x y))
               (dst-name (cell-name x (1+ y)))
               (src-cell (get-cell-raw src-name)))
          (when src-cell
            ;; セルを移動（数式はまだ更新しない）
            (set-cell-value dst-name src-cell)
            (remove-cell src-name)))))
    ;; 全セルの数式参照を更新（挿入位置以降の参照を+1）
    (update-all-formulas-with-position 
     (lambda (f row col) (update-formula-ref-for-row-insert f at-row row col)))
    ;; 行高さ配列を更新（シフト）
    (when *row-heights*
      (loop for i from (- (sheet-rows) 2) downto at-row do
        (setf (aref *row-heights* (1+ i)) (aref *row-heights* i)))
      (setf (aref *row-heights* at-row) +default-cell-h+))
    ;; 全セルを再評価
    (recalculate-all)
    ;; 依存関係を再構築
    (rebuild-all-dependencies)
    t))

(defun delete-row (at-row)
  "指定行を削除（at-row以降を上にシフト、最終行は空になる）"
  (when (and (>= at-row 0) (< at-row (sheet-rows)))
    ;; 削除行のセルをクリア
    (loop for x from 0 below (sheet-cols) do
      (remove-cell (cell-name x at-row)))
    ;; 上にシフト
    (loop for y from (1+ at-row) below (sheet-rows) do
      (loop for x from 0 below (sheet-cols) do
        (let* ((src-name (cell-name x y))
               (dst-name (cell-name x (1- y)))
               (src-cell (get-cell-raw src-name)))
          (when src-cell
            ;; セルを移動（数式はまだ更新しない）
            (set-cell-value dst-name src-cell)
            (remove-cell src-name)))))
    ;; 全セルの数式参照を更新（削除行への参照は#REF!、それより後は-1）
    (update-all-formulas-with-position 
     (lambda (f row col) (update-formula-ref-for-row-delete f at-row row col)))
    ;; 行高さ配列を更新（シフト）
    (when *row-heights*
      (loop for i from at-row below (1- (sheet-rows)) do
        (setf (aref *row-heights* i) (aref *row-heights* (1+ i))))
      (setf (aref *row-heights* (1- (sheet-rows))) +default-cell-h+))
    ;; 全セルを再評価
    (recalculate-all)
    ;; 依存関係を再構築
    (rebuild-all-dependencies)
    t))

(defun insert-col (at-col &optional force)
  "指定列に空列を挿入（at-col以降を右にシフト、最終列は破棄）
   force=tの場合は確認なしで実行"
  (when (and (>= at-col 0) (< at-col (sheet-cols)))
    ;; 最終列にデータがあるかチェック
    (when (and (not force) (col-has-data-p (1- (sheet-cols))))
      (let ((col-name (string (code-char (+ (char-code #\A) (1- (sheet-cols)))))))
        (unless (confirm-dialog "Insert Column"
                                (format nil "Column ~a contains data and will be deleted. Continue?" col-name))
          (return-from insert-col nil))))
    ;; 最終列のセルを削除
    (loop for y from 0 below (sheet-rows) do
      (remove-cell (cell-name (1- (sheet-cols)) y)))
    ;; 右から左に向かってセルを移動（最終列-1から挿入列まで）
    (loop for x from (- (sheet-cols) 2) downto at-col do
      (loop for y from 0 below (sheet-rows) do
        (let* ((src-name (cell-name x y))
               (dst-name (cell-name (1+ x) y))
               (src-cell (get-cell-raw src-name)))
          (when src-cell
            ;; セルを移動（数式はまだ更新しない）
            (set-cell-value dst-name src-cell)
            (remove-cell src-name)))))
    ;; 全セルの数式参照を更新（挿入位置以降の参照を+1）
    (update-all-formulas-with-position 
     (lambda (f row col) (update-formula-ref-for-col-insert f at-col row col)))
    ;; 列幅配列を更新（シフト）
    (when *col-widths*
      (loop for i from (- (sheet-cols) 2) downto at-col do
        (setf (aref *col-widths* (1+ i)) (aref *col-widths* i)))
      (setf (aref *col-widths* at-col) +default-cell-w+))
    ;; 全セルを再評価
    (recalculate-all)
    ;; 依存関係を再構築
    (rebuild-all-dependencies)
    t))

(defun delete-col (at-col)
  "指定列を削除（at-col以降を左にシフト、最終列は空になる）"
  (when (and (>= at-col 0) (< at-col (sheet-cols)))
    ;; 削除列のセルをクリア
    (loop for y from 0 below (sheet-rows) do
      (remove-cell (cell-name at-col y)))
    ;; 左にシフト
    (loop for x from (1+ at-col) below (sheet-cols) do
      (loop for y from 0 below (sheet-rows) do
        (let* ((src-name (cell-name x y))
               (dst-name (cell-name (1- x) y))
               (src-cell (get-cell-raw src-name)))
          (when src-cell
            ;; セルを移動（数式はまだ更新しない）
            (set-cell-value dst-name src-cell)
            (remove-cell src-name)))))
    ;; 全セルの数式参照を更新（削除列への参照は#REF!、それより後は-1）
    (update-all-formulas-with-position 
     (lambda (f row col) (update-formula-ref-for-col-delete f at-col row col)))
    ;; 列幅配列を更新（シフト）
    (when *col-widths*
      (loop for i from at-col below (1- (sheet-cols)) do
        (setf (aref *col-widths* i) (aref *col-widths* (1+ i))))
      (setf (aref *col-widths* (1- (sheet-cols))) +default-cell-w+))
    ;; 全セルを再評価
    (recalculate-all)
    ;; 依存関係を再構築
    (rebuild-all-dependencies)
    t))

(defun rebuild-all-dependencies ()
  "全セルの依存関係を再構築"
  (clear-dependencies)
  (map-sheet (lambda (name cell)
               (when (cell-formula cell)
                 (let* ((coords (parse-cell-name name))
                        (col (first coords))
                        (row (second coords))
                        (refs (extract-references (cell-formula cell) row col)))
                   (update-dependencies name refs))))))

(defun recalculate-all ()
  "全セルの数式を再評価"
  (map-sheet (lambda (name cell)
               (when (cell-formula cell)
                 (let* ((coords (parse-cell-name name))
                        (col (first coords))
                        (row (second coords)))
                   ;; 動的変数を設定して評価
                   (setf (eval-col) col (eval-row) row)
                   (let ((*eval-stack* (list name)))
                     (setf (cell-value cell)
                           (handler-case
                               (eval-formula (cell-formula cell))
                             (error (e)
                               (format nil "#評価:~a" (type-of e)))))))))))

;;;; =========================
;;;; コピー＆ペースト
;;;; ===========================

(defun copy-selection ()
  "選択範囲をクリップボードにコピー"
  (when (has-selection-p)
    (multiple-value-bind (min-x min-y max-x max-y) (selection-bounds)
      (let ((cells nil)
            (rows (1+ (- max-y min-y)))
            (cols (1+ (- max-x min-x))))
        ;; セルデータを収集
        (loop for y from min-y to max-y do
          (loop for x from min-x to max-x do
            (let ((cell (get-cell (cell-name x y))))
              (push (list (cell-value cell) (cell-formula cell)) cells))))
        (set-clipboard (nreverse cells) rows cols)))))

(defun paste-clipboard ()
  "クリップボードの内容をカーソル位置にペースト"
  (when (clipboard-cells)
    (let ((idx 0)
          (clip (clipboard-cells))
          (pasted-cells nil)
          (before-snapshots nil)
          (after-snapshots nil))
      ;; まず全てのセルに値と数式を設定
      (loop for dy from 0 below (clipboard-rows) do
        (loop for dx from 0 below (clipboard-cols) do
          (let* ((x (+ (cursor-x) dx))
                 (y (+ (cursor-y) dy)))
            (when (and (< x (sheet-cols)) (< y (sheet-rows)))
              (let* ((name (cell-name x y))
                     (cell (get-cell name))
                     (data (nth idx clip))
                     (formula (second data)))
                ;; 変更前の状態を保存
                (push (make-cell-snapshot name) before-snapshots)
                ;; 数式がある場合は再評価
                (if formula
                    (progn
                      (setf (eval-col) x (eval-row) y)
                      (let ((*eval-stack* (list name)))
                        (handler-case
                            (setf (cell-value cell) (eval-formula formula))
                          (error (e)
                            (setf (cell-value cell) (format nil "ERR: ~a" e)))))
                      (setf (cell-formula cell) formula)
                      (update-dependencies name (extract-references formula y x)))
                    (progn
                      (setf (cell-value cell) (first data)
                            (cell-formula cell) nil)
                      (update-dependencies name nil)))
                ;; 変更後の状態を保存
                (push (make-cell-snapshot name) after-snapshots)
                (push name pasted-cells))))
          (incf idx)))
      ;; Undo履歴に記録
      (when pasted-cells
        (record-multi-change (nreverse before-snapshots) (nreverse after-snapshots)))
      ;; 貼り付けたセルの依存元を再計算
      (dolist (name (nreverse pasted-cells))
        (recalc-dependents name)))))

(defun clear-selection-cells ()
  "選択範囲のセルをクリア（NILを設定）し、依存元を再計算"
  (let ((cleared-cells nil)
        (before-snapshots nil)
        (after-snapshots nil))
    (if (has-selection-p)
        ;; 範囲選択がある場合
        (multiple-value-bind (min-x min-y max-x max-y) (selection-bounds)
          (loop for y from min-y to max-y do
            (loop for x from min-x to max-x do
              (let* ((name (cell-name x y))
                     (cell (get-cell name)))
                ;; 変更前の状態を保存
                (push (make-cell-snapshot name) before-snapshots)
                (setf (cell-value cell) nil
                      (cell-formula cell) nil)
                (update-dependencies name nil)
                ;; 変更後の状態を保存
                (push (make-cell-snapshot name) after-snapshots)
                (push name cleared-cells)))))
        ;; 範囲選択がない場合はカーソル位置のみ
        (let* ((name (cell-name (cursor-x) (cursor-y)))
               (cell (get-cell name)))
          (push (make-cell-snapshot name) before-snapshots)
          (setf (cell-value cell) nil
                (cell-formula cell) nil)
          (update-dependencies name nil)
          (push (make-cell-snapshot name) after-snapshots)
          (push name cleared-cells)))
    ;; Undo履歴に記録
    (when cleared-cells
      (record-multi-change (nreverse before-snapshots) (nreverse after-snapshots)))
    ;; 全ての削除されたセルの依存元を再計算
    (dolist (name cleared-cells)
      (recalc-dependents name))))

;;;; =========================
;;;; システムクリップボード
;;;; =========================

(defun get-system-clipboard ()
  "システムクリップボードからテキストを取得"
  (handler-case
      (ltk::clipboard-get)
    (error () nil)))

(defun set-system-clipboard (text)
  "システムクリップボードにテキストを設定"
  (format-wish "clipboard clear")
  (format-wish "clipboard append {~a}" text))

(defun split-string (string separator)
  "文字列を区切り文字で分割"
  (loop for start = 0 then (1+ pos)
        for pos = (position separator string :start start)
        collect (subseq string start (or pos (length string)))
        while pos))

(defun format-cell-for-clipboard (val formula)
  "セル値をクリップボード用文字列に変換"
  (let ((*package* (find-package :ssexp)))  ; パッケージプレフィックスなしで表示
    (cond
      ;; 数式があればそれを優先
      (formula (format nil "=~S" formula))
      ;; NILは空文字列
      ((null val) "")
      ;; 文字列はそのまま
      ((stringp val) val)
      ;; その他はprinc形式
      (t (princ-to-string val)))))

(defun selection-to-tsv ()
  "選択範囲をTSV文字列に変換"
  (if (has-selection-p)
      (multiple-value-bind (min-x min-y max-x max-y) (selection-bounds)
        (with-output-to-string (s)
          (loop for y from min-y to max-y do
            (loop for x from min-x to max-x do
              (let ((cell (get-cell (cell-name x y))))
                (when (> x min-x) (write-char #\Tab s))
                (write-string (format-cell-for-clipboard 
                               (cell-value cell) 
                               (cell-formula cell)) s)))
            (when (< y max-y) (terpri s)))))
      ;; 選択範囲がない場合はカーソル位置のセル
      (let ((cell (current-cell)))
        (format-cell-for-clipboard (cell-value cell) (cell-formula cell)))))

(defun copy-to-system-clipboard ()
  "選択範囲をシステムクリップボードにコピー"
  (let ((text (selection-to-tsv)))
    (set-system-clipboard text)
    ;; 内部クリップボードにもコピー
    (copy-selection)))

(defun parse-clipboard-value (text)
  "クリップボードのテキストをセル値に変換"
  (let ((trimmed (string-trim '(#\Space #\Tab #\Return) text)))
    (cond
      ;; 空文字列 → NIL
      ((string= trimmed "") nil)
      ;; =で始まる → 数式として処理
      ((and (> (length trimmed) 0) (char= (char trimmed 0) #\=))
       (handler-case
           (let* ((*package* (find-package :ssexp))  ; SSEXPパッケージで読み込み
                  (form (read-from-string (subseq trimmed 1)))
                  (value (eval-formula form)))
             (values value form))
         (error () (values trimmed nil))))
      ;; 数値を試す
      (t (let* ((*package* (find-package :ssexp))
                (num (ignore-errors (read-from-string trimmed))))
           (if (numberp num)
               num
               trimmed))))))

(defun paste-from-system-clipboard ()
  "システムクリップボードから貼り付け"
  (let ((text (get-system-clipboard))
        (pasted-cells nil)
        (before-snapshots nil)
        (after-snapshots nil))
    (when (and text (> (length text) 0))
      ;; 行で分割
      (let* ((lines (split-string text #\Newline))
             ;; 空行を末尾から除去
             (lines (loop for l in lines
                         for i from 0
                         while (or (< i (1- (length lines)))
                                  (> (length l) 0))
                         collect l)))
        (if (and (= (length lines) 1)
                 (not (find #\Tab (first lines))))
            ;; 単一値の場合
            (let* ((name (cell-name (cursor-x) (cursor-y)))
                   (cell (get-cell name)))
              ;; 変更前の状態を保存
              (push (make-cell-snapshot name) before-snapshots)
              ;; 評価位置を設定
              (setf (eval-col) (cursor-x) (eval-row) (cursor-y))
              (multiple-value-bind (val form) 
                  (parse-clipboard-value (first lines))
                (setf (cell-value cell) val
                      (cell-formula cell) form)
                (if form
                    (update-dependencies name (extract-references form (cursor-y) (cursor-x)))
                    (update-dependencies name nil))
                ;; 変更後の状態を保存
                (push (make-cell-snapshot name) after-snapshots)
                (push name pasted-cells)))
            ;; 複数セル（TSV形式）の場合
            (loop for line in lines
                  for dy from 0 do
              (loop for col-text in (split-string line #\Tab)
                    for dx from 0 do
                (let ((x (+ (cursor-x) dx))
                      (y (+ (cursor-y) dy)))
                  (when (and (< x (sheet-cols)) (< y (sheet-rows)))
                    (let* ((name (cell-name x y))
                           (cell (get-cell name)))
                      ;; 変更前の状態を保存
                      (push (make-cell-snapshot name) before-snapshots)
                      ;; 評価位置を設定
                      (setf (eval-col) x (eval-row) y)
                      (multiple-value-bind (val form)
                          (parse-clipboard-value col-text)
                        (setf (cell-value cell) val
                              (cell-formula cell) form)
                        (if form
                            (update-dependencies name (extract-references form y x))
                            (update-dependencies name nil))
                        ;; 変更後の状態を保存
                        (push (make-cell-snapshot name) after-snapshots)
                        (push name pasted-cells))))))))))
    ;; Undo履歴に記録
    (when pasted-cells
      (record-multi-change (nreverse before-snapshots) (nreverse after-snapshots)))
    ;; 貼り付けたセルの依存元を再計算
    (dolist (name (nreverse pasted-cells))
      (recalc-dependents name))))

;;;; =========================
;;;; 依存関係管理と再計算
;;;; =========================

(defun extract-references (formula row col)
  "数式から参照しているセル名のリストを抽出"
  (let ((refs nil))
    (labels ((sym-eq (sym name)
               "シンボル名を文字列比較"
               (and (symbolp sym)
                    (string-equal (symbol-name sym) name)))
             (walk (expr)
               (cond
                 ;; セル参照シンボル（A1形式）
                 ((and (symbolp expr)
                       (not (keywordp expr))
                       (let ((name (symbol-name expr)))
                         (and (>= (length name) 2)
                              (<= (length name) 3)
                              (alpha-char-p (char name 0))
                              (every #'digit-char-p (subseq name 1)))))
                  (pushnew (string-upcase (symbol-name expr)) refs :test #'string-equal))
                 ;; (rel drow dcol) - 相対参照
                 ((and (listp expr)
                       (sym-eq (car expr) "REL")
                       (= (length expr) 3)
                       (numberp (second expr))
                       (numberp (third expr)))
                  (let* ((drow (second expr))
                         (dcol (third expr))
                         (new-row (+ row drow))
                         (new-col (+ col dcol)))
                    (when (and (>= new-row 0) (< new-row (sheet-rows))
                               (>= new-col 0) (< new-col (sheet-cols)))
                      (pushnew (cell-name new-col new-row) refs :test #'string-equal))))
                 ;; (rel-range dr1 dc1 dr2 dc2) - 相対範囲
                 ((and (listp expr)
                       (sym-eq (car expr) "REL-RANGE")
                       (= (length expr) 5))
                  (let* ((dr1 (second expr))
                         (dc1 (third expr))
                         (dr2 (fourth expr))
                         (dc2 (fifth expr)))
                    (when (and (numberp dr1) (numberp dc1)
                               (numberp dr2) (numberp dc2))
                      (let ((r1 (+ row dr1))
                            (c1 (+ col dc1))
                            (r2 (+ row dr2))
                            (c2 (+ col dc2)))
                        (loop for r from (min r1 r2) to (max r1 r2) do
                          (loop for c from (min c1 c2) to (max c1 c2) do
                            (when (and (>= r 0) (< r (sheet-rows))
                                       (>= c 0) (< c (sheet-cols)))
                              (pushnew (cell-name c r) refs :test #'string-equal))))))))
                 ;; (range start end) - 絶対範囲
                 ((and (listp expr)
                       (sym-eq (car expr) "RANGE")
                       (= (length expr) 3))
                  (let ((start (second expr))
                        (end (third expr)))
                    (when (and (symbolp start) (symbolp end))
                      (let* ((start-name (symbol-name start))
                             (end-name (symbol-name end))
                             (c1 (- (char-code (char-upcase (char start-name 0))) (char-code #\A)))
                             (r1 (1- (parse-integer (subseq start-name 1))))
                             (c2 (- (char-code (char-upcase (char end-name 0))) (char-code #\A)))
                             (r2 (1- (parse-integer (subseq end-name 1)))))
                        (loop for r from (min r1 r2) to (max r1 r2) do
                          (loop for c from (min c1 c2) to (max c1 c2) do
                            (pushnew (cell-name c r) refs :test #'string-equal)))))))
                 ;; (cell-at row col) - 行列指定
                 ((and (listp expr)
                       (sym-eq (car expr) "CELL-AT")
                       (>= (length expr) 3))
                  (let ((r (second expr))
                        (c (third expr)))
                    (when (and (numberp r) (or (numberp c) (stringp c)))
                      (let ((actual-col (if (stringp c)
                                           (- (char-code (char-upcase (char c 0))) (char-code #\A))
                                           c))
                            (actual-row (1- r)))
                        (when (and (>= actual-row 0) (< actual-row (sheet-rows))
                                   (>= actual-col 0) (< actual-col (sheet-cols)))
                          (pushnew (cell-name actual-col actual-row) refs :test #'string-equal))))))
                 ;; リストの場合は再帰
                 ((listp expr)
                  (dolist (e expr)
                    (walk e))))))
      (walk formula))
    refs))

(defun update-dependencies (cell-name new-refs)
  "セルの依存関係を更新"
  (let ((old-refs (get-refs cell-name)))
    ;; 古い参照先から自分を削除
    (dolist (ref old-refs)
      (let ((deps (get-dependents ref)))
        (setf (get-dependents ref)
              (remove cell-name deps :test #'string-equal))))
    ;; 新しい参照先を設定
    (setf (get-refs cell-name) new-refs)
    ;; 新しい参照先に自分を追加
    (dolist (ref new-refs)
      (pushnew cell-name (get-dependents ref) :test #'string-equal))))

(defun collect-all-dependents (cell-name)
  "セルに依存する全てのセルを収集（再帰的に）"
  (let ((visited (make-hash-table :test 'equal))
        (result nil))
    (labels ((collect (name)
               (unless (gethash name visited)
                 (setf (gethash name visited) t)
                 (dolist (dep (get-dependents name))
                   (push dep result)
                   (collect dep)))))
      (collect cell-name))
    (nreverse result)))

(defun topological-sort-cells (cells)
  "セルをトポロジカルソート（依存順）"
  (let ((in-degree (make-hash-table :test 'equal))
        (graph (make-hash-table :test 'equal))
        (result nil)
        (queue nil))
    ;; 初期化
    (dolist (c cells)
      (setf (gethash c in-degree) 0)
      (setf (gethash c graph) nil))
    ;; グラフ構築
    (dolist (c cells)
      (dolist (ref (get-refs c))
        (when (member ref cells :test #'string-equal)
          (push c (gethash ref graph))
          (incf (gethash c in-degree)))))
    ;; 入次数0のセルをキューに
    (dolist (c cells)
      (when (zerop (gethash c in-degree))
        (push c queue)))
    ;; BFS
    (loop while queue do
      (let ((current (pop queue)))
        (push current result)
        (dolist (dep (gethash current graph))
          (decf (gethash dep in-degree))
          (when (zerop (gethash dep in-degree))
            (push dep queue)))))
    ;; 結果（依存順）
    (nreverse result)))

(defun recalc-cell (cell-name)
  "単一セルを再計算"
  (let* ((cell (get-cell cell-name))
         (formula (cell-formula cell)))
    (when formula
      (let* ((coords (parse-cell-name cell-name))
             (col (first coords))
             (row (second coords)))
        ;; 評価位置を設定
        (setf (eval-col) col (eval-row) row)
        (let ((*eval-stack* (list cell-name)))
          (handler-case
              (setf (cell-value cell) (eval-formula formula))
            (error (e)
              (let ((msg (princ-to-string e)))
                (if (search "循環参照" msg)
                    (setf (cell-value cell) (format-error-message :circular cell-name))
                    (setf (cell-value cell) (format-error-message :eval msg)))))))))))

(defun parse-cell-name (name)
  "セル名から座標(col row)を取得"
  (let* ((col (- (char-code (char-upcase (char name 0))) (char-code #\A)))
         (row (1- (parse-integer (subseq name 1)))))
    (list col row)))

(defun recalc-dependents (cell-name)
  "セルに依存する全てのセルを再計算"
  (let* ((deps (collect-all-dependents cell-name))
         (sorted (topological-sort-cells deps)))
    (dolist (dep sorted)
      (recalc-cell dep))))

(defun clear-dependencies ()
  "依存関係をクリア"
  (clear-all-refs)
  (clear-all-dependents))

(defun show-dependencies ()
  "依存関係をデバッグ表示"
  (format t "~%=== Refs (セル→参照先) ===~%")
  (map-refs (lambda (k v) (format t "  ~a → ~a~%" k v)))
  (format t "~%=== Dependents (セル→依存元) ===~%")
  (map-dependents (lambda (k v) (format t "  ~a ← ~a~%" k v)))
  (values))

(defun show-cell-deps (cell-name)
  "特定セルの依存関係を表示"
  (format t "~%セル ~a:~%" cell-name)
  (format t "  参照先: ~a~%" (get-refs cell-name))
  (format t "  依存元: ~a~%" (get-dependents cell-name))
  (values))

;;;; =========================
;;;; Undo/Redo 機能
;;;; =========================

;;; 操作タイプ:
;;;   :cell-change  - 単一セルの変更
;;;   :multi-change - 複数セルの変更（ペースト、削除等）

(defun make-cell-snapshot (cell-name)
  "セルの現在状態をスナップショットとして取得"
  (let ((cell (get-cell cell-name)))
    (list :name cell-name
          :value (cell-value cell)
          :formula (cell-formula cell))))

(defun restore-cell-snapshot (snapshot)
  "スナップショットからセルを復元"
  (let* ((name (getf snapshot :name))
         (value (getf snapshot :value))
         (formula (getf snapshot :formula))
         (cell (get-cell name)))
    (setf (cell-value cell) value
          (cell-formula cell) formula)
    ;; 依存関係を再構築
    (let ((coords (parse-cell-name name)))
      (if formula
          (update-dependencies name 
                               (extract-references formula 
                                                   (second coords) 
                                                   (first coords)))
          ;; 数式がなくなった場合は依存関係をクリア
          (update-dependencies name nil)))))

(defun record-cell-change (cell-name old-value old-formula)
  "単一セルの変更を記録"
  (let ((action (list :type :cell-change
                      :before (list :name cell-name
                                    :value old-value
                                    :formula old-formula)
                      :after (make-cell-snapshot cell-name))))
    (push-undo action)
    ;; Redo履歴をクリア
    (clear-redo)))

(defun record-multi-change (before-snapshots after-snapshots)
  "複数セルの変更を記録"
  (let ((action (list :type :multi-change
                      :before before-snapshots
                      :after after-snapshots)))
    (push-undo action)
    (clear-redo)))

(defun undo ()
  "直前の操作を取り消す"
  (if (null (undo-stack))
      (progn
        (format t "Undo: 履歴がありません~%")
        nil)
      (let ((action (pop-undo)))
        (push-redo action)
        (case (getf action :type)
          (:cell-change
           (restore-cell-snapshot (getf action :before))
           (let ((name (getf (getf action :before) :name)))
             (recalc-dependents name)))
          (:multi-change
           (dolist (snapshot (getf action :before))
             (restore-cell-snapshot snapshot))
           ;; 全ての変更セルの依存先を再計算
           (dolist (snapshot (getf action :before))
             (recalc-dependents (getf snapshot :name)))))
        t)))

(defun redo ()
  "取り消した操作をやり直す"
  (if (null (redo-stack))
      (progn
        (format t "Redo: 履歴がありません~%")
        nil)
      (let ((action (pop-redo)))
        (push-undo action)
        (case (getf action :type)
          (:cell-change
           (restore-cell-snapshot (getf action :after))
           (let ((name (getf (getf action :after) :name)))
             (recalc-dependents name)))
          (:multi-change
           (dolist (snapshot (getf action :after))
             (restore-cell-snapshot snapshot))
           (dolist (snapshot (getf action :after))
             (recalc-dependents (getf snapshot :name)))))
        t)))

(defun clear-history ()
  "Undo/Redo履歴をクリア"
  (setf (undo-stack) nil
        (redo-stack) nil)
  (format t "履歴をクリアしました~%"))

;;;; =========================
;;;; ファイル保存/読み込み
;;;; =========================

(defun iso-timestamp ()
  "ISO 8601形式のタイムスタンプを生成"
  (multiple-value-bind (sec min hour day month year)
      (get-decoded-time)
    (format nil "~4,'0d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0d"
            year month day hour min sec)))

(defun collect-cells-data ()
  "保存用にセルデータを収集"
  (let ((cells-data nil))
    (map-sheet (lambda (name cell)
                 (when (or (cell-value cell) (cell-formula cell))
                   (push (if (cell-formula cell)
                             (list name (cell-value cell) (cell-formula cell))
                             (list name (cell-value cell)))
                         cells-data))))
    (sort cells-data #'string< :key #'first)))

(defun save (filename)
  "スプレッドシートを.sspファイルに保存"
  (let ((cells-data (collect-cells-data)))
    (with-open-file (out filename 
                         :direction :output 
                         :if-exists :supersede
                         :external-format :utf-8)
      (let ((*print-pretty* t)
            (*print-right-margin* 80)
            (*print-case* :downcase)
            (*package* (find-package :ssexp)))  ; パッケージプレフィックスなしで保存
        ;; ヘッダーコメント
        (format out ";;;; -*- mode: lisp; coding: utf-8 -*-~%")
        (format out ";;;; SSP File (.ssp)~%")
        (format out ";;;; Created: ~a~%~%" (iso-timestamp))
        ;; データ
        (prin1 
         `(:spreadsheet
           :format-version 1
           :metadata (:created ,(iso-timestamp)
                      :modified ,(iso-timestamp)
                      :app-version "0.6")
           :grid (:rows ,(sheet-rows) :cols ,(sheet-cols))
           :cells ,cells-data)
         out)
        (terpri out)))
    (setf (current-file) filename)
    (format t "~%Saved: ~a (~d cells)~%" filename (length cells-data))
    filename))

(defun load-file (filename)
  "ファイルからスプレッドシートを読み込み"
  (with-open-file (in filename 
                      :direction :input
                      :external-format :utf-8)
    (let* ((*package* (find-package :ssexp))  ; SSEXPパッケージで読み込み
           (data (read in)))
      ;; 形式チェック
      (unless (and (listp data) (eq (car data) :spreadsheet))
        (error "無効なファイル形式: ~a" filename))
      (let ((version (getf (cdr data) :format-version))
            (grid (getf (cdr data) :grid))
            (cells (getf (cdr data) :cells)))
        ;; バージョンチェック
        (when (and version (> version 1))
          (warn "ファイルバージョン ~a は完全にはサポートされていません" version))
        ;; グリッド設定
        (when grid
          (setf (sheet-rows) (or (getf grid :rows) (sheet-rows))
                (sheet-cols) (or (getf grid :cols) (sheet-cols))))
        ;; シートをクリア
        (reset-sheet)
        (clear-dependencies)
        ;; Undo/Redo履歴をクリア
        (setf (undo-stack) nil
              (redo-stack) nil)
        ;; セルデータを復元
        (dolist (cell-data cells)
          (let* ((name (first cell-data))
                 (value (second cell-data))
                 (formula (third cell-data))
                 (cell (get-cell name)))
            (setf (cell-value cell) value
                  (cell-formula cell) formula)
            ;; 依存関係を再構築
            (when formula
              (let ((coords (parse-cell-name name)))
                (update-dependencies 
                 name 
                 (extract-references formula 
                                    (second coords) 
                                    (first coords)))))))
        (setf (current-file) filename)
        (format t "~%Loaded: ~a (~d cells)~%" filename (length cells))
        filename))))

(defun new-sheet ()
  "新規シートを作成（現在のデータをクリア）"
  (reset-sheet)
  (setf (cursor-x) 0 (cursor-y) 0)
  (clear-selection)
  (set-clipboard nil 0 0)
  (clear-dependencies)
  (setf (current-file) nil)
  ;; Undo/Redo履歴もクリア
  (setf (undo-stack) nil
        (redo-stack) nil)
  (format t "~%New sheet created~%")
  t)

;;;; =========================
;;;; CSV エクスポート/インポート
;;;; =========================

(defun get-used-range ()
  "使用されているセル範囲を取得 (min-col min-row max-col max-row)"
  (let ((min-col (1- (sheet-cols))) (min-row (1- (sheet-rows)))
        (max-col 0) (max-row 0)
        (has-data nil))
    (map-sheet (lambda (name cell)
                 (when (or (cell-value cell) (cell-formula cell))
                   (setf has-data t)
                   (let* ((coords (parse-cell-name name))
                          (col (first coords))
                          (row (second coords)))
                     (setf min-col (min min-col col)
                           min-row (min min-row row)
                           max-col (max max-col col)
                           max-row (max max-row row))))))
    (if has-data
        (values min-col min-row max-col max-row)
        (values 0 0 0 0))))

(defun escape-csv-field (str)
  "CSV用にフィールドをエスケープ"
  (let ((s (if (stringp str) str (princ-to-string str))))
    (if (or (find #\, s) 
            (find #\" s) 
            (find #\Newline s)
            (find #\Return s))
        ;; クォートが必要
        (format nil "\"~a\"" 
                (with-output-to-string (out)
                  (loop for c across s do
                    (when (char= c #\") (write-char #\" out))
                    (write-char c out))))
        s)))

(defun cell-value-for-csv (cell)
  "セル値をCSV出力用文字列に変換"
  (let ((val (cell-value cell)))
    (cond
      ((null val) "")
      ((stringp val) val)
      ((numberp val) (princ-to-string val))
      ((listp val) (princ-to-string val))
      ((symbolp val) (symbol-name val))
      (t (princ-to-string val)))))

(defun export-csv (filename &key (include-header nil) (include-formulas nil))
  "CSVファイルにエクスポート
   :include-header   列名ヘッダーを含める（デフォルトnil）
   :include-formulas 数式を含める（デフォルトnil、値のみ）"
  (multiple-value-bind (min-col min-row max-col max-row) (get-used-range)
    (with-open-file (out filename 
                         :direction :output 
                         :if-exists :supersede
                         :external-format :utf-8)
      ;; ヘッダー行（列名）
      (when include-header
        (loop for c from min-col to max-col
              for first = t then nil do
          (unless first (write-char #\, out))
          (write-string (string (code-char (+ (char-code #\A) c))) out))
        (terpri out))
      ;; データ行
      (let ((*package* (find-package :ssexp)))  ; パッケージプレフィックスなしで出力
        (loop for r from min-row to max-row do
          (loop for c from min-col to max-col
                for first = t then nil do
            (unless first (write-char #\, out))
            (let* ((cell (get-cell (cell-name c r)))
                   (text (if (and include-formulas (cell-formula cell))
                             (format nil "=~S" (cell-formula cell))
                             (cell-value-for-csv cell))))
              (write-string (escape-csv-field text) out)))
          (terpri out))))
    (format t "~%Exported CSV: ~a~%" filename)
    filename))

(defun parse-csv-line (line)
  "CSV行をフィールドのリストにパース"
  (let ((fields nil)
        (current (make-array 0 :element-type 'character :adjustable t :fill-pointer 0))
        (in-quotes nil)
        (i 0)
        (len (length line)))
    (loop while (< i len) do
      (let ((c (char line i)))
        (cond
          ;; クォート開始/終了
          ((char= c #\")
           (if in-quotes
               ;; クォート内で次もクォートならエスケープ
               (if (and (< (1+ i) len) (char= (char line (1+ i)) #\"))
                   (progn
                     (vector-push-extend #\" current)
                     (incf i))
                   (setf in-quotes nil))
               (setf in-quotes t)))
          ;; カンマ（クォート外）
          ((and (char= c #\,) (not in-quotes))
           (push (copy-seq current) fields)
           (setf (fill-pointer current) 0))
          ;; その他の文字
          (t (vector-push-extend c current))))
      (incf i))
    ;; 最後のフィールド
    (push (copy-seq current) fields)
    (nreverse fields)))

(defun parse-csv-value (text)
  "CSVフィールドをセル値に変換"
  (let ((trimmed (string-trim '(#\Space #\Tab) text)))
    (cond
      ;; 空文字列
      ((string= trimmed "") nil)
      ;; =で始まる → 数式として処理
      ((and (> (length trimmed) 0) (char= (char trimmed 0) #\=))
       (handler-case
           (let* ((*package* (find-package :ssexp))
                  (form (read-from-string (subseq trimmed 1))))
             (values (eval-formula form) form))
         (error () (values trimmed nil))))
      ;; 数値を試す
      (t (let* ((*package* (find-package :ssexp))
                (num (ignore-errors (read-from-string trimmed))))
           (if (numberp num)
               num
               trimmed))))))

(defun import-csv (filename &key (has-header nil) (start-col 0) (start-row 0))
  "CSVファイルからインポート
   :has-header 最初の行をヘッダーとしてスキップ（デフォルトnil）
   :start-col  開始列（デフォルト0=A列）
   :start-row  開始行（デフォルト0=1行目）"
  (with-open-file (in filename 
                      :direction :input
                      :external-format :utf-8)
    (let ((row-idx start-row)
          (cell-count 0)
          (first-line t))
      ;; シートをクリア
      (reset-sheet)
      (clear-dependencies)
      ;; 各行を処理
      (loop for line = (read-line in nil nil)
            while line do
        ;; ヘッダー行をスキップ
        (if (and first-line has-header)
            (setf first-line nil)
            (progn
              (setf first-line nil)
              (let ((fields (parse-csv-line line))
                    (col-idx start-col))
                (dolist (field fields)
                  (when (< col-idx (sheet-cols))
                    (multiple-value-bind (val formula) (parse-csv-value field)
                      (when val
                        (let* ((name (cell-name col-idx row-idx))
                               (cell (get-cell name)))
                          (setf (cell-value cell) val
                                (cell-formula cell) formula)
                          (when formula
                            (update-dependencies 
                             name 
                             (extract-references formula row-idx col-idx)))
                          (incf cell-count)))))
                  (incf col-idx)))
              (incf row-idx))))
      (setf (current-file) nil)  ; CSVなのでsspではない
      (format t "~%Imported CSV: ~a (~d cells)~%" filename cell-count)
      filename)))

