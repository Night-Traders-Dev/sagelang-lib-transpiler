gc_disable()
# -----------------------------------------
# path_resolver.sage - Relative JavaScript module resolution for cjs2esm
# -----------------------------------------

import io
from resolver.package_json import cjs_package_main_entry

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
    let full_path = path_join(base_directory, candidate)
    if not io.exists(full_path) or io.isdir(full_path):
        return nil
    return candidate

proc cjs_has_resolvable_extension(candidate):
    return cjs_path_ends_with(candidate, ".js") or cjs_path_ends_with(candidate, ".cjs") or cjs_path_ends_with(candidate, ".mjs") or cjs_path_ends_with(candidate, ".json")

proc cjs_resolve_file_target(base_directory, candidate):
    let direct = cjs_existing_relative_target(base_directory, candidate)
    if direct != nil:
        return direct
    let extensions = [".js", ".cjs", ".mjs", ".json"]
    var index = 0
    while index < len(extensions):
        let target = cjs_existing_relative_target(base_directory, candidate + extensions[index])
        if target != nil:
            return target
        index = index + 1
    return nil

proc cjs_join_specifier(specifier, suffix):
    if cjs_path_ends_with(specifier, "/"):
        return specifier + suffix
    return specifier + "/" + suffix

proc cjs_resolve_relative_specifier(base_directory, specifier):
    if not cjs_is_relative_specifier(specifier):
        return specifier
    let candidate = cjs_strip_dot_slash(specifier)
    let direct = cjs_resolve_file_target(base_directory, candidate)
    if direct != nil:
        if direct == candidate:
            return specifier
        return specifier + slice(direct, len(candidate), len(direct))
    let directory = path_join(base_directory, candidate)
    if io.isdir(directory):
        let main = cjs_package_main_entry(directory)
        if main != nil and main != "":
            let main_target = cjs_resolve_file_target(directory, main)
            if main_target != nil:
                let suffix = cjs_strip_dot_slash(main_target)
                return cjs_join_specifier(specifier, suffix)
        let indexes = ["index.js", "index.cjs", "index.mjs", "index.json"]
        var index = 0
        while index < len(indexes):
            let target = cjs_existing_relative_target(directory, indexes[index])
            if target != nil:
                return cjs_join_specifier(specifier, indexes[index])
            index = index + 1
    if cjs_has_resolvable_extension(candidate):
        return specifier
    return specifier

proc resolve_import_path(specifier, base_directory):
    if specifier == nil or specifier == "":
        return nil
    if cjs_path_starts_with(specifier, "node:"):
        return specifier
    if cjs_is_relative_specifier(specifier):
        return cjs_resolve_relative_specifier(base_directory, specifier)
    return specifier
