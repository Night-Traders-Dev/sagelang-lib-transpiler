gc_disable()
# -----------------------------------------
# visitor.sage - Generic AST walker for cjs2esm
# -----------------------------------------

proc js_visit(node, callbacks):
    if node == nil or type(node) != "dict":
        return true
    if dict_has(callbacks, node["kind"]):
        callbacks[node["kind"]](node)
    if node["kind"] == "Program":
        return js_visit_list(node["body"], callbacks)
    if node["kind"] == "VariableDeclaration":
        return js_visit_list(node["declarators"], callbacks)
    if node["kind"] == "VariableDeclarator":
        return js_visit(node["initializer"], callbacks)
    if node["kind"] == "ImportDeclaration":
        return true
    if node["kind"] == "ExportDefault":
        return js_visit(node["expression"], callbacks)
    if node["kind"] == "ExportNamed":
        return true
    if node["kind"] == "FunctionDeclaration":
        return true
    if node["kind"] == "ClassDeclaration":
        return true
    return true

proc js_visit_list(nodes, callbacks):
    var index = 0
    while index < len(nodes):
        js_visit(nodes[index], callbacks)
        index = index + 1
    return true

proc js_visit_kinds(node, kinds):
    if node == nil or type(node) != "dict":
        return true
    push(kinds, node["kind"])
    if node["kind"] == "Program":
        return js_visit_kind_list(node["body"], kinds)
    if node["kind"] == "VariableDeclaration":
        return js_visit_kind_list(node["declarators"], kinds)
    if node["kind"] == "VariableDeclarator":
        return js_visit_kinds(node["initializer"], kinds)
    if node["kind"] == "ExportDefault":
        return js_visit_kinds(node["expression"], kinds)
    return true

proc js_visit_kind_list(nodes, kinds):
    var index = 0
    while index < len(nodes):
        js_visit_kinds(nodes[index], kinds)
        index = index + 1
    return true
