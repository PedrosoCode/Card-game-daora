"""Animações de efeito em pixel art (folhas de quadros). Cada função devolve a
lista de quadros (RGBA). Fades por pontilhado (Bayer), paletas curtas."""
import math
import random
from PIL import Image
from desenho import hexc, sprite, ampliar, colar_centro
from especiais import dither


def _rampa(*cores):
    return [hexc(c) for c in cores]


def _put(px, w, h, x, y, cor):
    x, y = int(round(x)), int(round(y))
    if 0 <= x < w and 0 <= y < h:
        px[x, y] = cor


def _disco(px, w, h, cx, cy, r, cor, dens=1.0, t=0):
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r and dither(x, y + t, dens):
                _put(px, w, h, x, y, cor)


def _anel(px, w, h, cx, cy, r, esp, cor, dens=1.0):
    for y in range(int(cy - r - esp - 1), int(cy + r + esp + 2)):
        for x in range(int(cx - r - esp - 1), int(cx + r + esp + 2)):
            d = math.hypot(x - cx, y - cy)
            if r - esp <= d <= r and dither(x, y, dens):
                _put(px, w, h, x, y, cor)


# ---------------------------------------------------------------- corte (ataque)

def corte():
    W = H = 48
    cores = _rampa("#ffffff", "#fff3b0", "#ffc04a", "#c8641e")
    out = []
    for f in range(7):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        px = img.load()
        fim = min(1.0, (f + 1) / 4.0)                      # o arco cresce nos 4 primeiros quadros
        some = max(0.0, (f - 3) / 3.0)                     # e se desfaz nos 3 últimos
        a0, a1 = math.radians(200), math.radians(200 + 150 * fim)
        n = 140
        for i in range(n):
            a = a0 + (a1 - a0) * i / n
            k = i / n                                      # 0 = cauda, 1 = ponta
            esp = 1 + int(6 * math.sin(math.pi * (0.25 + 0.75 * k)))
            for e in range(esp + 4):
                r = 20 - e
                x, y = 24 + r * math.cos(a), 26 + r * math.sin(a) * 0.8
                if e < esp:                                # lâmina: branco no fio, laranja por dentro
                    cor = cores[0] if e == 0 else (cores[1] if e < esp * 0.6 else cores[2])
                    dens = 1.0 - some
                else:                                      # rastro de movimento pontilhado
                    cor = cores[3]
                    dens = (0.45 - 0.1 * (e - esp)) * (1.0 - some) * k
                if dither(int(round(x)), int(round(y)), dens):
                    _put(px, W, H, x, y, cor)
        if f >= 3:                                         # faíscas na ponta
            for i in range(5):
                a = a1 + (i - 2) * 0.35
                r = 20 + (f - 2) * 3
                _put(px, W, H, 24 + r * math.cos(a), 26 + r * math.sin(a) * 0.8, cores[1] if f < 5 else cores[2])
        out.append(img)
    return out


# ---------------------------------------------------------------- impacto (dano)

def impacto():
    W = H = 48
    cores = _rampa("#ffffff", "#fff3b0", "#ffb347", "#e04a1e", "#7a2410")
    out = []
    rnd = random.Random(3)
    faiscas = [(rnd.uniform(0, 2 * math.pi), rnd.uniform(1.6, 3.2)) for _ in range(10)]
    for f in range(6):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        px = img.load()
        c = 24
        if f == 0:
            _disco(px, W, H, c, c, 4, cores[0])
        if 1 <= f <= 3:
            r = (6, 10, 13)[f - 1]
            dens = (1.0, 0.8, 0.45)[f - 1]
            _anel(px, W, H, c, c, r, 2, cores[min(4, f)], dens)
            for i in range(8):                             # raios da estrela
                a = i * math.pi / 4 + (0.2 if f > 1 else 0)
                comp = (9, 15, 18)[f - 1] if i % 2 == 0 else (6, 10, 12)[f - 1]
                for d in range(2, comp):
                    if dither(int(c + d * math.cos(a)), int(c + d * math.sin(a)), dens * (1 - d / (comp + 2))):
                        _put(px, W, H, c + d * math.cos(a), c + d * math.sin(a), cores[0] if d < comp / 2 else cores[2])
            if f == 1:
                _disco(px, W, H, c, c, 3, cores[0])
        for a, v in faiscas:
            if f >= 2:
                d = 6 + v * (f - 1) * 2.2
                cor = cores[1] if f < 4 else (cores[2] if f < 5 else cores[3])
                _put(px, W, H, c + d * math.cos(a), c + d * math.sin(a), cor)
        out.append(img)
    return out


# ---------------------------------------------------------------- explosão de fogo (Bola de Fogo, Piromante)

