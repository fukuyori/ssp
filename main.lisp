;;;; main.lisp
;;;; SSP v0.7.2 - メインGUI、start関数、イベントハンドラ
;;;; v0.7: 日本語・Unicode対応
;;;; v0.7.1: 循環参照検出改善、パフォーマンス最適化
;;;; v0.7.2: シートサイズ上限設定（1000行×26列）

(in-package :ssexp)

;;;; =========================
;;;; メイン：GUIの構築と起動
;;;; =========================

(defun update-window-title ()
  "ウィンドウタイトルを更新"
  (wm-title *tk* (format nil "SSP v~a [~Dx~D]~a" 
                         *ssp-version*
                         (sheet-cols) (sheet-rows)
                         (if (current-file) 
                             (format nil " - ~a" (file-namestring (current-file)))
                             ""))))

(defun print-startup-message ()
  "起動メッセージを表示"
  (format t "~%")
  (format t "╔══════════════════════════════════════════════════════════════╗~%")
  (format t "║  SSP v~a - Symbolic Spreadsheet for Lisp Learning       ║~%" *ssp-version*)
  (format t "╠══════════════════════════════════════════════════════════════╣~%")
  (format t "║  Grid: ~4d rows × ~2d cols (max ~d×~d)                        ║~%" 
          +default-rows+ +default-cols+ +max-rows+ +max-cols+)
  (format t "║  View: ~4d rows × ~2d cols (with scrollbars)                  ║~%" 
          +visible-rows+ +visible-cols+)
  (format t "║                                                              ║~%")
  (format t "║  Commands: (detect-cycles) (show-cache-stats) (version-info) ║~%")
  (format t "╚══════════════════════════════════════════════════════════════╝~%")
  (format t "~%"))

