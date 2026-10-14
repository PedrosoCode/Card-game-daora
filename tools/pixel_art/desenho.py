"""Utilitários de pixel art: sprites escritos como texto, recolorir, sombra,
escala inteira e texto com os dígitos/letras da moldura."""
from PIL import Image


def hexc(h: str, a: int = 255) -> tuple:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def sprite(linhas: str, pal: dict) -> Image.Image:
    """Sprite a partir de texto: cada caractere é uma cor da paleta ('.' = vazio)."""
    rows = [r for r in linhas.strip("\n").split("\n")]
    rows = [r.strip() for r in rows]
    w = max(len(r) for r in rows)
    img = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != "." and ch != " ":
                img.putpixel((x, y), hexc(pal[ch]) if isinstance(pal[ch], str) else pal[ch])
    return img


def recolor(img: Image.Image, mapa: dict) -> Image.Image:
    """Troca cores exatas: {'#8a7611': '#5c1a24', ...}."""
    m = {hexc(k)[:3]: hexc(v) for k, v in mapa.items()}
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            p = px[x, y]
            if p[3] and p[:3] in m:
                px[x, y] = m[p[:3]]
    return out


def tint(img: Image.Image, cor: str) -> Image.Image:
    """Silhueta de uma cor (mantém o alfa)."""
    c = hexc(cor)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    src = img.load()
    px = out.load()
    for y in range(img.height):
        for x in range(img.width):
            if src[x, y][3]:
                px[x, y] = (c[0], c[1], c[2], src[x, y][3])
    return out


def escala(img: Image.Image, k: int) -> Image.Image:
    return img.resize((img.width * k, img.height * k), Image.NEAREST)


def colar(base: Image.Image, img: Image.Image, x: int, y: int) -> None:
    base.alpha_composite(img, (int(x), int(y)))


def colar_centro(base: Image.Image, img: Image.Image, cx: float, cy: float, sombra: str = None) -> None:
    x = int(round(cx - img.width / 2.0))
    y = int(round(cy - img.height / 2.0))
    if sombra:
        colar(base, tint(img, sombra), x + 1, y + 1)
    colar(base, img, x, y)


def contorno(img: Image.Image, cor: str) -> Image.Image:
    """Contorno de 1 px (4-vizinhança) em volta do que é opaco."""
    c = hexc(cor)
    w, h = img.size
    out = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    src = img.load()
    px = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3]:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    px[x + 1 + dx, y + 1 + dy] = c
    out.alpha_composite(img, (1, 1))
    return out


# ---------------------------------------------------------------- letras (estilo dos dígitos: 9 px, traço de 1 px)

LETRAS = {
    "J": """
..###
....#
....#
....#
....#
....#
#...#
#...#
.###.""",
    "Q": """
.###.
#...#
#...#
#...#
#...#
#...#
#.#.#
#..#.
.##.#""",
    "K": """
#...#
#..#.
#.#..
##...
##...
#.#..
#..#.
#...#
#...#""",
    "+": """
.....
.....
..#..
..#..
#####
..#..
..#..
.....
.....""",
    "-": """
.....
.....
.....
.....
#####
.....
.....
.....
.....""",
    "Z": """
...##
..##.
.##..
####.
.####
..##.
.##..
.#...
#....""",
    "A": """
..#..
.#.#.
#...#
#...#
#...#
#####
#...#
#...#
#...#""",
}


def glifos(digitos: dict) -> dict:
    g = dict(digitos)
    for k, v in LETRAS.items():
        g[k] = sprite(v, {"#": "#ffffff"})
    return g


def texto(g: dict, s: str, espaco: int = 2) -> Image.Image:
    partes = [g[ch] for ch in s]
    w = sum(p.width for p in partes) + espaco * (len(partes) - 1)
    h = max(p.height for p in partes)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    x = 0
    for p in partes:
        img.alpha_composite(p, (x, 0))
        x += p.width + espaco
    return img


# ---------------------------------------------------------------- Scale2x / Scale3x (EPX): ampliar pixel art sem "escadinha"

def scale2x(img: Image.Image) -> Image.Image:
    w, h = img.size
    s = img.load()
    out = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    o = out.load()

    def p(x, y):
        return s[min(max(x, 0), w - 1), min(max(y, 0), h - 1)]
    for y in range(h):
        for x in range(w):
            e = s[x, y]
            b, d, f, hh = p(x, y - 1), p(x - 1, y), p(x + 1, y), p(x, y + 1)
            e0 = d if (d == b and b != f and d != hh) else e
            e1 = f if (b == f and b != d and f != hh) else e
            e2 = d if (d == hh and d != b and hh != f) else e
            e3 = f if (hh == f and d != hh and b != f) else e
            o[2 * x, 2 * y], o[2 * x + 1, 2 * y], o[2 * x, 2 * y + 1], o[2 * x + 1, 2 * y + 1] = e0, e1, e2, e3
    return out


def scale3x(img: Image.Image) -> Image.Image:
    w, h = img.size
    s = img.load()
    out = Image.new("RGBA", (w * 3, h * 3), (0, 0, 0, 0))
    o = out.load()

    def p(x, y):
        return s[min(max(x, 0), w - 1), min(max(y, 0), h - 1)]
    for y in range(h):
        for x in range(w):
            a, b, c = p(x - 1, y - 1), p(x, y - 1), p(x + 1, y - 1)
            d, e, f = p(x - 1, y), p(x, y), p(x + 1, y)
            g, hh, i = p(x - 1, y + 1), p(x, y + 1), p(x + 1, y + 1)
            r = [e] * 9
            if b != hh and d != f:
                r[0] = d if d == b else e
                r[1] = b if (d == b and e != c) or (b == f and e != a) else e
                r[2] = f if b == f else e
                r[3] = d if (d == b and e != g) or (d == hh and e != a) else e
                r[5] = f if (b == f and e != i) or (hh == f and e != c) else e
                r[6] = d if d == hh else e
                r[7] = hh if (d == hh and e != i) or (hh == f and e != g) else e
                r[8] = f if hh == f else e
            for k in range(9):
                o[3 * x + k % 3, 3 * y + k // 3] = r[k]
    return out


def ampliar(img: Image.Image, k: int) -> Image.Image:
    """×2, ×3 ou ×4 com Scale2x/Scale3x (×4 = Scale2x duas vezes)."""
    if k == 2:
        return scale2x(img)
    if k == 3:
        return scale3x(img)
    if k == 4:
        return scale2x(scale2x(img))
    return escala(img, k)
