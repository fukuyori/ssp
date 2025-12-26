# SSP - Symbolic Spreadsheet for Lisp Learning

**SSP is not a notebook.**  
**It is a Lisp-native evaluation space where cells are expressions, not scripts.**

![Version](https://img.shields.io/badge/version-0.7.2-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Lisp](https://img.shields.io/badge/Common%20Lisp-SBCL-red.svg)
![GUI](https://img.shields.io/badge/GUI-LTK%2FTk-orange.svg)

[日本語版 README](README-JP.md)

---

## What's New in v0.7.2

### Grid Size Limits

- **Maximum rows**: 1000 (for UI performance)
- **Maximum columns**: 26 (A-Z, cell name format limitation)
- **Default grid**: 100 rows × 26 columns
- **Visible area**: 30 rows × 14 columns (with scrollbars)
- **Validation on startup**: `(start :rows 2000)` → automatically limited to 1000
- **Validation on import**: CSV/SSP files exceeding limits are truncated with warnings

### Scrollbars

- Horizontal and vertical scrollbars for navigating large sheets
- Auto-scroll when cursor moves outside visible area
- Fixed row/column headers during scroll
- Scroll region updates automatically on file load/import

### Scroll Controls

- **Mouse wheel**: Vertical scroll
- **Shift + Mouse wheel**: Horizontal scroll
- **Page Up/Down**: Scroll by page
- **Ctrl+Home**: Go to top-left
- **Ctrl+End**: Go to bottom-right

### Size Constants

```lisp
+max-rows+      ; 1000 - Maximum row count
+max-cols+      ; 26   - Maximum column count (A-Z)
+default-rows+  ; 100  - Default row count
+default-cols+  ; 26   - Default column count (A-Z)
+visible-rows+  ; 30   - Visible row count in window
+visible-cols+  ; 14   - Visible column count in window
```

### Enhanced CSV Import

```lisp
(import-csv "data.csv"
  :expand-grid t      ; Auto-expand grid to fit data (default)
  :max-rows 500       ; Custom row limit
  :max-cols 20)       ; Custom column limit
```

---

## What's New in v0.7.1

### Improved Circular Reference Detection

- **Path Display**: When a circular reference is detected, the full cycle path is shown
  - Example: `#循環: A3 (A1→A2→A3→A1)`
- **Pre-evaluation Check**: `(detect-cycles)` function to scan all cells for cycles before they cause errors
- **Depth Limit**: Maximum evaluation depth (100) prevents infinite loops

### Performance Optimization

- **Evaluation Cache**: Results are cached to avoid redundant recalculation
  - Only "dirty" (changed) cells and their dependents are recalculated
- **Cache Statistics**: `(show-cache-stats)` to monitor cache effectiveness
- **Topological Sort**: Improved dependency ordering with cycle warning

### New Commands

```lisp
(detect-cycles)       ; Scan all cells for circular references
(show-cache-stats)    ; Display cache hit/miss statistics
(show-cycle-path)     ; Show the last detected cycle path
(clear-cache)         ; Clear evaluation cache manually
```

---

## What's New in v0.7

### Japanese and Unicode Support

- **CJK Font Auto-Detection**: Automatically selects appropriate fonts for Japanese/Chinese/Korean characters
  - macOS: Menlo
  - Windows: MS Gothic
  - Linux: Noto Sans Mono CJK JP (with fallbacks)
- **Character Width Calculation**: Proper handling of full-width (2) vs half-width (1) characters
- **Text Truncation**: Smart truncation with "…" suffix respecting character widths
- **UTF-8 File I/O**: Full UTF-8 support for `.ssp` files
- **Excel-Compatible CSV**: BOM (Byte Order Mark) prefix for proper Excel import

---

## Philosophy

In SSP, each cell holds a single **S-expression**—not a script, not a code block.

```
Cell A1: 10
Cell A2: =(+ A1 5)        → 15
Cell A3: =(range A1 A2)   → (10 15)
Cell A4: =(apply #'+ A3)  → 25
```

When you type `=(+ A1 B1)`, you're not "running code"—you're defining a **symbolic relationship**. The spreadsheet grid becomes a live evaluation environment where dependencies flow naturally through cell references.

**Cells can hold any Lisp value:**
- Numbers: `42`, `3.14159`
- Lists: `(1 2 3 4 5)`
- Symbols: `HELLO`, `T`, `NIL`
- Strings: `"Hello, World!"`, `"日本語"`
- Nested structures: `((a 1) (b 2))`

---

## Screenshot

```
╔═════════════════════════════════════════════════════════════════════╗
║ [File] [Edit]                            SSP v0.7 [14×26]           ║
╠═════════════════════════════════════════════════════════════════════╣
║ =(mapcar #'1+ (range A1 A5))                                        ║
╠════╤════════════╤════════════════════════╤══════════╤═══════════════╣
║    │     A      │           B            │    C     │      D        ║
╠════╪════════════╪════════════════════════╪══════════╪═══════════════╣
║  1 │          1 │ (2 3 4 5 6)            │          │               ║
║  2 │          2 │                        │          │               ║
║  3 │          3 │ 日本語テスト           │          │               ║
║  4 │          4 │ "文字列"               │          │               ║
║  5 │          5 │                        │          │               ║
╚════╧════════════╧════════════════════════╧══════════╧═══════════════╝
       ↑ Numbers         ↑ Japanese text supported
```

---

## Cell Values

Unlike Excel (which only supports numbers, strings, and errors), SSP cells can hold **any Lisp value**.

### Supported Value Types

| Type | Input Example | Display | Notes |
|------|---------------|---------|-------|
| Integer | `42` | `42` | Right-aligned |
| Float | `3.14159` | `3.142` | Right-aligned, 4-digit precision |
| Ratio | `1/3` | `1/3` | Lisp-native exact fractions |
| String | `"Hello"` | `Hello` | Left-aligned |
| String (JP) | `"日本語"` | `日本語` | Full-width characters (v0.7) |
| Symbol | `HELLO` | `HELLO` | Uppercase |
| Keyword | `:keyword` | `:KEYWORD` | With colon prefix |
| List | `(1 2 3)` | `(1 2 3)` | Displayed as-is |
| Nested List | `((a 1) (b 2))` | `((A 1) (B 2))` | Alists, trees, etc. |
| NIL | `nil` | *(empty)* | Displayed as blank cell |
| T | `t` | `T` | Boolean true |

---

## Features

### Lisp-Native Formula System
- **S-expression formulas** with full Lisp syntax
- **150+ whitelisted pure functions** (math, list, string, logic)
- **Lambda expressions**: `=(mapcar (lambda (x) (* x x)) (range A1 A5))`
- **Higher-order functions**: `apply`, `funcall`, `reduce`, `mapcar`
- **Conditionals**: `if`, `cond`, `when`, `unless`, `case`

### Cell References
| Type | Syntax | Description |
|------|--------|-------------|
| Absolute | `A1`, `B2` | Fixed cell reference |
| Relative | `(rel -1 0)` | Offset from current cell |
| Range | `(range A1 A5)` | Returns list of values |
| Relative Range | `(rel-range -4 0 -1 0)` | Range by offsets |
| Position | `this-row`, `this-col` | Current position |

### Smart References (v0.5+)
- Auto-update on row/column insert/delete
- `#REF!` error for deleted cell references
- Confirmation dialogs to prevent data loss

### Unicode Support (v0.7)
- Japanese, Chinese, Korean character support
- Proper full-width/half-width character handling
- CJK font auto-selection per platform
- UTF-8 BOM for Excel CSV compatibility

### User Interface
- Resizable columns and rows (drag borders)
- Context menus on headers (right-click)
- Direct input mode (just start typing)
- Multi-line formula input with syntax highlighting
- S-expression auto-formatter (Ctrl+Shift+F)

### Data Management
- Undo/Redo (Ctrl+Z / Ctrl+Y) up to 100 operations
- Native `.ssp` file format (UTF-8)
- CSV import/export (with BOM option)
- System clipboard (TSV format)
- Range selection (drag or Shift+Arrow)

---

## Requirements

| Component | Version |
|-----------|---------|
| SBCL | 2.0+ recommended |
| Quicklisp | Latest |
| Tcl/Tk | 8.5+ |

### Recommended Fonts (for CJK support)
- **Linux**: Noto Sans Mono CJK JP, Source Han Code JP, IPAGothic
- **macOS**: Built-in (Menlo with fallback)
- **Windows**: MS Gothic (built-in)

---

## Installation

### 1. Install SBCL and Tk

```bash
# Ubuntu/Debian
sudo apt install sbcl tk fonts-noto-cjk

# macOS
brew install sbcl tcl-tk

# Windows
# Download SBCL from http://www.sbcl.org/
# Install Tcl/Tk from https://www.activestate.com/products/tcl/
```

### 2. Install Quicklisp

```bash
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --load quicklisp.lisp
```

```lisp
(quicklisp-quickstart:install)
(ql:add-to-init-file)
(quit)
```

---

## Usage

### With ASDF

```lisp
(push #P"/path/to/ssp/" asdf:*central-registry*)
(asdf:load-system :ssp)
(ssp:start)
```

### With Simple Loader (No ASDF Required)

```lisp
(load "/path/to/ssp/load.lisp")
(ssp:start)
```

### Startup Options

```lisp
(ssp:start)                      ; Default: 26 rows × 14 columns
(ssp:start :rows 50 :cols 10)    ; Custom grid size
(ssp:start :input-lines 5)       ; Larger formula input area
```

---

## Project Structure

```
ssp/
├── ssp.asd          ; ASDF system definition
├── load.lisp        ; Simple loader (no ASDF required)
├── package.lisp     ; Package, constants, structures, char-width (v0.7)
├── formula.lisp     ; Allowed functions, evaluation engine
├── core.lisp        ; Cell ops, dependencies, undo/redo, file I/O
├── ui.lisp          ; Drawing, input, syntax highlighting (Unicode v0.7)
├── main.lisp        ; GUI construction, event handlers
├── README.md        ; English documentation
└── README-JP.md     ; Japanese documentation
```

---

## Keyboard Shortcuts

### Navigation

| Key | Action |
|-----|--------|
| Arrow keys | Move cursor |
| Shift+Arrow | Extend selection |
| Home / End | First / Last column |
| Ctrl+Home | Go to A1 |
| Page Up/Down | Scroll by page |

### Editing

| Key | Action |
|-----|--------|
| Any character | Start typing (replaces cell) |
| F2 | Edit mode (keep content) |
| Delete / Backspace | Clear cell(s) |
| Escape | Cancel editing |
| Ctrl+Shift+F | Format S-expression |

### Confirmation

| Key | Action |
|-----|--------|
| Enter | Confirm → Move down |
| Ctrl+Enter | Confirm → Stay |
| Alt+Enter | Confirm → Move right |
| Shift+Enter | Newline in input |
| Tab | Confirm → Move right |

### Clipboard

| Key | Action |
|-----|--------|
| Ctrl+C | Copy |
| Ctrl+X | Cut |
| Ctrl+V | Paste |
| Ctrl+Z | Undo |
| Ctrl+Y | Redo |

### File

| Key | Action |
|-----|--------|
| Ctrl+N | New spreadsheet |
| Ctrl+O | Open file |
| Ctrl+S | Save |
| Ctrl+Shift+S | Save as |

---

## Formula Examples

### Basic Arithmetic
```lisp
=(+ 1 2 3)              → 6
=(* A1 A2)              → product of A1 and A2
=(/ (+ A1 A2) 2)        → average of two cells
```

### Working with Ranges
```lisp
=(range A1 A10)         → (1 2 3 4 5 6 7 8 9 10)
=(apply #'+ (range A1 A10))  → sum
=(apply #'max (range A1 A10)) → maximum
=(length (range A1 A10))     → count
```

### List Operations
```lisp
=(mapcar #'1+ (range A1 A5))     → increment each
=(remove-if #'oddp (range A1 A10)) → filter evens
=(reverse (range A1 A5))         → reverse order
=(sort (range A1 A5) #'<)        → sort ascending
```

### Lambda Expressions
```lisp
=(mapcar (lambda (x) (* x x)) (range A1 A5))  → squares
=(reduce (lambda (a b) (+ a b)) (range A1 A5)) → sum
```

### Conditionals
```lisp
=(if (> A1 0) "positive" "non-positive")
=(cond ((< A1 0) "negative")
       ((= A1 0) "zero")
       (t "positive"))
```

### Relative References
```lisp
=(rel -1 0)             → cell above
=(rel 0 -1)             → cell to the left
=(+ (rel -1 0) (rel -2 0))  → sum of two cells above
=(apply #'+ (rel-range -4 0 -1 0))  → sum of 4 cells above
```

---

## File Format

### Native Format (.ssp)

```lisp
(:spreadsheet
 :format-version 1
 :metadata (:created "2025-12-26T10:30:00"
            :modified "2025-12-26T11:45:00"
            :app-version "0.7")
 :grid (:rows 26 :cols 14)
 :cells (("A1" 100)
         ("A2" 200 (+ A1 100))
         ("B1" "日本語テスト")))
```

### API

```lisp
(ssp:save "mydata.ssp")
(ssp:load-file "mydata.ssp")
(ssp:new-sheet)
(ssp:export-csv "data.csv")                    ; With BOM (Excel compatible)
(ssp:export-csv "data.csv" :excel-compatible nil)  ; Without BOM
(ssp:import-csv "data.csv")
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.7.2 | 2025-12 | Grid size limits (1000×26), scrollbars, default 100×26, visible 30×14 |
| 0.7.1 | 2025-12 | Improved circular reference detection, evaluation cache, performance optimization |
| 0.7 | 2025-12 | Japanese/Unicode support, CJK fonts, character width calculation, UTF-8 BOM for CSV |
| 0.6 | 2025-12 | Structure-based architecture, accessor functions, modular split, renamed to SSP |
| 0.5 | 2025-12 | Smart formula references, row/column insert/delete |
| 0.4 | 2025-12 | Syntax highlighting, S-expression formatter |
| 0.3 | 2025-12 | Undo/Redo, file save/load, CSV support |
| 0.2 | 2025-12 | Range selection, clipboard, lambda support |
| 0.1 | 2025-12 | Initial release |

---

## License

MIT License

---

## Contributing

Contributions welcome! This is a learning project exploring the intersection of spreadsheets and Lisp.

---

*SSP: Where every cell is an expression, and the grid is your REPL.*
