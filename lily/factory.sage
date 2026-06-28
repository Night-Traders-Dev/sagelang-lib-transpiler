from transpiler.lily.sage_to_lily import SageToLilyTranspiler
from transpiler.lily.lily_to_sage import LilyToSageTranspiler

proc get_parser(backend: String) -> Object:
    if backend == "sage_to_lily":
        return SageToLilyTranspiler()
    elif backend == "lily_to_sage":
        return LilyToSageTranspiler()
    else:
        raise "Unknown backend: " + backend
