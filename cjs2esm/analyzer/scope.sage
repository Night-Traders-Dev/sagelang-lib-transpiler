gc_disable()
# -----------------------------------------
# scope.sage - Lexical scope stack for cjs2esm
# -----------------------------------------

proc cjs_scope_level(level_type, parent):
    let scope = {}
    scope["level"] = level_type
    scope["parent"] = parent
    scope["bindings"] = {}
    return scope

proc cjs_scope_tracker():
    let tracker = {}
    tracker["global"] = cjs_scope_level("global", nil)
    tracker["current"] = tracker["global"]
    tracker["stack"] = [tracker["global"]]
    return tracker

proc cjs_scope_enter(tracker, level_type):
    let child = cjs_scope_level(level_type, tracker["current"])
    push(tracker["stack"], child)
    tracker["current"] = child
    return child

proc cjs_scope_exit(tracker):
    if len(tracker["stack"]) > 1:
        pop(tracker["stack"])
        tracker["current"] = tracker["stack"][len(tracker["stack"]) - 1]
    return tracker["current"]

proc cjs_scope_bind(tracker, name):
    if name == nil or name == "":
        return false
    tracker["current"]["bindings"][name] = true
    return true

proc cjs_scope_lookup(tracker, name):
    var index = len(tracker["stack"]) - 1
    while index >= 0:
        if dict_has(tracker["stack"][index]["bindings"], name):
            return true
        index = index - 1
    return false
