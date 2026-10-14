"""Ícones escritos à mão (texto -> pixels) no estilo da moldura."""
from desenho import sprite

METAL = {"W": "#ffffff", "S": "#c0c0c0", "D": "#7d7d88", "G": "#ffd700", "O": "#c77d38", "B": "#8a5a2b"}

ATQ = sprite("""
...........W
..........WS
.........WS.
........WS..
.......WS...
..G...WS....
...G.WS.....
....OS......
...BOG......
..B...G.....
.O..........
G...........""", METAL)

HP = sprite("""
.RR...RR.
RhRR.RRRR
RhRRRRRRR
RRRRRRRRr
.RRRRRRr.
..RRRRr..
...RRr...
....r....""", {"R": "#e8455a", "r": "#9c2236", "h": "#ffc0c8"})

ARM = sprite("""
LLLLLLLLL
LWWLMMMMd
LWLMMMMMd
LLMMMMMMd
LMMMMMMMd
.LMMMMMd.
.LMMMMMd.
..LMMMd..
...LMd...
....d....""", {"L": "#dedede", "W": "#ffffff", "M": "#8a95a8", "d": "#4b5466"})

_GOTA = """
....G....
...GGG...
..GGGGG..
.GGhGGGG.
.GhGGGGd.
.GGGGGGd.
..GGGGd..
...ddd..."""
VENENO = sprite(_GOTA, {"G": "#3ecf3e", "h": "#c6ff9a", "d": "#1d7a24"})
SANGRAMENTO = sprite(_GOTA, {"G": "#d8303a", "h": "#ffb0a8", "d": "#7a1018"})

ESCUDO = sprite("""
..CCCCC..
.C.....C.
C..hh...C
C.h.....C
C.......C
C.......C
C......cC
.C....cC.
..CCCCC..""", {"C": "#7ad8ff", "c": "#3a8fd0", "h": "#ffffff"})

CONGELADO = sprite("""
....W....
.W..W..W.
..W.W.W..
...BWB...
WWWWWWWWW
...BWB...
..W.W.W..
.W..W..W.
....W....""", {"W": "#d8f6ff", "B": "#6fc8ff"})

EXAUSTO = sprite("""
....ZZZZ.
.......Z.
......Z..
.....ZZZZ
ZZZ......
..Z......
.Z.......
ZZZ......""", {"Z": "#9aa4b8"})

TEMPORIZADOR = sprite("""
GGGGGGG
.O...O.
..OyO..
...O...
..O.O..
.O.y.O.
.OyyyO.
GGGGGGG""", {"G": "#ffd27a", "O": "#c0a060", "y": "#ffe9a8"})

RAIO = sprite("""
.....GGG
....GGG.
...GGG..
..GGG...
.GGGGGGG
.....GG.
....GG..
...GG...
..GG....
.GO.....
GO......""", {"G": "#ffd700", "O": "#c77d38"})

# ---------------------------------------------------------------- emblemas das figuras (cor da gema = naipe)

def coroa(gema: str) -> object:
    return sprite("""
G.........G.........G
GG.......GgG.......GG
GOG.....GgxgG.....GOG
GOOG...GGgggGG...GOOG
GOOOG.GOOGGGOOG.GOOOG
GOOOOGOOOOOOOOOGOOOOG
GOOOOOOOOOOOOOOOOOOOG
GGGGGGGGGGGGGGGGGGGGG
GxOxOxOxOxOxOxOxOxOxG
GGGGGGGGGGGGGGGGGGGGG""", {"G": "#ffd700", "O": "#c77d38", "g": gema, "x": "#fff4c0"})


def tiara(gema: str) -> object:
    return sprite("""
.......G.......
......GgG......
..G..GgxgG..G..
.GgG.GGgGG.GgG.
GGGGGGGGGGGGGGG
GOOxOOOxOOOxOOG
.GGGGGGGGGGGGG.""", {"G": "#ffd700", "O": "#c77d38", "g": gema, "x": "#fff4c0"})


def elmo(pluma: str) -> object:
    return sprite("""
......pp.........
.....pPPp........
....pPPPp........
....pPPp.........
...SSSSSSS.......
..SWWSSSSSD......
.SWWSSSSSSSD.....
.SWSSSSSSSSD.....
.SSDDDDDDDSD.....
.SS.......SD.....
.SSDDDDDDDSD.....
.SSSSSSSSSSD.....
..SSSSSSSSD......
...DDDDDDD.......""", {"S": "#c0c0c0", "W": "#ffffff", "D": "#6d6d78", "p": pluma, "P": pluma})


# ---------------------------------------------------------------- moeda (Mercador-Rei): 4 quadros girando

MOEDA = [
    sprite("""
.GGGG.
GgYYgG
GYxYYO
GYYYYO
GgYYgO
.OOOO.""", {"G": "#ffd700", "g": "#ffe680", "Y": "#f5c400", "x": "#fffbe0", "O": "#b8860b"}),
    sprite("""
.GGG.
GYxYO
GYYYO
GYYYO
GYYYO
.OOO.""", {"G": "#ffd700", "Y": "#f5c400", "x": "#fffbe0", "O": "#b8860b"}),
    sprite("""
GG
GO
GO
GO
GO
GO""", {"G": "#ffe680", "O": "#b8860b"}),
    sprite("""
.GGG.
OYYYG
OYYYG
OYYYG
OYxYG
.OOO.""", {"G": "#ffd700", "Y": "#f5c400", "x": "#fffbe0", "O": "#b8860b"}),
]
