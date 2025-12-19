# SSP - Symbolic Spreadsheet for Lisp Learning

**SSP is not a notebook.**  
**It is a Lisp-native evaluation space where cells are expressions, not scripts.**

![Version](https://img.shields.io/badge/version-0.6-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Lisp](https://img.shields.io/badge/Common%20Lisp-SBCL-red.svg)
![GUI](https://img.shields.io/badge/GUI-LTK%2FTk-orange.svg)

[日本語版 README](README-JP.md)

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
- Strings: `"Hello, World!"`
- Nested structures: `((a 1) (b 2))`

---

## Screenshot

```
╔═════════════════════════════════════════════════════════════════════╗
║ [File] [Edit]                            SSP v0.6 [14×26]           ║
╠═════════════════════════════════════════════════════════════════════╣
║ =(mapcar #'1+ (range A1 A5))                                        ║
╠════╤════════════╤════════════════════════╤══════════╤═══════════════╣
║    │     A      │           B            │    C     │      D        ║
╠════╪════════════╪════════════════════════╪══════════╪═══════════════╣
║  1 │          1 │ (2 3 4 5 6)            │          │               ║
║  2 │          2 │                        │          │               ║
║  3 │          3 │ FIBONACCI              │          │               ║
║  4 │          4 │ "string"               │          │               ║
║  5 │          5 │                        │          │               ║
╚════╧════════════╧════════════════════════╧══════════╧═══════════════╝
       ↑ Numbers         ↑ List as value
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
| Symbol | `HELLO` | `HELLO` | Uppercase |
| Keyword | `:keyword` | `:KEYWORD` | With colon prefix |
| List | `(1 2 3)` | `(1 2 3)` | Displayed as-is |
| Nested List | `((a 1) (b 2))` | `((A 1) (B 2))` | Alists, trees, etc. |
| NIL | `nil` | *(empty)* | Displayed as blank cell |
| T | `t` | `T` | Boolean true |

### Input Methods

```
Direct input:    42           → Number
                 "text"       → String  
                 hello        → Symbol HELLO
             
Formula input:   =(+ 1 2)     → 3
                 =(list 1 2 3) → (1 2 3)
                 =(range A1 A5) → (val1 val2 val3 val4 val5)
```

### Formula Return Value Examples

```lisp
=(+ 1 2 3)                          → 6           ; Number
=(/ 1 3)                            → 1/3         ; Ratio (exact)
=(list 'a 'b 'c)                    → (A B C)     ; List of symbols
=(cons 1 '(2 3))                    → (1 2 3)     ; List
=(if (> A1 0) 'pos 'neg)            → POS         ; Symbol
=(format nil "~a USD" A1)           → "100 USD"   ; String
=(range A1 A5)                      → (1 2 3 4 5) ; List of values
=(mapcar #'1+ (range A1 A3))        → (2 3 4)     ; Transformed list
='((:name "Taro") (:age 25))        → Association list
```

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

### Data Types
- Numbers right-aligned, text left-aligned
- Lists displayed inline: `(1 2 3)`
- Symbols uppercase: `HELLO`
- Nil displayed as empty cell

### User Interface
- Resizable columns and rows (drag borders)
- Context menus on headers (right-click)
- Direct input mode (just start typing)
- Multi-line formula input with syntax highlighting
- S-expression auto-formatter (Ctrl+Shift+F)

### Data Management
- Undo/Redo (Ctrl+Z / Ctrl+Y) up to 100 operations
- Native `.ssp` file format
- CSV import/export
- System clipboard (TSV format)
- Range selection (drag or Shift+Arrow)

---

## Requirements

| Component | Version |
|-----------|---------|
| SBCL | 2.0+ recommended |
| Quicklisp | Latest |
| Tcl/Tk | 8.5+ |

---

## Installation

### 1. Install SBCL and Tk

```bash
# Ubuntu/Debian
sudo apt install sbcl tk

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
├── package.lisp     ; Package, constants, structures, accessors
├── formula.lisp     ; Allowed functions, evaluation engine
├── core.lisp        ; Cell ops, dependencies, undo/redo, file I/O
├── ui.lisp          ; Drawing, input, syntax highlighting
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

## Allowed Functions (150+)

### Arithmetic
`+`, `-`, `*`, `/`, `mod`, `rem`, `1+`, `1-`, `floor`, `ceiling`, `round`, `truncate`, `abs`, `max`, `min`, `sqrt`, `expt`, `log`, `exp`, `sin`, `cos`, `tan`, `gcd`, `lcm`

### Comparison
`=`, `/=`, `<`, `>`, `<=`, `>=`, `equal`, `equalp`, `eq`, `eql`

### List Operations
`car`, `cdr`, `cons`, `list`, `first`...`tenth`, `last`, `nth`, `length`, `append`, `reverse`, `member`, `assoc`, `mapcar`, `mapc`, `mapcan`, `reduce`, `remove`, `remove-if`, `remove-if-not`, `find`, `find-if`, `position`, `count`, `sort`, `subseq`, `butlast`, `nthcdr`

### String Operations
`string-upcase`, `string-downcase`, `string-capitalize`, `string-trim`, `concatenate`, `format`, `char`, `subseq`

### Logic
`and`, `or`, `not`, `null`, `if`, `cond`, `when`, `unless`, `case`

### Type Predicates
`numberp`, `stringp`, `listp`, `symbolp`, `atom`, `zerop`, `plusp`, `minusp`, `evenp`, `oddp`

### Higher-Order
`apply`, `funcall`, `lambda`, `mapcar`, `mapc`, `reduce`, `remove-if`, `remove-if-not`, `find-if`, `every`, `some`, `notevery`, `notany`

---

## File Format

### Native Format (.ssp)

```lisp
(:spreadsheet
 :format-version 1
 :metadata (:created "2025-12-20T10:30:00"
            :modified "2025-12-20T11:45:00"
            :app-version "0.6")
 :grid (:rows 26 :cols 14)
 :cells (("A1" 100)
         ("A2" 200 (+ A1 100))
         ("B1" "Hello")))
```

### API

```lisp
(ssp:save "mydata.ssp")
(ssp:load-file "mydata.ssp")
(ssp:new-sheet)
(ssp:export-csv "data.csv")
(ssp:import-csv "data.csv")
```

---

## Architecture (v0.6)

### Structure-Based Design

```lisp
(defstruct cell value formula)
(defstruct ss-state rows cols sheet refs dependents ...)
(defstruct eval-context row col stack env)
```

### Accessor Functions

All global state accessed through accessor functions:
- `(cursor-x)`, `(cursor-y)`, `(move-cursor x y)`
- `(sheet-rows)`, `(sheet-cols)`
- `(get-cell name)`, `(get-cell-raw name)`
- `(get-refs name)`, `(get-dependents name)`

### Dependency Tracking

```
A1: 10
A2: =(+ A1 5)     ; A2 depends on A1
A3: =(* A2 2)     ; A3 depends on A2

When A1 changes → A2 recalculates → A3 recalculates
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
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
