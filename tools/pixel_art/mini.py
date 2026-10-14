"""Carta de mesa (mini, 48x60): a mesma linguagem da carta grande em tamanho que
cabe nas fileiras (×2 no celular = 120 px físicos). O jogo desenha o valor na
aba, os números da barra e os ícones de estado."""
import math
from PIL import Image
from desenho import hexc, sprite, colar_centro, ampliar, contorno
import cartas
import icones
import lich_sprite

W, H = 48, 60
ARTE = (3, 3, 33, 57)          # x0, y0, x1, y1 (exclusivo)
ARTE_CENTRO = (18.0, 33.0)
BARRA = (35, 1, 47, 59)        # inclui o contorno laranja

CINZA, BEGE, PRATA, LARANJA, LARANJA_CLARO, ESCURO = "#9b948a", "#ccbf7c", "#dedede", "#c77d38", "#f79b45", "#1c1c1d"

MINI = {"W": "#ffffff", "S": "#c0c0c0", "G": "#ffd700", "O": "#c77d38", "B": "#8a5a2b"}
ATQ = sprite("""
......W
.....WS
....WS.
.G.WS..
..GS...
.BOG...
B......""", MINI)
HP = sprite("""
.RR.RR.
RhRRRRR
RRRRRRr
.RRRRr.
..RRr..
...r...""", {"R": "#e8455a", "r": "#9c2236", "h": "#ffc0c8"})
ARM = sprite("""
LLLLLLL
LWMMMMd
LWMMMMd
LMMMMMd
.LMMMd.
..LMd..
...d...""", {"L": "#dedede", "W": "#ffffff", "M": "#8a95a8", "d": "#4b5466"})
_GOTA = """
...G...
..GGG..
.GGGGG.
GGhGGGd
GhGGGGd
.GGGGd.
..ddd.."""
VENENO = sprite(_GOTA, {"G": "#3ecf3e", "h": "#c6ff9a", "d": "#1d7a24"})
SANGRAMENTO = sprite(_GOTA, {"G": "#d8303a", "h": "#ffb0a8", "d": "#7a1018"})
ESCUDO = sprite("""
..CCC..
.C...C.
C.h...C
C.....C
C.....c
.C...c.
..ccc..""", {"C": "#7ad8ff", "c": "#3a8fd0", "h": "#ffffff"})
CONGELADO = sprite("""
...W...
.W.W.W.
..WBW..
WWBWBWW
..WBW..
.W.W.W.
...W...""", {"W": "#d8f6ff", "B": "#6fc8ff"})
EXAUSTO = sprite("""
...ZZZZ
.....Z.
....Z..
...ZZZZ
ZZZ....
.Z.....
ZZZ....""", {"Z": "#c8d0e0"})
TEMPORIZADOR = sprite("""
GGGGG
.OyO.
..O..
.O.O.
.OyO.
GGGGG""", {"G": "#ffd27a", "O": "#c0a060", "y": "#ffe9a8"})
GUARDIAO = sprite("""
WWWWWWW
WBBBBBW
WBWWWBW
WBBBBBW
.WBBBW.
..WBW..
...W...""", {"W": "#dedede", "B": "#3a6fd0"})
INVESTIDA = sprite("""
O..O...
.O..O..
..O..O.
...O..O
..O..O.
.O..O..
O..O...""", {"O": "#ffb347"})
ALCANCE = sprite("""
..RRR..
.R...R.
R..R..R
R.RRR.R
R..R..R
.R...R.
..RRR..""", {"R": "#ff6a6a"})
FURTIVO = sprite("""
.......
..PPP..
.P.W.P.
P.WKW.P
.P.W.P.
..PPP..
.......""", {"P": "#a898c8", "W": "#ffffff", "K": "#1c1c1d"})
FURIA = sprite("""
...O...
..OO...
..OYO..
.OYYO.O
.OYWYOO
.OYWYO.
..OOO..""", {"O": "#ff6a1a", "Y": "#ffd23f", "W": "#fff3b0"})
ROUBO_VIDA = sprite("""
W.....W
WW...WW
.WW.WW.
..WRW..
...R...
..RRR..
...R...""", {"W": "#ffffff", "R": "#d8303a"})
SILENCIADA = sprite("""
G.....G
.G...G.
..G.G..
...G...
..G.G..
.G...G.
G.....G""", {"G": "#c08aff"})
ICONES_MINI = [("atq", ATQ), ("hp", HP), ("arm", ARM), ("veneno", VENENO), ("sangramento", SANGRAMENTO),
               ("escudo", ESCUDO), ("congelado", CONGELADO), ("exausto", EXAUSTO), ("temporizador", TEMPORIZADOR),
               ("guardiao", GUARDIAO), ("investida", INVESTIDA), ("alcance", ALCANCE), ("furtivo", FURTIVO),
               ("furia", FURIA), ("roubo_vida", ROUBO_VIDA), ("silenciada", SILENCIADA)]


