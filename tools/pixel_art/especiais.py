"""Cartas especiais animadas (estilo cartas premium do Gwent, em pixel art).
Cada uma devolve a lista de quadros da camada de arte (160x192, transparente fora
da área da arte); moldura, valor e stats são as camadas normais da carta base."""
import math
from PIL import Image
from desenho import hexc, colar_centro, escala, ampliar, sprite, contorno
import cartas
import icones
import lich_sprite

QUADROS = 16
X0, Y0, X1, Y1 = cartas.ARTE_RECT

# dithering ordenado 4x4 (transições "pixeladas" em vez de transparência suave)
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def dither(x: int, y: int, v: float) -> bool:
    return v * 16.0 > BAYER[y % 4][x % 4] + 0.5


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (255,)


def brilho(cx: float, cy: float, r: int, cor: str) -> Image.Image:
    """Estrelinha de 4 pontas."""
    s = r * 2 + 1
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    c = hexc(cor)
    for i in range(-r, r + 1):
        img.putpixel((r + i, r), c)
        img.putpixel((r, r + i), c)
    img.putpixel((r, r), (255, 255, 255, 255))
    return img


_FONTE = {}


def area(img: Image.Image) -> Image.Image:
    """Recorta para dentro da área da arte (sem as abas dos cantos)."""
    return cartas.recortar_arte(_FONTE, img)


# ================================================================ Lich (A de Paus)

OLHOS = ["#1d7a24", "#2aa82e", "#3ecf3e", "#7cf06a", "#c6ff9a", "#ffffff", "#c6ff9a", "#7cf06a",
         "#3ecf3e", "#2aa82e", "#1d7a24", "#1d7a24", "#2aa82e", "#3ecf3e", "#2aa82e", "#1d7a24"]
FOGO = [hexc(c) for c in ("#0f3a14", "#1d7a24", "#2fae36", "#5fe05a", "#b6ff9a", "#efffe8")]


def _fogo_fantasma(img: Image.Image, f: int) -> None:
    """Chamas verdes subindo do pé da arte; altura por coluna = soma de senos
    com frequências inteiras no tempo (o laço de 16 quadros fecha sem emenda)."""
    px = img.load()
    t = 2 * math.pi * f / QUADROS
    for x in range(X0, X1):
        u = (x - X0) / (X1 - X0)
        h = (40 + 9 * math.sin(u * 9.0 + t) + 8 * math.sin(u * 23.0 - 2 * t)
             + 6 * math.sin(u * 41.0 + 3 * t) + 4 * math.sin(u * 67.0 - 4 * t))
        h *= 0.7 + 0.3 * math.sin(math.pi * u)          # mais alto no meio
        for y in range(Y1 - 1, int(Y1 - h) - 1, -1):
            k = (Y1 - 1 - y) / h                           # 0 na base, 1 na ponta
            v = 1.0 - k
            if not dither(x, y, min(1.0, v * 1.6)):
                continue
            idx = min(len(FOGO) - 1, int((1.0 - k) * (len(FOGO) - 1) * 0.8 + (1 if (x + y + f) % 7 == 0 else 0)))
            px[x, y] = FOGO[max(0, idx)]


def _fagulhas(img: Image.Image, f: int) -> None:
    for i in range(16):
        vel = 3 + i % 3                                    # px por quadro
        ciclo = QUADROS * vel                              # fecha o laço
        y = Y1 - 4 - ((i * 37 + f * vel) % ciclo)
        x = X0 + 6 + (i * 53) % (X1 - X0 - 12) + int(round(2 * math.sin(2 * math.pi * (f + i * 3) / QUADROS)))
        idade = ((i * 37 + f * vel) % ciclo) / ciclo
        cor = FOGO[5] if idade < 0.25 else (FOGO[4] if idade < 0.6 else FOGO[3])
        if Y0 < y < Y1:
            img.putpixel((x, y), cor)
            if idade < 0.4 and y + 1 < Y1:
                img.putpixel((x, y + 1), FOGO[3])


def _almas(img: Image.Image, f: int, cx: float, cy: float, frente: bool) -> None:
    """3 almas em órbita elíptica; as de trás são desenhadas antes da caveira."""
    px = img.load()
    for i in range(3):
        for rastro in range(5, -1, -1):
            a = 2 * math.pi * ((f - rastro * 0.3) / QUADROS + i / 3.0)
            if (math.sin(a) > 0) != frente:
                continue
            x = int(round(cx + 47 * math.cos(a)))
            y = int(round(cy + 18 * math.sin(a)))
            if rastro == 0:
                for dy in range(-2, 3):
                    for dx in range(-2, 3):
                        d = abs(dx) + abs(dy)
                        if d <= 1:
                            px[x + dx, y + dy] = FOGO[5] if d == 0 else FOGO[4]
                        elif d <= 3 and dither(x + dx, y + dy, 0.45):
                            px[x + dx, y + dy] = FOGO[3]
            else:
                cor = FOGO[4] if rastro < 2 else (FOGO[3] if rastro < 4 else FOGO[2])
                px[x, y] = cor
                if rastro < 3:
                    px[x, y - 1] = cor


