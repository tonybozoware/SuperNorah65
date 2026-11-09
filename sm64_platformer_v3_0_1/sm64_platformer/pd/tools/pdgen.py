# Tiny helper to write Pure Data patches with named objects (Biryani64).
class Patch:
    def __init__(self, w=900, h=700):
        self.lines = [f"#N canvas 40 40 {w} {h} 12;"]
        self.ids = {}
        self.n = 0
        self.conns = []
        self.x = 20
        self.y = 20

    def _add(self, kind, name, text, x, y):
        if x is None:
            x, y = self.x, self.y
            self.y += 34
            if self.y > 660:
                self.y = 20
                self.x += 230
        self.lines.append(f"#X {kind} {x} {y} {text};")
        if name:
            self.ids[name] = self.n
        self.n += 1
        return self.n - 1

    @staticmethod
    def esc(text):
        # Pd file format: dollars, commas and semicolons inside boxes are escaped
        return text.replace("$", "\\$").replace(",", " \\,").replace(";", " \\;")

    def obj(self, name, text, x=None, y=None):
        return self._add("obj", name, self.esc(text), x, y)

    def msg(self, name, text, x=None, y=None):
        return self._add("msg", name, self.esc(text), x, y)

    def comment(self, text, x=None, y=None):
        return self._add("text", None, self.esc(text), x, y)

    def con(self, a, ao, b, bi):
        ia = self.ids[a] if isinstance(a, str) else a
        ib = self.ids[b] if isinstance(b, str) else b
        self.conns.append(f"#X connect {ia} {ao} {ib} {bi};")

    def save(self, path):
        open(path, "w").write("\n".join(self.lines + self.conns) + "\n")