def moldura(naipe: str, stats: bool = True) -> Image.Image:
    esc, clara, _ = cartas.PALETA[naipe]
    img = Image.new("RGBA", (W, H), hexc(CINZA))
    px = img.load()
    for y in range(1, H - 1):
        for x in range(1, 35):
            px[x, y] = hexc(BEGE)
    # filete prateado por dentro da moldura (como os tracejados da carta grande)
    for x in range(2, 34):
        if x % 4 != 1:
            px[x, 2] = hexc(PRATA)
            px[x, H - 3] = hexc(PRATA)
    for y in range(2, H - 2):
        if y % 4 != 1:
            px[2, y] = hexc(PRATA)
            px[33, y] = hexc(PRATA)
    # área da arte com a faixa diagonal clara
    x0, y0, x1, y1 = ARTE
    for y in range(y0, y1):
        for x in range(x0, x1):
            u, v = x - x0, y - y0
            px[x, y] = hexc(clara) if 14 <= u + v * 0.55 <= 27 else hexc(esc)
    # aba do valor (canto superior esquerdo), chanfrada, com borda clara
    for y in range(3, 15):
        for x in range(3, 16):
            if x + y > 27:
                continue
            borda = x == 15 or y == 14 or x + y == 27
            px[x, y] = hexc(LARANJA_CLARO) if borda else hexc(LARANJA)
    # barra de stats: escura com contorno laranja e cantos chanfrados
    bx0, by0, bx1, by1 = BARRA
    for y in range(by0, by1):
        for x in range(bx0, bx1):
            dx = min(x - bx0, bx1 - 1 - x)
            dy = min(y - by0, by1 - 1 - y)
            if dx + dy < 2:
                continue
            borda = dx == 0 or dy == 0 or dx + dy == 2
            px[x, y] = hexc(LARANJA_CLARO) if borda else hexc(ESCURO)
    # brilhos amarelos nos cantos da moldura (como na carta grande)
    for (cx, cy) in ((1, 1), (34, 1), (1, H - 2), (34, H - 2)):
        px[cx, cy] = hexc("#ffd700")
    if stats:
        colar_centro(img, ATQ, 40.5, 6.0)
        colar_centro(img, HP, 40.5, 23.5)
    else:                                           # instantânea: raio na barra, sem stats
        colar_centro(img, icones.RAIO, 40.5, 10.0)
    return img


def mascara(moldura_img: Image.Image, naipe: str) -> Image.Image:
    esc, clara, _ = cartas.PALETA[naipe]
    alvo = {hexc(esc)[:3], hexc(clara)[:3]}
    m = Image.new("L", (W, H), 0)
    src = moldura_img.load()
    for y in range(H):
        for x in range(W):
            if src[x, y][:3] in alvo:
                m.putpixel((x, y), 255)
    return m


def recortar(img: Image.Image, m: Image.Image) -> Image.Image:
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), m)
    return out


