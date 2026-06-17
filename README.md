# transpiler

## Purpose
Code transformation and transpilation infrastructure for SageLang.

## Features
- **Parsers**: JSON parser, Python AST parser.
- **Emitters**: Extensible emitters for transforming SageLang code to other languages (like Python).

## Usage Example
```sage
import transpiler.python
import transpiler.json_parser

let ast = transpiler.json_parser.parse(json_data)
transpiler.python.emit(ast, "out.py")
```