def fogo():
    W = H = 64
    fogo_c = _rampa("#ffffff", "#fff3b0", "#ffd23f", "#ff8c1a", "#e0401a", "#8a1a10")
    fumaca = _rampa("#6b6470", "#4a4450", "#2e2a33")
    out = []
    rnd = random.Random(7)
    brasas = [(rnd.uniform(0, 2 * math.pi), rnd.uniform(0.8, 2.2), rnd.uniform(0.5, 1.5)) for _ in range(14)]
    for f in range(10):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        px = img.load()
        cx, cy = 32, 34
        raio = (5, 10, 14, 17, 19, 20, 20, 20, 20, 20)[f]
        calor = max(0.0, 1.0 - f / 6.0)                    # 1 = branco, 0 = fumaça
        for y in range(H):
            for x in range(W):
                d = math.hypot(x - cx, (y - cy) * 1.1)
                ruido = 2.5 * math.sin(x * 0.7 + f) + 2.5 * math.cos(y * 0.6 - f * 1.3)
                if d > raio + ruido:
                    continue
                k = d / max(1.0, raio + ruido)              # 0 no centro
                if f < 6:
                    idx = int((k * 0.7 + (1 - calor) * 0.6) * (len(fogo_c) - 1))
                    if dither(x, y, 1.0 if k < 0.8 else 0.6):
                        _put(px, W, H, x, y, fogo_c[min(len(fogo_c) - 1, idx)])
                else:
                    dens = 1.0 - (f - 5) / 5.0 - k * 0.3
                    if dither(x, y - f, dens):
                        _put(px, W, H, x, y - (f - 5) * 2, fumaca[min(2, int(k * 3))])
        for a, v, sub in brasas:
            if f >= 2:
                d = 8 + v * f * 2.4
                _put(px, W, H, cx + d * math.cos(a), cy + d * math.sin(a) - sub * f, fogo_c[2] if f < 6 else fogo_c[4])
        out.append(img)
    return out


# ---------------------------------------------------------------- cura

CRUZ = sprite("""
.G.
GWG
.G.""", {"G": "#5fe05a", "W": "#ffffff"})
CRUZ_GRANDE = sprite("""
..GG..
..GG..
GGWWGG
GGWWGG
..GG..
..GG..""", {"G": "#5fe05a", "W": "#e8ffe0"})


def cura():
    W, H = 48, 64
    luz = _rampa("#efffe8", "#b6ff9a", "#5fe05a")
    out = []
    rnd = random.Random(11)
    cruzes = [(rnd.uniform(8, 40), rnd.uniform(0, 1), rnd.choice((0, 0, 1))) for _ in range(9)]
    for f in range(10):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        px = img.load()
        brilho = math.sin(math.pi * f / 9.0)               # coluna de luz acende e apaga
        for y in range(H):
            for x in range(W):
                d = abs(x - 24) / 14.0
                if d < 1 and dither(x, y + f, brilho * (1 - d) * 0.55 * (y / H + 0.3)):
                    _put(px, W, H, x, y, luz[2] if d > 0.5 else luz[1])
        for x0, fase, grande in cruzes:
            t = (f / 10.0 + fase) % 1.0
            y = H - 6 - t * (H - 10)
            spr = CRUZ_GRANDE if grande else CRUZ
            if t < 0.85:
                img.alpha_composite(spr, (int(x0 - spr.width / 2), int(y)))
        out.append(img)
    return out


# ---------------------------------------------------------------- veneno

def veneno():
    W = H = 48
    verde = _rampa("#c6ff9a", "#5fe05a", "#2aa82e", "#1d7a24", "#0f3a14")
    out = []
    rnd = random.Random(5)
    bolhas = [(rnd.uniform(10, 38), rnd.uniform(0, 1), rnd.choice((1, 2, 2, 3))) for _ in range(9)]
    for f in range(10):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        px = img.load()
        # névoa tóxica no pé
        for y in range(30, H):
            for x in range(W):
                ondas = 3 * math.sin(x * 0.3 + f * 0.63)
                if y > 36 + ondas and dither(x, y, 0.5 * (y - 30) / 18.0):
                    _put(px, W, H, x, y, verde[3] if (x + y) % 3 else verde[2])
        for x0, fase, r in bolhas:
            t = (f / 10.0 + fase) % 1.0
            y = H - 8 - t * 34
            x = x0 + 2 * math.sin(t * 6.3)
            if t < 0.8:
                _anel(px, W, H, x, y, r + 0.5, 1, verde[1])
                _put(px, W, H, x - r * 0.4, y - r * 0.4, verde[0])
            elif t < 0.92:                                 # estoura
                for i in range(6):
                    a = i * math.pi / 3
                    _put(px, W, H, x + (r + 2) * math.cos(a), y + (r + 2) * math.sin(a), verde[0])
        out.append(img)
    return out


# ---------------------------------------------------------------- escudo / armadura

