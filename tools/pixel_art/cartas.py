"""Cartas base: moldura do usuário recolorida por naipe, naipes nas posições do
baralho (2-10 copiados dos arquivos de Ouros), Ás com naipe grande, figuras com
emblema, valores nos cantos e stats na barra lateral."""
import json
import os
from PIL import Image
from desenho import hexc, recolor, colar_centro, escala, ampliar, glifos, texto, contorno, sprite
import icones

W, H = 160, 192
ARTE_RECT = (11, 12, 120, 181)          # área da arte (x0, y0, x1, y1)
CENTRO = (65.5, 96.5)
BARRA_CX = 141.5                         # centro da barra lateral de stats
CANTO_SUP = (15.5, 13.0)                 # centro do valor no canto superior
CANTO_INF = (115.5, 179.0)               # centro do valor no canto inferior
NAIPES = ["ouros", "copas", "espadas", "paus"]
NOME_ARQ = {"ouros": "diamond", "copas": "heart", "espadas": "spade", "paus": "club"}
VALOR_TXT = {11: "J", 12: "Q", 13: "K", 14: "A"}

# área da arte: (escuro, faixa clara, sombra dos naipes). Ouros é a do usuário.
PALETA = {
    "ouros": ("#8a7611", "#ad9415", "#5e500a"),
    "copas": ("#5a1621", "#73202d", "#330a10"),
    "espadas": ("#56627a", "#64718a", "#323a4a"),   # aço: o azul dos naipes contrasta
    "paus": ("#1f4a26", "#2a5f31", "#0f2a13"),
}
GEMA = {"ouros": "#ffef94", "copas": "#ff3040", "espadas": "#4a7dff", "paus": "#3ecf3e"}


def mascara_arte(fonte: dict) -> Image.Image:
    """Máscara (L) dos pixels da área da arte na moldura original: exclui as abas
    dos cantos, que entram na área retangular."""
    if "mascara" not in fonte:
        m = Image.new("L", (W, H), 0)
        src = fonte["moldura"].load()
        for y in range(H):
            for x in range(W):
                if "%02x%02x%02x" % src[x, y][:3] in ("8a7611", "ad9415"):
                    m.putpixel((x, y), 255)
        fonte["mascara"] = m
    return fonte["mascara"]


def recortar_arte(fonte: dict, img: Image.Image) -> Image.Image:
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mascara_arte(fonte))
    return out


def moldura(fonte: dict, naipe: str) -> Image.Image:
    esc, clara, _ = PALETA[naipe]
    return recolor(fonte["moldura"], {"#8a7611": esc, "#ad9415": clara})


def camada_naipes(fonte: dict, naipe: str, valor: int) -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ic = fonte["icones"][naipe]
    sombra = None if naipe == "ouros" else PALETA[naipe][2]
    if 2 <= valor <= 10:
        for cx, cy in fonte["pips"][valor]:
            colar_centro(img, ic, cx, cy, sombra)
    elif valor == 14:
        grande = ampliar(ic, 3)
        colar_centro(img, contorno(grande, PALETA[naipe][2]), CENTRO[0], CENTRO[1])
    else:
        emblema = {11: icones.elmo, 12: icones.tiara, 13: icones.coroa}[valor](GEMA[naipe])
        emblema = ampliar(emblema, 2 if valor == 13 else 3)   # a coroa já é larga
        grande = ampliar(ic, 3)
        colar_centro(img, contorno(emblema, PALETA[naipe][2]), CENTRO[0], 60)
        colar_centro(img, contorno(grande, PALETA[naipe][2]), CENTRO[0], 122)
    return img


def camada_valor(fonte: dict, valor) -> Image.Image:
    g = glifos(fonte["digitos"])
    t = texto(g, VALOR_TXT.get(valor, str(valor)) if isinstance(valor, int) else valor)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    colar_centro(img, t, *CANTO_SUP)
    colar_centro(img, t, *CANTO_INF)
    return img


def camada_stats_icones(instantanea: bool) -> Image.Image:
    """Ícones fixos da barra (o jogo escreve os números por cima)."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    if instantanea:
        colar_centro(img, escala(icones.RAIO, 2), BARRA_CX, 34)
        return img
    colar_centro(img, icones.ATQ, BARRA_CX, 20)
    colar_centro(img, icones.HP, BARRA_CX, 52)
    return img


def camada_stats_valores(fonte: dict, atk: int, hp: int) -> Image.Image:
    """Números de exemplo (os da carta do Baralho Padrão com esse valor e naipe)."""
    g = glifos(fonte["digitos"])
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    colar_centro(img, texto(g, str(atk)), BARRA_CX, 34)
    colar_centro(img, texto(g, str(hp)), BARRA_CX, 65)
    return img


def camada_instantanea(fonte: dict, naipe: str) -> Image.Image:
    """Arte de instantânea: raios saindo do centro, raio grande e o naipe."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    x0, y0, x1, y1 = ARTE_RECT
    claro = hexc(PALETA[naipe][1])
    import math
    for y in range(y0, y1):
        for x in range(x0, x1):
            a = math.atan2(y - CENTRO[1], x - CENTRO[0])
            if int((a + math.pi) / (math.pi / 8)) % 2 == 0:
                px[x, y] = (min(255, claro[0] + 18), min(255, claro[1] + 18), min(255, claro[2] + 18), 255)
    raio = contorno(ampliar(icones.RAIO, 4), "#5e3a10")
    colar_centro(img, raio, CENTRO[0], CENTRO[1] - 6)
    colar_centro(img, contorno(ampliar(fonte["icones"][naipe], 2), PALETA[naipe][2]), CENTRO[0] + 30, CENTRO[1] + 52)
    return recortar_arte(fonte, img)


def verso(fonte: dict) -> Image.Image:
    """Verso das cartas: treliça azul-marinho (cor da moldura base) com corrente dourada."""
    img = Image.new("RGBA", (W, H), hexc("#9b948a"))
    px = img.load()
    for y in range(4, H - 4):
        for x in range(4, W - 4):
            px[x, y] = hexc("#ccbf7c")
    navy, navy2, ouro = hexc("#040347"), hexc("#0b0a66"), hexc("#c7a52a")
    for y in range(10, H - 10):
        for x in range(10, W - 10):
            d = (x + y) % 16
            e = (x - y) % 16
            px[x, y] = ouro if (d == 0 or e == 0) else (navy2 if ((x + y) // 16 + (x - y) // 16) % 2 else navy)
    elo = sprite("""
..GGGGGGG..
.GO.....OG.
GO.......OG
G.........G
G.........G
GO.......OG
.GO.....OG.
..GGGGGGG..""", {"G": "#ffd700", "O": "#c77d38"})
    elo = ampliar(elo, 3)
    for i, dx in enumerate((-26, 0, 26)):
        colar_centro(img, contorno(elo, "#040347"), W / 2 + dx, H / 2)
    for naipe, (cx, cy) in zip(NAIPES, ((30, 30), (130, 30), (30, 162), (130, 162))):
        colar_centro(img, contorno(fonte["icones"][naipe], "#040347"), cx, cy)
    return img


def baralho_padrao() -> dict:
    """(naipe, valor) -> carta do Baralho Padrão (para os números de exemplo)."""
    raiz = os.path.join(os.path.dirname(__file__), "..", "..")
    d = json.load(open(os.path.join(raiz, "data", "cards.json")))
    por_id = {c["id"]: c for c in d["cards"]}
    out = {}
    for cid in d["decks"]["padrao"]["cards"]:
        c = por_id[cid]
        out[(c["suit"], int(c["value"]))] = c
    return out