def lich(fonte: dict) -> list:
    _FONTE.update(fonte)
    quadros = []
    for f in range(QUADROS):
        img = Image.new("RGBA", (cartas.W, cartas.H), (0, 0, 0, 0))
        bob = int(round(2 * math.sin(2 * math.pi * f / QUADROS)))
        cx, cy = 65.5, 98 + bob                              # centro do sprite (caveira + manto)
        _almas(img, f, cx, 76 + bob, frente=False)
        joia = "#ffffff" if f in (6, 7) else OLHOS[(f + 4) % QUADROS]
        cav = ampliar(lich_sprite.caveira(OLHOS[f], joia), 2)
        colar_centro(img, contorno(cav, "#050805"), cx, cy)
        if f in (5, 6, 7, 8):                              # brilho na joia da coroa
            colar_centro(img, brilho(0, 0, 2 if f in (6, 7) else 1, "#c6ff9a"), cx + 1, cy - 34)
        # a barra do manto se desfaz em pontilhado antes de entrar no fogo
        px = img.load()
        fundo = int(cy + cav.height / 2)
        for y in range(fundo - 16, fundo + 2):
            for x in range(X0, X1):
                if px[x, y][3] and not dither(x, y + f, (fundo - y) / 16.0):
                    px[x, y] = (0, 0, 0, 0)
        _fogo_fantasma(img, f)                             # o manto "queima" no fogo-fantasma
        _fagulhas(img, f)
        _almas(img, f, cx, 76 + bob, frente=True)
        quadros.append(area(img))
    return quadros


# ================================================================ Mercador-Rei (K de Ouros)

def _reflexo(img: Image.Image, f: int) -> None:
    """Faixa de brilho "foil" atravessando a arte na direção da faixa diagonal."""
    if f > 10:
        return
    px = img.load()
    c = int(X0 + Y0 - 20 + f * 30)                         # linha x + y = c
    alvo = hexc("#fff3b0")
    for y in range(Y0, Y1):
        for x in range(X0, X1):
            d = abs((x + y) - c)
            if d <= 3 and px[x, y][3]:
                px[x, y] = lerp(px[x, y], alvo, (0.7, 0.5, 0.3, 0.12)[d])


def mercador_rei(fonte: dict) -> list:
    _FONTE.update(fonte)
    base = cartas.moldura(fonte, "ouros")                  # fundo da arte para o reflexo
    diamante = contorno(ampliar(fonte["icones"]["ouros"], 3), "#5e500a")
    coroa = contorno(ampliar(icones.coroa("#ff3040"), 2), "#5e500a")
    moedas = [contorno(ampliar(m, 2), "#5e500a") for m in icones.MOEDA]
    # pilha fixa de moedas no pé da arte
    pilha = []
    for i in range(11):
        pilha.append((X0 + 12 + (i * 31) % (X1 - X0 - 24), Y1 - 12 - (i % 3) * 6, i % 4))
    quadros = []
    for f in range(QUADROS):
        img = Image.new("RGBA", (cartas.W, cartas.H), (0, 0, 0, 0))
        img.paste(base.crop((X0, Y0, X1, Y1)), (X0, Y0))
        caindo = []
        for i in range(7):
            vel = 4 + i % 3
            ciclo = QUADROS * vel
            y = Y0 - 10 + ((i * 41 + f * vel) % ciclo) * (Y1 - Y0 + 10) / ciclo
            x = X0 + 10 + (i * 37) % (X1 - X0 - 20)
            caindo.append((x, y, (f + i) % 4, i % 2 == 0))
        for x, y, q, frente in caindo:                     # moedas de trás
            if not frente:
                colar_centro(img, moedas[q], x, y)
        for x, y, q in pilha:
            colar_centro(img, moedas[q if q != 2 else 0], x, y)
        colar_centro(img, coroa, 65.5, 70)
        colar_centro(img, diamante, 65.5, 114)
        for x, y, q, frente in caindo:                     # moedas da frente
            if frente:
                colar_centro(img, moedas[q], x, y)
        for i, (bx, by) in enumerate(((44, 100), (88, 126), (70, 92), (52, 132), (86, 104))):
            fase = (f + i * 3) % QUADROS
            if fase < 4:
                colar_centro(img, brilho(0, 0, (1, 2, 2, 1)[fase], "#fff3b0"), bx, by)
        _reflexo(img, f)
        quadros.append(area(img))
    return quadros
