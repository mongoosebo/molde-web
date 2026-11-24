"""Where tools/build_map.py spends its time: runs it statement by statement and lists the slowest.

    .venv/bin/python tools/profile_build.py            the 40 slowest top-level statements
    .venv/bin/python tools/profile_build.py 2          also inside top-level loops and ifs, two levels down

It runs the real build (and so writes world/ as the build does): not while the game is running.
The list goes to data/build_profile.txt as well.
"""
import ast, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
PATH = os.path.join(HERE, "build_map.py")
DEPTH = int(sys.argv[1]) if len(sys.argv) > 1 else 0
sys.argv = [PATH]
sys.path.insert(0, HERE)
src = open(PATH).read()
tree = ast.parse(src, PATH)
spent = {}          # (first line, last line) -> seconds


class Timer(ast.NodeTransformer):
    """Wraps the statements inside top-level loops and ifs in calls that time them."""

    def wrap(self, body, depth):
        out = []
        for node in body:
            if depth < DEPTH and isinstance(node, (ast.For, ast.While, ast.If, ast.With)):
                node.body = self.wrap(node.body, depth + 1)
                if getattr(node, "orelse", None):
                    node.orelse = self.wrap(node.orelse, depth + 1)
            if isinstance(node, (ast.FunctionDef, ast.ClassDef, ast.Import, ast.ImportFrom, ast.Continue, ast.Break, ast.Return, ast.Global)):
                out.append(node)
                continue
            key = (node.lineno, node.end_lineno)
            start = ast.parse("__t0_%d = __clock()" % node.lineno).body[0]
            stop = ast.parse("__took(%d, %d, __t0_%d)" % (node.lineno, node.end_lineno, node.lineno)).body[0]
            out.append(ast.Try(body=[start, node], handlers=[], orelse=[], finalbody=[stop]))
        return out


def took(a, b, t0):
    spent[(a, b)] = spent.get((a, b), 0.0) + time.perf_counter() - t0


def report():
    lines = src.split("\n")
    rows = sorted(spent.items(), key=lambda kv: -kv[1])[:40]
    text = ["%7.1f s  lines %d-%d  %s" % (s, a, b, lines[a - 1].strip()[:110]) for (a, b), s in rows]
    text.append("%7.1f s  in all (statements inside a timed loop are counted in the loop as well)" % (time.perf_counter() - T0))
    print("\n".join(text))
    open(os.path.join(HERE, "..", "data", "build_profile.txt"), "w").write("\n".join(text) + "\n")


tree.body = Timer().wrap(tree.body, 0)
ast.fix_missing_locations(tree)
T0 = time.perf_counter()
g = {"__name__": "__main__", "__file__": PATH, "__clock": time.perf_counter, "__took": took}
try:
    exec(compile(tree, PATH, "exec"), g)
except SystemExit:
    pass
finally:
    report()
