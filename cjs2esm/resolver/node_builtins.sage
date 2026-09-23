gc_disable()
# -----------------------------------------
# node_builtins.sage - Node.js built-in module list for cjs2esm
# -----------------------------------------

proc cjs_node_builtins():
    return ["assert", "async_hooks", "buffer", "child_process", "cluster", "console", "constants", "crypto", "dgram", "diagnostics_channel", "dns", "domain", "events", "fs", "http", "http2", "https", "inspector", "module", "net", "os", "path", "perf_hooks", "process", "punycode", "querystring", "readline", "repl", "stream", "string_decoder", "sys", "timers", "tls", "trace_events", "tty", "url", "util", "v8", "vm", "wasi", "worker_threads", "zlib"]

proc cjs_is_node_builtin(specifier):
    let bare = specifier
    if cjs_builtin_starts_with(specifier, "node:"):
        bare = slice(specifier, 5, len(specifier))
    let builtins = cjs_node_builtins()
    var index = 0
    while index < len(builtins):
        if builtins[index] == bare:
            return true
        index = index + 1
    return false

proc cjs_builtin_starts_with(value, prefix):
    if value == nil or prefix == nil:
        return false
    if len(value) < len(prefix):
        return false
    return slice(value, 0, len(prefix)) == prefix
