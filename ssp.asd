;;;; ssp.asd
;;;; ASDF System Definition for SSP
;;;; SSP - Symbolic Spreadsheet for Lisp Learning

(asdf:defsystem #:ssp
  :description "SSP - Symbolic Spreadsheet for Lisp Learning. A Lisp-native evaluation space where cells are expressions, not scripts."
  :author "Claude & Human"
  :license "MIT"
  :version "0.7.1"
  :depends-on (#:ltk)
  :serial t
  :components ((:file "package")    ; パッケージ定義、定数、構造体、キャッシュ、循環検出
               (:file "formula")    ; 許可関数リスト、数式評価エンジン（深さ制限付き）
               (:file "core")       ; セル操作、依存関係、Undo/Redo、ファイルI/O
               (:file "ui")         ; 描画、入力、シンタックスハイライト（Unicode対応）
               (:file "main")))     ; start関数、イベント、メニュー
