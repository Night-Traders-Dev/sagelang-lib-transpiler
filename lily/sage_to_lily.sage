from transpiler.base import Transpiler
import ast

class SageToLilyTranspiler(Transpiler):
    proc init(self):
        self.output = []
        self.indent_level = 0

    proc parse(self, source: String) -> Object:
        # Expected to be parsed externally or we can import parser if needed
        return nil

    proc emit(self, ast_stmts: Object) -> String:
        self.output = []
        self.indent_level = 0
        for stmt in ast_stmts:
            self.emit_stmt(stmt)
        return join(self.output, "")

    proc write(self, text: String):
        push(self.output, text)

    proc write_indent(self):
        for i in range(self.indent_level):
            self.write("    ")

    proc emit_stmt(self, stmt: Object):
        let type = stmt.type
        if type == ast.STMT_LET:
            self.write_indent()
            # Lily uses 'let' for immutable, similar to Sage
            self.write("let ")
            self.write(stmt.name)
            if stmt.initializer != nil:
                self.write(" = ")
                self.emit_expr(stmt.initializer)
            self.write(chr(10))
        elif type == ast.STMT_PROC:
            self.write_indent()
            # Lily syntax: return_type func name(params):
            # Since Sage AST doesn't have strict return types by default on AST nodes, we assume 'var' or omit.
            self.write("var func ")
            self.write(stmt.name)
            self.write("(")
            # emit params
            let count = len(stmt.params)
            for i in range(count):
                self.write("var " + stmt.params[i])
                if i < count - 1:
                    self.write(", ")
            self.write("):")
            self.write(chr(10))
            self.indent_level = self.indent_level + 1
            let body = stmt.body
            for b_stmt in body:
                self.emit_stmt(b_stmt)
            self.indent_level = self.indent_level - 1
        elif type == ast.STMT_EXPRESSION:
            self.write_indent()
            self.emit_expr(stmt.expression)
            self.write(chr(10))
        elif type == ast.STMT_RETURN:
            self.write_indent()
            self.write("return ")
            if stmt.value != nil:
                self.emit_expr(stmt.value)
            self.write(chr(10))
        elif type == ast.STMT_PRINT:
            self.write_indent()
            self.write("print(")
            self.emit_expr(stmt.expression)
            self.write(")")
            self.write(chr(10))
        else:
            self.write_indent()
            self.write("// TODO: Unhandled stmt type " + str(type))
            self.write(chr(10))

    proc emit_expr(self, expr: Object):
        let type = expr.type
        if type == ast.EXPR_NUMBER:
            self.write(str(expr.value))
        elif type == ast.EXPR_STRING:
            self.write(chr(34) + expr.value + chr(34))
        elif type == ast.EXPR_VARIABLE:
            self.write(expr.name)
        elif type == ast.EXPR_BINARY:
            self.emit_expr(expr.left)
            self.write(" " + expr.op + " ")
            self.emit_expr(expr.right)
        elif type == ast.EXPR_CALL:
            self.emit_expr(expr.callee)
            self.write("(")
            let count = len(expr.args)
            for i in range(count):
                self.emit_expr(expr.args[i])
                if i < count - 1:
                    self.write(", ")
            self.write(")")
        else:
            self.write("/* unhandled expr type " + str(type) + " */")

