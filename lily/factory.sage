from transpiler.lily.sage_to_lily import SageToLilyTranspiler
from transpiler.lily.lily_to_sage import LilyToSageTranspiler

proc get_parser(backend):
    if backend == "sage_to_lily":
        return SageToLilyTranspiler()
    elif backend == "lily_to_sage":
        return LilyToSageTranspiler()
    else:
        print "Error transpiler backend: " + backend
        return nil
