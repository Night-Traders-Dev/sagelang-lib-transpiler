gc_disable()
# -----------------------------------------
# declarations.sage - ESTree-flavored declaration nodes for cjs2esm
# -----------------------------------------

proc js_program_node(body):
    let node = {}
    node["kind"] = "Program"
    node["body"] = body
    return node

proc js_import_declaration(source, pairs):
    let node = {}
    node["kind"] = "ImportDeclaration"
    node["source"] = source
    node["pairs"] = pairs
    return node

proc js_import_pair(imported, local):
    let pair = {}
    pair["imported"] = imported
    pair["local"] = local
    return pair

proc js_export_default(expression):
    let node = {}
    node["kind"] = "ExportDefault"
    node["expression"] = expression
    return node

proc js_export_named(names):
    let node = {}
    node["kind"] = "ExportNamed"
    node["names"] = names
    return node

proc js_variable_declaration(kind, declarators):
    let node = {}
    node["kind"] = "VariableDeclaration"
    node["declaration_kind"] = kind
    node["declarators"] = declarators
    return node

proc js_variable_declarator(name, initializer):
    let node = {}
    node["kind"] = "VariableDeclarator"
    node["name"] = name
    node["initializer"] = initializer
    return node

proc js_function_declaration(name, async_flag):
    let node = {}
    node["kind"] = "FunctionDeclaration"
    node["name"] = name
    node["async"] = async_flag
    return node

proc js_class_declaration(name):
    let node = {}
    node["kind"] = "ClassDeclaration"
    node["name"] = name
    return node
