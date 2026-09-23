gc_disable()
# -----------------------------------------
# pass_exports.sage - ESM export footer synthesis for cjs2esm
# -----------------------------------------

proc cjs_unique_export_names(names):
    let unique = []
    var index = 0
    while index < len(names):
        let candidate = names[index]
        var seen = false
        var check = 0
        while check < len(unique):
            if unique[check] == candidate:
                seen = true
            check = check + 1
        if not seen:
            push(unique, candidate)
        index = index + 1
    return unique

proc cjs_export_footer(names):
    let unique = cjs_unique_export_names(names)
    let footer = chr(10) + ";" + chr(10) + "export default module.exports;" + chr(10)
    var index = 0
    while index < len(unique):
        footer = footer + "export const " + unique[index] + " = module.exports." + unique[index] + ";" + chr(10)
        index = index + 1
    return footer