(defun start (&key (rows +default-rows+) (cols +default-cols+) (input-lines 3))
  "スプレッドシートを起動
   :rows        行数（デフォルト100、最大1000）
   :cols        列数（デフォルト26、最大26=A-Z）
   :input-lines 入力欄の行数（デフォルト3）"
  ;; パラメータ検証 (v0.7.2)
  (multiple-value-bind (valid-rows valid-cols warnings)
      (validate-grid-size rows cols)
    ;; 警告表示
    (dolist (w warnings)
      (format t "Warning: ~a~%" w))
    ;; パラメータ設定
    (setf (sheet-rows) valid-rows)
    (setf (sheet-cols) valid-cols))
  
  ;; 初期化
  (reset-sheet)
  (setf (cursor-x) 0 (cursor-y) 0)
  (clear-selection)
  (set-clipboard nil 0 0)
  (clear-dependencies)
  (setf (current-file) nil)
  (init-sizes)  ; 列幅・行高さを初期化
  
  ;; 起動メッセージ表示 (v0.7)
  (print-startup-message)
  
  (with-ltk ()
    (update-window-title)
    
    ;; 垂直分割用のPanedWindowをTclコマンドで作成
    (format-wish "ttk::panedwindow .paned -orient vertical")
    
    ;; ウィジェット作成
    (let* (;; 入力エリア用フレーム（.paned配下）
           (input-frame (make-instance 'frame))
           ;; 複数行入力用Textウィジェット（固定幅フォント）
           (input-text (make-instance 'text
                                      :master input-frame
                                      :width 80
                                      :height input-lines
                                      :font "TkFixedFont"))
           (input-scroll (make-instance 'scrollbar 
                                        :master input-frame
                                        :orientation :vertical))
           ;; スプレッドシート用フレーム
           (canvas-frame (make-instance 'frame))
           ;; スクロールバー (v0.7.2)
           (canvas-vscroll (make-instance 'scrollbar 
                                          :master canvas-frame
                                          :orientation :vertical))
           (canvas-hscroll (make-instance 'scrollbar 
                                          :master canvas-frame
                                          :orientation :horizontal))
           ;; 4つのキャンバス（ヘッダー固定対応 v0.7.2）
           ;; 左上コーナー（固定）
           (corner-canvas (make-instance 'canvas
                                         :master canvas-frame
                                         :width +header-w+
                                         :height +header-h+))
           ;; 列ヘッダー（横スクロール連動）
           (col-header-canvas (make-instance 'canvas
                                             :master canvas-frame
                                             :width (- (visible-width) +header-w+)
                                             :height +header-h+))
           ;; 行ヘッダー（縦スクロール連動）
           (row-header-canvas (make-instance 'canvas
                                             :master canvas-frame
                                             :width +header-w+
                                             :height (- (visible-height) +header-h+)))
           ;; メインセル（両方向スクロール）
           (canvas (make-instance 'canvas
                                  :master canvas-frame
                                  :width (- (visible-width) +header-w+)
                                  :height (- (visible-height) +header-h+)))
           ;; メニューバー
           (mb (make-menubar))
           (file-menu (make-menu mb "File"))
           (edit-menu (make-menu mb "Edit")))
      
      ;; ファイルメニュー項目
      (make-menubutton file-menu "New             Ctrl+N"
                       (lambda ()
                         (new-sheet)
                         (update-window-title)
                         (update-scroll-region canvas)
                         (update-text-input input-text)
                         (redraw canvas)))
      
      (make-menubutton file-menu "Open...         Ctrl+O"
                       (lambda ()
                         (let ((filename (get-open-file 
                                          :filetypes '(("SSP" "*.ssp")
                                                       ("All files" "*")))))
                           (when (and filename (> (length filename) 0))
                             (handler-case
                                 (progn
                                   (load-file filename)
                                   (update-window-title)
                                   (update-scroll-region canvas)
                                   (update-text-input input-text)
                                   (redraw canvas))
                               (error (e)
                                 (do-msg (format nil "Load Error: ~a" e))))))))
      
      (make-menubutton file-menu "Save            Ctrl+S"
                       (lambda ()
                         (if (current-file)
                             (progn
                               (save (current-file))
                               (do-msg (format nil "Saved: ~a" 
                                              (file-namestring (current-file)))))
                             ;; ファイルがない場合は名前を付けて保存
                             (let ((filename (get-save-file 
                                              :filetypes '(("SSP" "*.ssp")
                                                           ("All files" "*")))))
                               (when (and filename (> (length filename) 0))
                                 ;; 拡張子がなければ追加
                                 (unless (search ".ssp" filename :test #'char-equal)
                                   (setf filename (concatenate 'string filename ".ssp")))
                                 (save filename)
                                 (update-window-title)
                                 (do-msg (format nil "Saved: ~a" 
                                                (file-namestring filename))))))))
      
      (make-menubutton file-menu "Save As..."
                       (lambda ()
                         (let ((filename (get-save-file 
                                          :filetypes '(("SSP" "*.ssp")
                                                       ("All files" "*")))))
                           (when (and filename (> (length filename) 0))
                             ;; 拡張子がなければ追加
                             (unless (search ".ssp" filename :test #'char-equal)
                               (setf filename (concatenate 'string filename ".ssp")))
                             (save filename)
                             (update-window-title)
                             (do-msg (format nil "Saved: ~a" 
                                            (file-namestring filename)))))))
      
      (add-separator file-menu)
      
      (make-menubutton file-menu "Import CSV..."
                       (lambda ()
                         (let ((filename (get-open-file 
                                          :filetypes '(("CSV files" "*.csv")
                                                       ("TSV files" "*.tsv")
                                                       ("Text files" "*.txt")
                                                       ("All files" "*")))))
                           (when (and filename (> (length filename) 0))
                             (handler-case
                                 (progn
                                   (import-csv filename)
                                   (update-window-title)
                                   (update-scroll-region canvas)
                                   (update-text-input input-text)
                                   (redraw canvas)
                                   (do-msg (format nil "Imported: ~a" 
                                                  (file-namestring filename))))
                               (error (e)
                                 (do-msg (format nil "Import Error: ~a" e))))))))
      
      (make-menubutton file-menu "Export CSV..."
                       (lambda ()
                         (let ((filename (get-save-file 
                                          :filetypes '(("CSV files" "*.csv")
                                                       ("All files" "*")))))
                           (when (and filename (> (length filename) 0))
                             ;; 拡張子がなければ追加
                             (unless (search ".csv" filename :test #'char-equal)
                               (setf filename (concatenate 'string filename ".csv")))
                             (handler-case
                                 (progn
                                   (export-csv filename)
                                   (do-msg (format nil "Exported: ~a" 
                                                  (file-namestring filename))))
                               (error (e)
                                 (do-msg (format nil "Export Error: ~a" e))))))))
      
      (add-separator file-menu)
      
      (make-menubutton file-menu "Exit"
                       (lambda ()
                         (setf *exit-mainloop* t)))
      
      ;; 編集メニュー項目
      (make-menubutton edit-menu "Undo            Ctrl+Z"
                       (lambda ()
                         (when (undo)
                           (update-text-input input-text)
                           (redraw canvas))))
      
      (make-menubutton edit-menu "Redo            Ctrl+Y"
                       (lambda ()
                         (when (redo)
                           (update-text-input input-text)
                           (redraw canvas))))
      
      (add-separator edit-menu)
      
      (make-menubutton edit-menu "Cut             Ctrl+X"
                       (lambda ()
                         (copy-to-system-clipboard)
                         (clear-selection-cells)
                         (clear-selection)
                         (redraw canvas)
                         (update-text-input input-text)))
      
      (make-menubutton edit-menu "Copy            Ctrl+C"
                       (lambda ()
                         (copy-to-system-clipboard)))
      
      (make-menubutton edit-menu "Paste           Ctrl+V"
                       (lambda ()
                         (let ((sys-clip (get-system-clipboard)))
                           (if (and sys-clip (> (length sys-clip) 0))
                               (paste-from-system-clipboard)
                               (paste-clipboard)))
                         (clear-selection)
                         (redraw canvas)
                         (update-text-input input-text)))
      
      (add-separator edit-menu)
      
      (make-menubutton edit-menu "Delete          Delete"
                       (lambda ()
                         (clear-selection-cells)
                         (clear-selection)
                         (redraw canvas)
                         (update-text-input input-text)))
      
      (add-separator edit-menu)
      
      (make-menubutton edit-menu "Insert Row"
                       (lambda ()
                         (insert-row (cursor-y))
                         (configure canvas :height (total-height))
                         (redraw canvas)))
      
      (make-menubutton edit-menu "Insert Column"
                       (lambda ()
                         (insert-col (cursor-x))
                         (configure canvas :width (total-width))
                         (redraw canvas)))
      
      (make-menubutton edit-menu "Delete Row"
                       (lambda ()
                         (delete-row (cursor-y))
                         (configure canvas :height (total-height))
                         (redraw canvas)
                         (update-text-input input-text)))
      
      (make-menubutton edit-menu "Delete Column"
                       (lambda ()
                         (delete-col (cursor-x))
                         (configure canvas :width (total-width))
                         (redraw canvas)
                         (update-text-input input-text)))
      
      ;; セパレーター
      (add-separator edit-menu)
      
      ;; Format Expression
      (make-menubutton edit-menu "Format Expression   Ctrl+Shift+F"
                       (lambda ()
                         (format-sexp input-text)))
      
      ;; キーボードショートカット (Ctrl+N, Ctrl+O, Ctrl+S)
      (bind *tk* "<Control-n>"
            (lambda (evt)
              (declare (ignore evt))
              (new-sheet)
              (update-window-title)
              (update-text-input input-text)
              (redraw canvas)))
      
      (bind *tk* "<Control-o>"
            (lambda (evt)
              (declare (ignore evt))
              (let ((filename (get-open-file 
                               :filetypes '(("SSP" "*.ssp")
                                            ("All files" "*")))))
                (when (and filename (> (length filename) 0))
                  (handler-case
                      (progn
                        (load-file filename)
                        (update-window-title)
                        (update-text-input input-text)
                        (redraw canvas))
                    (error (e)
                      (do-msg (format nil "読み込みエラー: ~a" e))))))))
      
      (bind *tk* "<Control-s>"
            (lambda (evt)
              (declare (ignore evt))
              (if (current-file)
                  (progn
                    (save (current-file))
                    (do-msg (format nil "保存しました: ~a" 
                                   (file-namestring (current-file)))))
                  ;; ファイルがない場合は名前を付けて保存
                  (let ((filename (get-save-file 
                                   :filetypes '(("SSP" "*.ssp")
                                                ("All files" "*")))))
                    (when (and filename (> (length filename) 0))
                      (unless (search ".ssp" filename :test #'char-equal)
                        (setf filename (concatenate 'string filename ".ssp")))
                      (save filename)
                      (update-window-title)
                      (do-msg (format nil "保存しました: ~a" 
                                     (file-namestring filename))))))))
      
      ;; Ctrl+Z → Undo
      (bind *tk* "<Control-z>"
            (lambda (evt)
              (declare (ignore evt))
              (when (undo)
                (update-text-input input-text)
                (redraw canvas))))
      
      ;; Ctrl+Y → Redo
      (bind *tk* "<Control-y>"
            (lambda (evt)
              (declare (ignore evt))
              (when (redo)
                (update-text-input input-text)
                (redraw canvas))))
      
      ;; Ctrl+X → 切り取り
      (bind *tk* "<Control-x>"
            (lambda (evt)
              (declare (ignore evt))
              (copy-to-system-clipboard)
              (clear-selection-cells)
              (clear-selection)
              (redraw canvas)
              (update-text-input input-text)))
      
      ;; スクロールバーとテキストを連携
      (configure input-scroll :command (format nil "~a yview" (widget-path input-text)))
      (configure input-text :yscrollcommand (format nil "~a set" (widget-path input-scroll)))
      ;; タブ幅を4文字分に設定
      (format-wish "~a configure -tabs [list [expr {[font measure TkFixedFont 0] * 4}]]" 
                   (widget-path input-text))
      
      ;; Rainbow括弧のタグをセットアップ
      (setup-rainbow-tags input-text)
      ;; キー入力時に括弧を色分け
      (bind input-text "<KeyRelease>"
            (lambda (evt)
              (declare (ignore evt))
              (colorize-parentheses input-text)))
      
      ;; レイアウト - 入力フレーム内
      (pack input-scroll :side :right :fill :y)
      (pack input-text :side :left :fill :both :expand t)
      
      ;; レイアウト - キャンバスフレーム内（4キャンバス＋スクロールバー v0.7.2）
      ;; スクロール領域を設定
      (let ((cells-width (- (total-width) +header-w+))
            (cells-height (- (total-height) +header-h+)))
        ;; 列ヘッダーのスクロール領域（横スクロール連動）
        (format-wish "~a configure -scrollregion {0 0 ~d ~d}"
                     (widget-path col-header-canvas) cells-width +header-h+)
        ;; 行ヘッダーのスクロール領域（縦スクロール連動）
        (format-wish "~a configure -scrollregion {0 0 ~d ~d}"
                     (widget-path row-header-canvas) +header-w+ cells-height)
        ;; メインキャンバスのスクロール領域
        (format-wish "~a configure -scrollregion {0 0 ~d ~d}"
                     (widget-path canvas) cells-width cells-height))
      
      ;; スクロール連動の設定 (v0.7.7 改善 - スクロール後に再描画)
      ;; ssp_redraw コールバックを設定
      (format-wish "proc ssp_redraw {} {}")  ; プレースホルダー
      
      ;; scroll_y: 垂直スクロール後に再描画
      (format-wish "proc scroll_y {args} {
          ~a yview {*}$args
          ~a yview {*}$args
          after idle ssp_redraw
      }" (widget-path canvas) (widget-path row-header-canvas))
      (configure canvas-vscroll :command "scroll_y")
      
      ;; scroll_x: 水平スクロール後に再描画
      (format-wish "proc scroll_x {args} {
          ~a xview {*}$args
          ~a xview {*}$args
          after idle ssp_redraw
      }" (widget-path canvas) (widget-path col-header-canvas))
      (configure canvas-hscroll :command "scroll_x")
      
      ;; Windows/Mac用MouseWheelハンドラ
      (format-wish "proc ssp_wheel_y {delta} {
          if {$delta > 0} {
              scroll_y scroll -3 units
          } else {
              scroll_y scroll 3 units
          }
      }")
      (format-wish "proc ssp_wheel_x {delta} {
          if {$delta > 0} {
              scroll_x scroll -3 units
          } else {
              scroll_x scroll 3 units
          }
      }")
      
      ;; スクロールバーの位置更新（メインキャンバスから）
      (configure canvas :xscrollcommand (format nil "~a set" (widget-path canvas-hscroll)))
      (configure canvas :yscrollcommand (format nil "~a set" (widget-path canvas-vscroll)))
      
      ;; グリッドレイアウト
      (format-wish "grid ~a -row 0 -column 0 -sticky nw" (widget-path corner-canvas))
      (format-wish "grid ~a -row 0 -column 1 -sticky new" (widget-path col-header-canvas))
      (format-wish "grid ~a -row 1 -column 0 -sticky nsw" (widget-path row-header-canvas))
      (format-wish "grid ~a -row 1 -column 1 -sticky nsew" (widget-path canvas))
      (format-wish "grid ~a -row 0 -column 2 -rowspan 2 -sticky ns" (widget-path canvas-vscroll))
      (format-wish "grid ~a -row 2 -column 0 -columnspan 2 -sticky ew" (widget-path canvas-hscroll))
      (format-wish "grid rowconfigure ~a 1 -weight 1" (widget-path canvas-frame))
      (format-wish "grid columnconfigure ~a 1 -weight 1" (widget-path canvas-frame))
      
      ;; グローバルキャンバス参照を設定 (v0.7.2)
      (setf *corner-canvas* corner-canvas
            *col-header-canvas* col-header-canvas
            *row-header-canvas* row-header-canvas
            *main-canvas* canvas)
      
      ;; スクロール位置を初期化
      (setf *scroll-x* 0 *scroll-y* 0)
      
      ;; スクロールバーリリース時に再描画 (v0.7.7)
      (bind canvas-vscroll "<ButtonRelease-1>"
            (lambda (evt)
              (declare (ignore evt))
              (redraw canvas)))
      (bind canvas-hscroll "<ButtonRelease-1>"
            (lambda (evt)
              (declare (ignore evt))
              (redraw canvas)))
      
      ;; スクロール位置監視タイマー (v0.7.7)
      ;; Windows/Macのホイールスクロール対応
      (let ((last-scroll-x 0)
            (last-scroll-y 0)
            (poll-active t))
        (labels ((check-scroll-position ()
                   (when poll-active
                     ;; Tkのスクロール位置を取得
                     (format-wish "senddatastrings [~a yview]" (widget-path canvas))
                     (let ((yview (ltk::read-data)))
                       (when (and yview (first yview))
                         (let ((y-frac (ignore-errors (read-from-string (first yview)))))
                           (when (and (numberp y-frac)
                                     (/= y-frac last-scroll-y))
                             (setf last-scroll-y y-frac)
                             (redraw canvas)))))
                     ;; 次のチェックをスケジュール
                     (ltk:after 100 #'check-scroll-position))))
          ;; ポーリング開始
          (ltk:after 100 #'check-scroll-position)
          ;; ウィンドウクローズ時にポーリング停止
          (bind *tk* "<Destroy>"
                (lambda (evt)
                  (declare (ignore evt))
                  (setf poll-active nil)))))
      
      ;; マウスホイールスクロール
      ;; Linux用 (Button-4/5) - 即時再描画
      (bind canvas "<Button-4>"
            (lambda (evt)
              (declare (ignore evt))
              (format-wish "scroll_y scroll -3 units")
              (redraw canvas)))
      (bind canvas "<Button-5>"
            (lambda (evt)
              (declare (ignore evt))
              (format-wish "scroll_y scroll 3 units")
              (redraw canvas)))
      (bind canvas "<Shift-Button-4>"
            (lambda (evt)
              (declare (ignore evt))
              (format-wish "scroll_x scroll -3 units")
              (redraw canvas)))
      (bind canvas "<Shift-Button-5>"
            (lambda (evt)
              (declare (ignore evt))
              (format-wish "scroll_x scroll 3 units")
              (redraw canvas)))
      
      ;; Windows/Mac用 - Tclでdeltaを処理してscroll_y/scroll_xを呼ぶ
      ;; ポーリングタイマーが位置変化を検出して再描画する
      (let ((canvas-path (widget-path canvas)))
        (format-wish "bind ~a <MouseWheel> {
            if {%D > 0} {
                scroll_y scroll -3 units
            } else {
                scroll_y scroll 3 units
            }
        }" canvas-path)
        (format-wish "bind ~a <Shift-MouseWheel> {
            if {%D > 0} {
                scroll_x scroll -3 units
            } else {
                scroll_x scroll 3 units
            }
        }" canvas-path))
      
      ;; PanedWindowにペインを追加
      (format-wish ".paned add ~a -weight 0" (widget-path input-frame))
      (format-wish ".paned add ~a -weight 1" (widget-path canvas-frame))
      ;; PanedWindowをパック
      (format-wish "pack .paned -fill both -expand true -padx 2 -pady 2")

      ;; ウィンドウリサイズ時に再描画 (v0.7.7)
      (let ((resize-pending nil))
        (bind canvas "<Configure>"
              (lambda (evt)
                (when evt
                  ;; 実際のキャンバスサイズを取得
                  (let ((new-w (ignore-errors (slot-value evt 'ltk::width)))
                        (new-h (ignore-errors (slot-value evt 'ltk::height))))
                    (when (and new-w new-h (numberp new-w) (numberp new-h)
                               (> new-w 0) (> new-h 0))
                      ;; 実際のキャンバスサイズを更新（ヘッダー分を加算）
                      (setf *actual-canvas-width* (+ new-w +header-w+)
                            *actual-canvas-height* (+ new-h +header-h+))
                      ;; 遅延再描画（連続リサイズ対策）
                      (unless resize-pending
                        (setf resize-pending t)
                        (ltk:after 100 (lambda ()
                                        (setf resize-pending nil)
                                        (redraw canvas))))))))))

      ;; 初期描画
      (update-text-input input-text)
      (redraw canvas)

      ;;; --- イベントバインド ---

      ;; Enter → 確定して下に移動
      (bind input-text "<Return>"
            (lambda (evt)
              (declare (ignore evt))
              (commit-and-move input-text canvas :down)
              (focus canvas)))
      
      ;; Ctrl+Enter → 確定してそのまま
      (bind input-text "<Control-Return>"
            (lambda (evt)
              (declare (ignore evt))
              (commit-and-move input-text canvas :stay)
              (focus canvas)))
      
      ;; Alt+Enter → 確定して右に移動
      (bind input-text "<Alt-Return>"
            (lambda (evt)
              (declare (ignore evt))
              (commit-and-move input-text canvas :right)
              (focus canvas)))
      
      ;; Shift+Alt+Enter → 確定して左に移動
      (bind input-text "<Shift-Alt-Return>"
            (lambda (evt)
              (declare (ignore evt))
              (commit-and-move input-text canvas :left)
              (focus canvas)))
      
      ;; Escape → 編集キャンセル（元に戻す）
      (bind input-text "<Escape>"
            (lambda (evt)
              (declare (ignore evt))
              (update-text-input input-text)
              (focus canvas)))
      
      ;; Ctrl+Shift+F → S式を整形
      (bind input-text "<Control-Shift-f>"
            (lambda (evt)
              (declare (ignore evt))
              (format-sexp input-text)))
      
      ;; Tclレベルでバインディングを調整（breakでデフォルト動作を抑制）
      (let ((path (widget-path input-text)))
        (format-wish "bind ~a <Return> \"[bind ~a <Return>]; break\"" path path)
        (format-wish "bind ~a <Control-Return> \"[bind ~a <Control-Return>]; break\"" path path)
        (format-wish "bind ~a <Alt-Return> \"[bind ~a <Alt-Return>]; break\"" path path)
        (format-wish "bind ~a <Shift-Alt-Return> \"[bind ~a <Shift-Alt-Return>]; break\"" path path)
        (format-wish "bind ~a <Escape> \"[bind ~a <Escape>]; break\"" path path)
        ;; Shift+Enter で改行
        (format-wish "bind ~a <Shift-Return> {~a insert insert \\n; break}" path path))

      ;; キーボードスクロール (v0.7.7 改良 - 再描画付き)
      ;; Page Up/Down
      (bind canvas "<Prior>"
            (lambda (evt)
              (declare (ignore evt))
              (format-wish "scroll_y scroll -1 pages")
              (redraw canvas)))
      (bind canvas "<Next>"
            (lambda (evt)
              (declare (ignore evt))
              (format-wish "scroll_y scroll 1 pages")
              (redraw canvas)))
      ;; Ctrl+Home → 先頭へ（カーソルも移動）
      (bind canvas "<Control-Home>"
            (lambda (evt)
              (declare (ignore evt))
              (setf (cursor-x) 0 (cursor-y) 0)
              (setf (selection-start-x) 0 (selection-start-y) 0
                    (selection-end-x) 0 (selection-end-y) 0)
              (format-wish "~a yview moveto 0" (widget-path canvas))
              (format-wish "~a yview moveto 0" (widget-path row-header-canvas))
              (format-wish "~a xview moveto 0" (widget-path canvas))
              (format-wish "~a xview moveto 0" (widget-path col-header-canvas))
              (setf *scroll-x* 0 *scroll-y* 0)
              (update-text-input input-text)
              (redraw canvas)))
      ;; Ctrl+End → 末尾へ（カーソルも移動）
      (bind canvas "<Control-End>"
            (lambda (evt)
              (declare (ignore evt))
              (let ((last-x (1- (sheet-cols)))
                    (last-y (1- (sheet-rows))))
                (setf (cursor-x) last-x (cursor-y) last-y)
                (setf (selection-start-x) last-x (selection-start-y) last-y
                      (selection-end-x) last-x (selection-end-y) last-y)
                (format-wish "~a yview moveto 1" (widget-path canvas))
                (format-wish "~a yview moveto 1" (widget-path row-header-canvas))
                (format-wish "~a xview moveto 1" (widget-path canvas))
                (format-wish "~a xview moveto 1" (widget-path col-header-canvas))
                (update-text-input input-text)
                (redraw canvas))))

      ;; セルクリック → 選択開始（クリック時のみスクロール位置を取得 v0.7.2改善）
      (bind canvas "<ButtonPress-1>"
            (lambda (evt)
              (let ((mx (and evt (slot-value evt 'ltk::x)))
                    (my (and evt (slot-value evt 'ltk::y))))
                (when (and mx my (numberp mx) (numberp my))
                  ;; クリック時にスクロール位置を取得（1回のみ）
                  (format-wish "senddatastrings [list [~a canvasx ~d] [~a canvasy ~d]]"
                               (widget-path canvas) mx (widget-path canvas) my)
                  (let* ((coords (ltk::read-data))
                         (canvas-x (if coords (parse-integer (first coords) :junk-allowed t) mx))
                         (canvas-y (if coords (parse-integer (second coords) :junk-allowed t) my)))
                    ;; スクロールオフセットを記録（ドラッグ用）
                    (setf *scroll-x* (- canvas-x mx)
                          *scroll-y* (- canvas-y my))
                    ;; ヘッダー分を加算してセル位置を計算
                    (let* ((adjusted-x (+ canvas-x +header-w+))
                           (adjusted-y (+ canvas-y +header-h+))
                           (x (clamp (find-col-at adjusted-x) 0 (1- (sheet-cols))))
                           (y (clamp (find-row-at adjusted-y) 0 (1- (sheet-rows)))))
                      (setf (cursor-x) x
                            (cursor-y) y
                            (selection-start-x) x
                            (selection-start-y) y
                            (selection-end-x) x
                            (selection-end-y) y
                            (selecting-p) t)
                      (update-text-input input-text)
                      (redraw canvas)))))
              (focus canvas)))

      ;; ドラッグ → 選択範囲拡張（キャッシュしたスクロール位置を使用 v0.7.2改善）
      (bind canvas "<B1-Motion>"
            (lambda (evt)
              (let ((mx (and evt (slot-value evt 'ltk::x)))
                    (my (and evt (slot-value evt 'ltk::y))))
                (when (and mx my (numberp mx) (numberp my) (selecting-p))
                  ;; クリック時に取得したスクロールオフセットを使用（通信なし）
                  (let* ((canvas-x (+ mx *scroll-x*))
                         (canvas-y (+ my *scroll-y*))
                         (adjusted-x (+ canvas-x +header-w+))
                         (adjusted-y (+ canvas-y +header-h+))
                         (x (find-col-at adjusted-x))
                         (y (find-row-at adjusted-y)))
                    (when (>= x 0)
                      (setf (selection-end-x) (clamp x 0 (1- (sheet-cols)))))
                    (when (>= y 0)
                      (setf (selection-end-y) (clamp y 0 (1- (sheet-rows)))))
                    (redraw canvas))))))

      ;; ドラッグ終了
      (bind canvas "<ButtonRelease-1>"
            (lambda (evt)
              (declare (ignore evt))
              (setf (selecting-p) nil
                    (resize-mode) nil
                    (resize-index) nil)))

      ;; === 列幅リサイズ機能 (col-header-canvas) ===
      ;; 列境界検出ヘルパー（境界から±5px以内か）
      (flet ((find-col-border (x)
               "x座標が列境界の近くなら列インデックスを返す、そうでなければnil"
               (let ((accum 0))
                 (dotimes (col (sheet-cols))
                   (incf accum (col-width col))
                   (when (<= (abs (- x accum)) 5)
                     (return-from find-col-border col)))
                 nil)))
        
        ;; 列ヘッダークリック → リサイズ開始
        (bind col-header-canvas "<ButtonPress-1>"
              (lambda (evt)
                (let ((mx (and evt (slot-value evt 'ltk::x))))
                  (when (and mx (numberp mx))
                    ;; スクロール位置を考慮
                    (format-wish "senddatastrings [list [~a canvasx ~d]]"
                                 (widget-path col-header-canvas) mx)
                    (let* ((coords (ltk::read-data))
                           (canvas-x (if coords (parse-integer (first coords) :junk-allowed t) mx))
                           (border-col (find-col-border canvas-x)))
                      (if border-col
                          ;; リサイズモード開始
                          (setf (resize-mode) :col
                                (resize-index) border-col
                                (resize-start) canvas-x)
                          ;; 列選択（将来の機能用）
                          nil))))))
        
        ;; 列ヘッダードラッグ → 列幅変更
        (bind col-header-canvas "<B1-Motion>"
              (lambda (evt)
                (let ((mx (and evt (slot-value evt 'ltk::x))))
                  (when (and mx (numberp mx) (eq (resize-mode) :col) (resize-index))
                    ;; スクロール位置を考慮
                    (format-wish "senddatastrings [list [~a canvasx ~d]]"
                                 (widget-path col-header-canvas) mx)
                    (let* ((coords (ltk::read-data))
                           (canvas-x (if coords (parse-integer (first coords) :junk-allowed t) mx))
                           (col (resize-index))
                           (col-start (col-left col))
                           (new-width (max +min-col-width+ (- canvas-x (- col-start +header-w+)))))
                      (set-col-width col new-width)
                      (update-scroll-region canvas)
                      (redraw canvas))))))
        
        ;; 列ヘッダードラッグ終了
        (bind col-header-canvas "<ButtonRelease-1>"
              (lambda (evt)
                (declare (ignore evt))
                (setf (resize-mode) nil
                      (resize-index) nil
                      (resize-start) nil)))
        
        ;; カーソル変更（リサイズ可能位置でsb_h_double_arrow）
        (bind col-header-canvas "<Motion>"
              (lambda (evt)
                (let ((mx (and evt (slot-value evt 'ltk::x))))
                  (when (and mx (numberp mx))
                    (format-wish "senddatastrings [list [~a canvasx ~d]]"
                                 (widget-path col-header-canvas) mx)
                    (let* ((coords (ltk::read-data))
                           (canvas-x (if coords (parse-integer (first coords) :junk-allowed t) mx))
                           (border-col (find-col-border canvas-x)))
                      (if border-col
                          (format-wish "~a configure -cursor sb_h_double_arrow"
                                       (widget-path col-header-canvas))
                          (format-wish "~a configure -cursor {}"
                                       (widget-path col-header-canvas)))))))))

      ;; === 行高さリサイズ機能 (row-header-canvas) ===
      (flet ((find-row-border (y)
               "y座標が行境界の近くなら行インデックスを返す、そうでなければnil"
               (let ((accum 0))
                 (dotimes (row (sheet-rows))
                   (incf accum (row-height row))
                   (when (<= (abs (- y accum)) 5)
                     (return-from find-row-border row)))
                 nil)))
        
        ;; 行ヘッダークリック → リサイズ開始
        (bind row-header-canvas "<ButtonPress-1>"
              (lambda (evt)
                (let ((my (and evt (slot-value evt 'ltk::y))))
                  (when (and my (numberp my))
                    ;; スクロール位置を考慮
                    (format-wish "senddatastrings [list [~a canvasy ~d]]"
                                 (widget-path row-header-canvas) my)
                    (let* ((coords (ltk::read-data))
                           (canvas-y (if coords (parse-integer (first coords) :junk-allowed t) my))
                           (border-row (find-row-border canvas-y)))
                      (if border-row
                          ;; リサイズモード開始
                          (setf (resize-mode) :row
                                (resize-index) border-row
                                (resize-start) canvas-y)
                          ;; 行選択（将来の機能用）
                          nil))))))
        
        ;; 行ヘッダードラッグ → 行高さ変更
        (bind row-header-canvas "<B1-Motion>"
              (lambda (evt)
                (let ((my (and evt (slot-value evt 'ltk::y))))
                  (when (and my (numberp my) (eq (resize-mode) :row) (resize-index))
                    ;; スクロール位置を考慮
                    (format-wish "senddatastrings [list [~a canvasy ~d]]"
                                 (widget-path row-header-canvas) my)
                    (let* ((coords (ltk::read-data))
                           (canvas-y (if coords (parse-integer (first coords) :junk-allowed t) my))
                           (row (resize-index))
                           (row-start (row-top row))
                           (new-height (max +min-row-height+ (- canvas-y (- row-start +header-h+)))))
                      (set-row-height row new-height)
                      (update-scroll-region canvas)
                      (redraw canvas))))))
        
        ;; 行ヘッダードラッグ終了
        (bind row-header-canvas "<ButtonRelease-1>"
              (lambda (evt)
                (declare (ignore evt))
                (setf (resize-mode) nil
                      (resize-index) nil
                      (resize-start) nil)))
        
        ;; カーソル変更（リサイズ可能位置でsb_v_double_arrow）
        (bind row-header-canvas "<Motion>"
              (lambda (evt)
                (let ((my (and evt (slot-value evt 'ltk::y))))
                  (when (and my (numberp my))
                    (format-wish "senddatastrings [list [~a canvasy ~d]]"
                                 (widget-path row-header-canvas) my)
                    (let* ((coords (ltk::read-data))
                           (canvas-y (if coords (parse-integer (first coords) :junk-allowed t) my))
                           (border-row (find-row-border canvas-y)))
                      (if border-row
                          (format-wish "~a configure -cursor sb_v_double_arrow"
                                       (widget-path row-header-canvas))
                          (format-wish "~a configure -cursor {}"
                                       (widget-path row-header-canvas)))))))))

      ;; 右クリック用の変数
      (let ((context-col nil)   ; 右クリックされた列
            (context-row nil))  ; 右クリックされた行
        
        ;; 列ヘッダー用コンテキストメニュー作成
        (format-wish "menu .colmenu -tearoff 0")
        (format-wish ".colmenu add command -label {Insert Column} -command {}")
        (format-wish ".colmenu add command -label {Delete Column} -command {}")
        (format-wish ".colmenu add separator")
        (format-wish ".colmenu add command -label {Column Width...} -command {}")
        
        ;; 行ヘッダー用コンテキストメニュー作成
        (format-wish "menu .rowmenu -tearoff 0")
        (format-wish ".rowmenu add command -label {Insert Row} -command {}")
        (format-wish ".rowmenu add command -label {Delete Row} -command {}")
        (format-wish ".rowmenu add separator")
        (format-wish ".rowmenu add command -label {Row Height...} -command {}")
        
        ;; 右クリック → コンテキストメニュー表示
        (bind canvas "<ButtonPress-3>"
              (lambda (evt)
                (let ((mx (and evt (slot-value evt 'ltk::x)))
                      (my (and evt (slot-value evt 'ltk::y))))
                  (when (and mx my (numberp mx) (numberp my))
                    (cond
                      ;; 列ヘッダー上で右クリック
                      ((and (< my +header-h+) (>= mx +header-w+))
                       (setf context-col (find-col-at mx))
                       (when (and context-col (>= context-col 0))
                         ;; メニューコマンドを更新
                         (format-wish ".colmenu entryconfigure 0 -command {event generate . <<ColInsert>>}")
                         (format-wish ".colmenu entryconfigure 1 -command {event generate . <<ColDelete>>}")
                         (format-wish ".colmenu entryconfigure 3 -command {event generate . <<ColWidth>>}")
                         ;; メニュー表示（画面座標を取得）
                         (format-wish "tk_popup .colmenu [expr [winfo rootx ~a] + ~a] [expr [winfo rooty ~a] + ~a]"
                                      (widget-path canvas) mx (widget-path canvas) my)))
                      
                      ;; 行ヘッダー上で右クリック
                      ((and (< mx +header-w+) (>= my +header-h+))
                       (setf context-row (find-row-at my))
                       (when (and context-row (>= context-row 0))
                         ;; メニューコマンドを更新
                         (format-wish ".rowmenu entryconfigure 0 -command {event generate . <<RowInsert>>}")
                         (format-wish ".rowmenu entryconfigure 1 -command {event generate . <<RowDelete>>}")
                         (format-wish ".rowmenu entryconfigure 3 -command {event generate . <<RowHeight>>}")
                         ;; メニュー表示
                         (format-wish "tk_popup .rowmenu [expr [winfo rootx ~a] + ~a] [expr [winfo rooty ~a] + ~a]"
                                      (widget-path canvas) mx (widget-path canvas) my))))))))
        
        ;; 列挿入イベント
        (bind *tk* "<<ColInsert>>"
              (lambda (evt)
                (declare (ignore evt))
                (when context-col
                  (insert-col context-col)
                  (configure canvas :width (total-width))
                  (redraw canvas))))
        
        ;; 列削除イベント
        (bind *tk* "<<ColDelete>>"
              (lambda (evt)
                (declare (ignore evt))
                (when context-col
                  (delete-col context-col)
                  (configure canvas :width (total-width))
                  (redraw canvas)
                  (update-text-input input-text))))
        
        ;; 列幅設定イベント
        (bind *tk* "<<ColWidth>>"
              (lambda (evt)
                (declare (ignore evt))
                (when context-col
                  (let* ((current-w (col-width context-col))
                         (col-name (string (code-char (+ (char-code #\A) context-col))))
                         (target-col context-col))
                    (show-size-dialog "Column Width" 
                                      (format nil "Width for column ~a:" col-name)
                                      current-w
                                      (lambda (w)
                                        (set-col-width target-col w)
                                        (configure canvas :width (total-width))
                                        (redraw canvas)))))))
        
        ;; 行挿入イベント
        (bind *tk* "<<RowInsert>>"
              (lambda (evt)
                (declare (ignore evt))
                (when context-row
                  (insert-row context-row)
                  (configure canvas :height (total-height))
                  (redraw canvas))))
        
        ;; 行削除イベント
        (bind *tk* "<<RowDelete>>"
              (lambda (evt)
                (declare (ignore evt))
                (when context-row
                  (delete-row context-row)
                  (configure canvas :height (total-height))
                  (redraw canvas)
                  (update-text-input input-text))))
        
        ;; 行高さ設定イベント
        (bind *tk* "<<RowHeight>>"
              (lambda (evt)
                (declare (ignore evt))
                (when context-row
                  (let* ((current-h (row-height context-row))
                         (row-num (1+ context-row))
                         (target-row context-row))
                    (show-size-dialog "Row Height"
                                      (format nil "Height for row ~a:" row-num)
                                      current-h
                                      (lambda (h)
                                        (set-row-height target-row h)
                                        (configure canvas :height (total-height))
                                        (redraw canvas))))))))

      ;; Ctrl+C → システムクリップボードにコピー
      (bind canvas "<Control-c>"
            (lambda (evt)
              (declare (ignore evt))
              (copy-to-system-clipboard)))

      ;; Ctrl+V → システムクリップボードからペースト
      (bind canvas "<Control-v>"
            (lambda (evt)
              (declare (ignore evt))
              (let ((sys-clip (get-system-clipboard)))
                (if (and sys-clip (> (length sys-clip) 0))
                    ;; システムクリップボードにデータあり
                    (paste-from-system-clipboard)
                    ;; なければ内部クリップボード
                    (paste-clipboard)))
              (clear-selection)
              (redraw canvas)
              (update-text-input input-text)))

      ;; Delete → 選択範囲をクリア
      (bind canvas "<Delete>"
            (lambda (evt)
              (declare (ignore evt))
              (clear-selection-cells)
              (clear-selection)
              (redraw canvas)
              (update-text-input input-text)))

      ;; BackSpace → 選択範囲をクリア
      (bind canvas "<BackSpace>"
            (lambda (evt)
              (declare (ignore evt))
              (clear-selection-cells)
              (clear-selection)
              (redraw canvas)
              (update-text-input input-text)))

      ;; 矢印キー（デバウンス付き v0.7.7）
      ;; キーリピートによるイベント蓄積を防止
      (let ((last-key-time 0)
            (key-interval 30))  ; 最小間隔（ミリ秒）
        (flet ((debounced-move (move-fn)
                 (let ((now (get-internal-real-time)))
                   (when (> (- now last-key-time) 
                           (* key-interval (/ internal-time-units-per-second 1000)))
                     (setf last-key-time now)
                     (clear-selection)
                     (funcall move-fn canvas input-text)))))
          (bind canvas "<Left>"
                (lambda (evt) 
                  (declare (ignore evt)) 
                  (debounced-move #'move-left)))
          (bind canvas "<Right>"
                (lambda (evt) 
                  (declare (ignore evt)) 
                  (debounced-move #'move-right)))
          (bind canvas "<Up>"
                (lambda (evt) 
                  (declare (ignore evt)) 
                  (debounced-move #'move-up)))
          (bind canvas "<Down>"
                (lambda (evt) 
                  (declare (ignore evt)) 
                  (debounced-move #'move-down)))))

      ;; Shift+矢印キー（範囲選択）
      (bind canvas "<Shift-Left>"
            (lambda (evt)
              (declare (ignore evt))
              ;; 選択開始していなければ現在位置から開始
              (unless (has-selection-p)
                (setf (selection-start-x) (cursor-x)
                      (selection-start-y) (cursor-y)
                      (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              ;; カーソルを移動し、選択終端も移動
              (when (> (cursor-x) 0)
                (decf (cursor-x))
                (setf (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (redraw canvas)
              (update-text-input input-text)))
      (bind canvas "<Shift-Right>"
            (lambda (evt)
              (declare (ignore evt))
              (unless (has-selection-p)
                (setf (selection-start-x) (cursor-x)
                      (selection-start-y) (cursor-y)
                      (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (when (< (cursor-x) (1- (sheet-cols)))
                (incf (cursor-x))
                (setf (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (redraw canvas)
              (update-text-input input-text)))
      (bind canvas "<Shift-Up>"
            (lambda (evt)
              (declare (ignore evt))
              (unless (has-selection-p)
                (setf (selection-start-x) (cursor-x)
                      (selection-start-y) (cursor-y)
                      (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (when (> (cursor-y) 0)
                (decf (cursor-y))
                (setf (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (redraw canvas)
              (update-text-input input-text)))
      (bind canvas "<Shift-Down>"
            (lambda (evt)
              (declare (ignore evt))
              (unless (has-selection-p)
                (setf (selection-start-x) (cursor-x)
                      (selection-start-y) (cursor-y)
                      (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (when (< (cursor-y) (1- (sheet-rows)))
                (incf (cursor-y))
                (setf (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (redraw canvas)
              (update-text-input input-text)))

      ;; Canvas上でEnter → Textにフォーカス
      (bind canvas "<Return>"
            (lambda (evt)
              (declare (ignore evt))
              (focus input-text)))
      
      ;; F2 → 編集モード（既存内容を編集）
      (bind canvas "<F2>"
            (lambda (evt)
              (declare (ignore evt))
              (focus input-text)
              ;; カーソルを末尾に移動
              (format-wish "~a mark set insert end" (widget-path input-text))))
      
      ;; Canvas上でキー入力 → 入力欄をクリアしてフォーカス移動（Tclレベルで処理）
      (let ((canvas-path (widget-path canvas))
            (text-path (widget-path input-text)))
        ;; 印刷可能文字のみを処理するTclバインディング
        (format-wish "bind ~a <Key> {
          set k %K
          set c %A
          # 特殊キーを除外
          if {$c ne {} && [string length $c] == 1 && [string is print $c]} {
            # 制御キーやファンクションキーでない場合
            if {![string match *Control* $k] && 
                ![string match *Shift* $k] && 
                ![string match *Alt* $k] && 
                ![string match *Meta* $k] &&
                ![string match *Super* $k] &&
                ![string match F?* $k] &&
                $k ne {Up} && $k ne {Down} && $k ne {Left} && $k ne {Right} &&
                $k ne {Return} && $k ne {Escape} && $k ne {Tab} &&
                $k ne {Delete} && $k ne {BackSpace} &&
                $k ne {Home} && $k ne {End} && $k ne {Prior} && $k ne {Next} &&
                $k ne {Insert} && $k ne {Caps_Lock} && $k ne {Num_Lock}} {
              # テキストをクリアして文字を挿入
              ~a delete 1.0 end
              ~a insert end $c
              focus ~a
            }
          }
        }" canvas-path text-path text-path text-path))

      (focus canvas))))

;;; ロード時メッセージ
(format t "~%╔══════════════════════════════════════════════════════════╗~%")
(format t "║  SSP v0.6 - Symbolic Spreadsheet for Lisp Learning       ║~%")
(format t "╠══════════════════════════════════════════════════════════╣~%")
(format t "║  SSP is not a notebook.                                  ║~%")
(format t "║  It is a Lisp-native evaluation space where cells are    ║~%")
(format t "║  expressions, not scripts.                               ║~%")
(format t "╚══════════════════════════════════════════════════════════╝~%")
(format t "~%Start: (ssexp:start) or (ssp:start)~%")
(format t "~%Basic Operations:~%")
(format t "  Arrow keys        : Move cursor~%")
(format t "  Shift+Arrow       : Select range~%")
(format t "  Type              : Direct input~%")
(format t "  F2                : Edit mode~%")
(format t "  Ctrl+X/C/V        : Cut/Copy/Paste~%")
(format t "  Ctrl+Z/Y          : Undo/Redo~%")
(format t "  Enter             : Confirm & move down~%")
(format t "  Ctrl+Shift+F      : Format S-expression~%")
(format t "~%Cell Input Examples:~%")
(format t "  42                : Number~%")
(format t "  =(+ A1 B1)        : Formula~%")
(format t "  =(range A1 A5)    : Cell range as list~%")
(format t "  =(sum (range A1 A5))~%")
(format t "  =(mapcar #'1+ (range A1 A5))~%")
(format t "~%")
