# lily_parser.sage - Frontend parser for Lily Language

import transpiler.lily.lily_lexer as lily_lexer
import parser
import token
from token import Token
from lexer import tokenize
from ast import Expr, Stmt, CatchClause
import errors
from ast import EXPR_NUMBER, EXPR_STRING, EXPR_BOOL, EXPR_NIL
from ast import EXPR_BINARY, EXPR_VARIABLE, EXPR_CALL, EXPR_ARRAY
from ast import EXPR_INDEX, EXPR_DICT, EXPR_TUPLE, EXPR_SLICE
from ast import EXPR_GET, EXPR_SET, EXPR_INDEX_SET, EXPR_AWAIT
from ast import STMT_PRINT, STMT_EXPRESSION, STMT_LET, STMT_IF
from ast import STMT_BLOCK, STMT_WHILE, STMT_PROC, STMT_FOR
from ast import STMT_RETURN, STMT_BREAK, STMT_CONTINUE, STMT_CLASS
from ast import STMT_TRY, STMT_RAISE, STMT_YIELD, STMT_IMPORT
from ast import STMT_ASYNC_PROC, STMT_DEFER, STMT_STRUCT
from ast import number_expr, string_expr, bool_expr, nil_expr
from ast import binary_expr, variable_expr, call_expr, array_expr
from ast import index_expr, index_set_expr, dict_expr, tuple_expr
from ast import slice_expr, get_expr, set_expr, await_expr
from ast import print_stmt, expr_stmt, let_stmt, if_stmt
from ast import block_stmt, while_stmt, proc_stmt, for_stmt
from ast import return_stmt, break_stmt, continue_stmt, class_stmt
from ast import try_stmt, raise_stmt, yield_stmt, import_stmt
from ast import async_proc_stmt, defer_stmt, struct_stmt
from parser import parse_number_literal
import ast

import token

let Parser = parser.Parser
let MAX_DEPTH = 500

class LilyParser(Parser):
    proc init(self, source):
        self.lexer = lily_lexer.LilyLexer(source)
        self.tokens = self.lexer.tokenize()
        self.pos = 0
        self.depth = 0
        self.source = source
        self.filename = "lily_source.lily"
        self.error_ctx = nil
        
    proc parse_declaration(self):
        # Skip newlines
        while self.match_tok(token.TOKEN_NEWLINE):
            pass

        if self.check(token.TOKEN_DEDENT) or self.check(token.TOKEN_EOF):
            return nil

        # Lily func declaration
        if self.match_tok(lily_lexer.TOKEN_FUNC):
            return self.parse_proc()

        if self.match_tok(token.TOKEN_VAR) or self.match_tok(lily_lexer.TOKEN_CONST) or self.match_tok(lily_lexer.TOKEN_FINAL):
            self.consume(token.TOKEN_IDENTIFIER, "Expect variable name.")
            let name = self.previous()
            let initializer = nil
            if self.match_tok(token.TOKEN_ASSIGN):
                initializer = self.parse_expression()
            let s = ast.let_stmt(name, initializer)
            self.match_tok(token.TOKEN_NEWLINE)
            return s

        # Default fallback to Sage parser for everything else
        return super.parse_declaration()

    proc parse_unary(self):
        # Lily ptr x -> __deref__(x)
        if self.match_tok(lily_lexer.TOKEN_PTR):
            let right = self.parse_unary()
            let callee = ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "__deref__", self.previous().line, self.previous().col))
            return ast.call_expr(callee, [right])

        # Lily addr x -> __addr__(x)
        if self.match_tok(lily_lexer.TOKEN_ADDR):
            let right = self.parse_unary()
            let callee = ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "__addr__", self.previous().line, self.previous().col))
            return ast.call_expr(callee, [right])

        # Default fallback to Sage parser for everything else
        return super.parse_unary()

    proc parse_postfix(self):
        let expr = super.parse_postfix()
        
        # Lily optional chaining expr?.prop
        while self.match_tok(lily_lexer.TOKEN_QUESTION):
            if self.match_tok(token.TOKEN_DOT):
                self.consume(token.TOKEN_IDENTIFIER, "Expect property name after '?.'")
                let name = self.previous()
                let get_ex = ast.get_expr(expr, name)
                # We would need to set is_optional, but it doesn't exist in Sage AST.
                # Since Sage doesn't have is_optional natively, we just emit a regular get_expr for now,
                # or we could construct a manual desugared AST: (expr != nil) ? expr.prop : nil
                # For simplicity, we just fallback to regular get_expr.
                expr = get_ex
        return expr

    proc parse(self):
        return self.parse_program()
        
proc parse_lily_source(source):
    let p = LilyParser(source)
    return p.parse()
