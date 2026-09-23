gc_disable()
# -----------------------------------------
# path_resolver.sage - Relative JavaScript module resolution for cjs2esm
# -----------------------------------------

import io

proc cjs_path_starts_with(value, prefix):
    if value == nil or prefix == nil:
        return false
    if len(value) < len(prefix):
        return false
    return slice(value, 0, len(prefix)) == prefix

proc cjs_path_ends_with(value, suffix):
    if value == nil or suffix == nil:
        return false
    if len(value) < len(suffix):
        return false
    return slice(value, len(value) - len(suffix), len(value)) == suffix

proc cjs_is_relative_specifier(specifier):
    if cjs_path_starts_with(specifier, "./"):
        return true
    if cjs_path_starts_with(specifier, "../"):
        return true
    return false

proc cjs_strip_dot_slash(specifier):
    if cjs_path_starts_with(specifier, "./"):
        return slice(specifier, 2, len(specifier))
    return specifier

proc cjs_existing_relative_target(base_directory, candidate):
    if candidate == nil or candidate == "":
        return nil
    if path_exists(path_join(base_directory, candidate)):
        return candidate
    return nil

proc cjs_resolve_relative_specifier(base_directory, specifier):
    if not cjs_is_relative_specifier(specifier):
        return specifier
    let direct = cjs_existing_relative_target(base_directory, cjs_strip_dot_slash(specifier))
    if direct != nil:
        return specifier
    let javascript = cjs_existing_relative_target(base_directory, cjs_strip_dot_slash(specifier) + ".js")
    if javascript != nil:
        return specifier + ".js"
    let commonjs = cjs_existing_relative_target(base_directory, cjs_strip_dot_slash(specifier) + ".cjs")
    if commonjs != nil:
        return specifier + ".cjs"
    let module_javascript = cjs_existing_relative_target(base_directory, cjs_strip_dot_slash(specifier) + ".mjs")
    if module_javascript != nil:
        return specifier + ".mjs"
    let json = cjs_existing_relative_target(base_directory, cjs_strip_dot_slash(specifier) + ".json")
    if json != nil:
        return specifier + ".json"
    let index = cjs_existing_relative_target(base_directory, path_join(cjs_strip_dot_slash(specifier), "index.js"))
    if index != nil:
        return specifier + "/index.js"
    return specifier

proc resolve_import_path(specifier, base_directory):
    if specifier == nil or specifier == "":
        return nil
    if cjs_path_starts_with(specifier, "node:"):
        return specifier
    if cjs_is_relative_specifier(specifier):
        return cjs_resolve_relative_specifier(base_directory, specifier)
    return specifier
