from transpiler.base import Transpiler

class SageEmitter(Transpiler):
    proc emit(self, node):
        if node["type"] == "Module":
            let code = ""
            for child in node["body"]:
                code = code + self.emit(child) + chr(10)
            return code

        elif node["type"] == "Assign":
            let target = self.emit(node["targets"][0])
            let value = self.emit(node["value"])
            return "let " + target + " = " + value

        elif node["type"] == "FunctionDef":
            return "proc " + node["name"] + "():"

        elif node["type"] == "While":
            let test = self.emit(node["test"])
            let code = "while " + test + ":" + chr(10)
            for child in node["body"]:
                code = code + "    " + self.emit(child) + chr(10)
            return code

        elif node["type"] == "AugAssign":
            let target = self.emit(node["target"])
            let op = node["op"]["type"]
            let value = self.emit(node["value"])
            let op_str = " + "
            if op == "Sub":
                op_str = " - "
            return "let " + target + " = " + target + op_str + value

        elif node["type"] == "List" or node["type"] == "Tuple":
            let elts = ""
            for i in range(len(node["elts"])):
                if i > 0:
                    elts = elts + ", "
                elts = elts + self.emit(node["elts"][i])
            if node["type"] == "List":
                return "[" + elts + "]"
            return "(" + elts + ")"

        elif node["type"] == "Dict":
            let pairs = ""
            for i in range(len(node["keys"])):
                if i > 0:
                    pairs = pairs + ", "
                pairs = pairs + self.emit(node["keys"][i]) + ": " + self.emit(node["values"][i])
            return "{" + pairs + "}"

        elif node["type"] == "Call":
            let func = self.emit(node["func"])
            let args = ""
            for i in range(len(node["args"])):
                if i > 0:
                    args = args + ", "
                args = args + self.emit(node["args"][i])
            return func + "(" + args + ")"

        elif node["type"] == "Name":
            return node["id"]

        elif node["type"] == "Constant":
            return str(node["value"])

        return "/* Unsupported: " + node["type"] + " */"