def escudo():
    W = H = 48
    azul = _rampa("#ffffff", "#bff0ff", "#7ad8ff", "#3a8fd0", "#1d4f80")
    out = []
    for f in range(8):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        px = img.load()
        cresce = min(1.0, (f + 1) / 3.0)
        some = max(0.0, (f - 4) / 3.0)
        for y in range(H):
            for x in range(W):
                # escudo heráldico: topo reto, ponta embaixo
                u, v = (x - 24) / 17.0, (y - 22) / 20.0
                dentro = (abs(u) <= cresce and -1 <= v <= 0.2) or (v > 0.2 and abs(u) <= cresce * (1 - (v - 0.2) / 0.85))
                if not dentro or v > 1.05:
                    continue
                borda = abs(u) > cresce - 0.12 or v < -0.9 or (v > 0.2 and abs(u) > cresce * (1 - (v - 0.2) / 0.85) - 0.12)
                if borda:
                    if dither(x, y, 1.0 - some):
                        _put(px, W, H, x, y, azul[2] if f < 3 else azul[3])
                else:
                    # reflexo diagonal que atravessa o escudo
                    faixa = abs((x + y) - (8 + f * 10)) <= 2
                    if faixa and dither(x, y, 0.9 - some):
                        _put(px, W, H, x, y, azul[0])
                    elif dither(x, y, 0.35 - some * 0.35):
                        _put(px, W, H, x, y, azul[3])
        out.append(img)
    return out


# ---------------------------------------------------------------- congelar

def gelo():
    W = H = 48
    gelo_c = _rampa("#ffffff", "#d8f6ff", "#9fe0ff", "#5fb4e8", "#2e6fa8")
    out = []
    for f in range(8):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        px = img.load()
        cresce = min(1.0, (f + 1) / 4.0)
        some = max(0.0, (f - 5) / 3.0)
        for i in range(6):                                 # 6 lâminas de gelo
            a = i * math.pi / 3 + math.pi / 6
            comp = 18 * cresce
            for d in range(int(comp)):
                x, y = 24 + d * math.cos(a), 24 + d * math.sin(a)
                if dither(int(x), int(y), 1.0 - some):
                    _put(px, W, H, x, y, gelo_c[1] if d < comp * 0.7 else gelo_c[0])
                    if d % 5 == 3 and d < comp - 2:        # ramos
                        for s in (-1, 1):
                            b = a + s * 0.9
                            for e in range(1, 4):
                                _put(px, W, H, x + e * math.cos(b), y + e * math.sin(b), gelo_c[2])
        # cristais pequenos em volta
        for i in range(8):
            a = i * math.pi / 4 + f * 0.1
            r = 20 + (i % 2) * 3
            if f >= 2 and dither(i, f, 1.0 - some):
                _put(px, W, H, 24 + r * math.cos(a), 24 + r * math.sin(a), gelo_c[0])
        _disco(px, W, H, 24, 24, 2 + cresce * 2, gelo_c[0], 1.0 - some)
        out.append(img)
    return out


# ---------------------------------------------------------------- morte

CAVEIRINHA = sprite("""
.WWWWW.
WWWWWWW
WKKWKKW
WKKWKKW
WWWKWWW
.WWWWW.
.W.W.W.""", {"W": "#ece6cc", "K": "#1a1020"})


def morte():
    W = H = 48
    fum = _rampa("#8a6aa8", "#5a3f78", "#3a2850", "#1f1530")
    out = []
    rnd = random.Random(9)
    bolas = [(rnd.uniform(-12, 12), rnd.uniform(-6, 8), rnd.uniform(5, 9)) for _ in range(7)]
    for f in range(10):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        px = img.load()
        cresce = min(1.0, (f + 1) / 4.0)
        some = max(0.0, (f - 4) / 5.0)
        for dx, dy, r in bolas:
            cx, cy = 24 + dx * (0.6 + 0.6 * cresce), 30 + dy - f * 1.2
            rr = r * cresce
            for y in range(int(cy - rr), int(cy + rr) + 1):
                for x in range(int(cx - rr), int(cx + rr) + 1):
                    d = math.hypot(x - cx, y - cy) / max(rr, 1)
                    if d <= 1 and dither(x, y + f, (1.0 - some) * (1.1 - d * 0.6)):
                        _put(px, W, H, x, y, fum[min(3, int(d * 2.5 + some * 1.5))])
        if 1 <= f <= 8:                                    # caveira sobe e some
            cav = ampliar(CAVEIRINHA, 2)
            y = 22 - f * 2
            if f > 6:
                cav2 = Image.new("RGBA", cav.size, (0, 0, 0, 0))
                for yy in range(cav.height):
                    for xx in range(cav.width):
                        if cav.getpixel((xx, yy))[3] and dither(xx, yy, 1.0 - (f - 6) / 3.0):
                            cav2.putpixel((xx, yy), cav.getpixel((xx, yy)))
                cav = cav2
            colar_centro(img, cav, 24, y)
        out.append(img)
    return out


TODOS = {"corte": corte, "impacto": impacto, "fogo": fogo, "cura": cura,
         "veneno": veneno, "escudo": escudo, "gelo": gelo, "morte": morte}