def arte(fonte: dict, naipe: str, tipo: str) -> Image.Image:
    """tipo: n (2-10), a (Ás), j, q, k, inst (instantânea)."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ic = fonte["icones"][naipe]
    sombra = cartas.PALETA[naipe][2]
    cx, cy = ARTE_CENTRO
    if tipo == "n":
        colar_centro(img, contorno(ic, sombra), cx, cy + 2)
    elif tipo == "a":
        colar_centro(img, contorno(ampliar(ic, 2), sombra), cx, cy + 3)
    elif tipo in ("j", "q", "k"):
        emb = {"j": icones.elmo, "q": icones.tiara, "k": icones.coroa}[tipo](cartas.GEMA[naipe])
        colar_centro(img, contorno(emb, sombra), cx, 24)
        colar_centro(img, contorno(ic, sombra), cx, 44)
    elif tipo == "inst":
        colar_centro(img, contorno(ampliar(icones.RAIO, 2), "#5e3a10"), cx, cy)
        colar_centro(img, contorno(ic, sombra), cx + 7, cy + 15)
    return img


def verso() -> Image.Image:
    img = Image.new("RGBA", (W, H), hexc(CINZA))
    px = img.load()
    navy, navy2, ouro = hexc("#040347"), hexc("#0b0a66"), hexc("#c7a52a")
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            px[x, y] = hexc(BEGE)
    for y in range(3, H - 3):
        for x in range(3, W - 3):
            px[x, y] = ouro if ((x + y) % 8 == 0 or (x - y) % 8 == 0) else (navy2 if ((x + y) // 8 + (x - y) // 8) % 2 else navy)
    return img


# ---------------------------------------------------------------- especiais animadas (mini)

QUADROS = 16


def _dither(x, y, v):
    from especiais import dither
    return dither(x, y, v)


def lich_mini(fonte: dict) -> list:
    """Caveira coroada (recorte do sprite grande, 1:1), olhos pulsando, fogo-fantasma e almas."""
    from especiais import OLHOS, FOGO
    base = moldura("paus")
    m = mascara(base, "paus")
    x0, y0, x1, y1 = ARTE
    quadros = []
    for f in range(QUADROS):
        img = base.copy()
        cav = lich_sprite.caveira(OLHOS[f], "#ffffff" if f in (6, 7) else OLHOS[(f + 4) % QUADROS])
        cav = cav.crop((5, 0, 31, 31))                 # caveira, coroa e o começo do manto
        bob = int(round(1.4 * math.sin(2 * math.pi * f / QUADROS)))
        camada = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        colar_centro(camada, contorno(cav, "#050805"), 18.5, 26 + bob)
        px = camada.load()
        # manto se desfaz em pontilhado
        for y in range(36, 46):
            for x in range(x0, x1):
                if px[x, y][3] and not _dither(x, y + f, (44 - y) / 9.0):
                    px[x, y] = (0, 0, 0, 0)
        # fogo-fantasma no pé
        t = 2 * math.pi * f / QUADROS
        for x in range(x0, x1):
            u = (x - x0) / (x1 - x0)
            h = 12 + 3 * math.sin(u * 9 + t) + 2.5 * math.sin(u * 23 - 2 * t) + 1.5 * math.sin(u * 41 + 3 * t)
            for y in range(y1 - 1, int(y1 - h) - 1, -1):
                k = (y1 - 1 - y) / h
                if _dither(x, y, min(1.0, (1 - k) * 1.7)):
                    px[x, y] = FOGO[max(0, min(5, int((1 - k) * 4)))]
        # duas almas em órbita
        for i in range(2):
            a = 2 * math.pi * (f / QUADROS + i / 2.0)
            ax, ay = int(round(18 + 12 * math.cos(a))), int(round(30 + 5 * math.sin(a)))
            px[ax, ay] = FOGO[5]
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                px[ax + dx, ay + dy] = FOGO[4]
        img.alpha_composite(recortar(camada, m))
        quadros.append(img)
    return quadros


def mercador_mini(fonte: dict) -> list:
    """Coroa e ♦ do usuário, moedas girando e caindo, reflexo atravessando a arte."""
    from especiais import lerp
    base = moldura("ouros")
    m = mascara(base, "ouros")
    x0, y0, x1, y1 = ARTE
    coroa = contorno(icones.coroa("#ff3040"), "#5e500a")
    diam = contorno(fonte["icones"]["ouros"], "#5e500a")
    moedas = [contorno(q, "#5e500a") for q in icones.MOEDA]
    quadros = []
    for f in range(QUADROS):
        img = base.copy()
        camada = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        for i in range(4):                               # pilha
            colar_centro(camada, moedas[0 if i % 2 else 1], 7 + i * 7, 52 - (i % 2) * 2)
        colar_centro(camada, coroa, 18, 21)
        colar_centro(camada, diam, 18, 37)
        for i in range(3):                               # moedas caindo (fecham o laço)
            vel = 3 + i
            ciclo = QUADROS * vel
            y = y0 - 6 + ((i * 23 + f * vel) % ciclo) * (y1 - y0 + 6) / ciclo
            colar_centro(camada, moedas[(f + i) % 4], 8 + i * 10, y)
        img.alpha_composite(recortar(camada, m))
        if f <= 9:                                       # reflexo foil
            px = img.load()
            c = x0 + y0 - 8 + f * 10
            for y in range(y0, y1):
                for x in range(x0, x1):
                    d = abs((x + y) - c)
                    if d <= 1 and m.getpixel((x, y)):
                        px[x, y] = lerp(px[x, y], hexc("#fff3b0"), (0.6, 0.3)[d])
        quadros.append(img)
    return quadros
