"""Lê a arte original do usuário (arquivos .aseprite) pela linha de comando do
Aseprite: moldura, dígitos, ícones de naipe e posições dos naipes do 2 ao 10."""
import os
import subprocess
from PIL import Image

ASEPRITE = os.path.expanduser("~/.local/share/Steam/steamapps/common/Aseprite/aseprite")
ARTE = os.path.expanduser("~/Imagens/arts/project cards")
CACHE = os.path.join(os.path.dirname(__file__), "build", "fonte")


def exportar_camadas(arquivo: str, nome: str) -> dict:
    """Exporta cada camada de um .aseprite para PNG (cache) e devolve {camada: Image}."""
    os.makedirs(CACHE, exist_ok=True)
    subprocess.run([ASEPRITE, "-b", "--split-layers", arquivo, "--save-as",
                    os.path.join(CACHE, nome + "_{layer}.png")], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    out = {}
    for f in os.listdir(CACHE):
        if f.startswith(nome + "_") and f.endswith(".png"):
            out[f[len(nome) + 1:-4]] = Image.open(os.path.join(CACHE, f)).convert("RGBA")
    return out


def componentes(img: Image.Image) -> list:
    """Caixas (x0, y0, x1, y1) dos grupos de pixels opacos (8-vizinhança)."""
    w, h = img.size
    px = img.load()
    seen = set()
    boxes = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] and (x, y) not in seen:
                st = [(x, y)]
                seen.add((x, y))
                xs, ys = [], []
                while st:
                    a, b = st.pop()
                    xs.append(a)
                    ys.append(b)
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            c = (a + dx, b + dy)
                            if 0 <= c[0] < w and 0 <= c[1] < h and c not in seen and px[c][3]:
                                seen.add(c)
                                st.append(c)
                boxes.append((min(xs), min(ys), max(xs) + 1, max(ys) + 1))
    boxes.sort(key=lambda b: (b[1], b[0]))
    return boxes


def carregar():
    """Tudo o que o gerador usa da arte original."""
    base = exportar_camadas(os.path.join(ARTE, "card frame base.aseprite"), "base")
    d7 = exportar_camadas(os.path.join(ARTE, "diamond", "diamond_7.aseprite"), "d7")
    # ícones de naipe (a moldura base tem um de cada, em cores próprias)
    icones = {}
    for b in componentes(base["icon"]):
        recorte = base["icon"].crop(b)
        cor = recorte.getpixel((recorte.width // 2, recorte.height // 2))
        chave = "%02x%02x%02x" % cor[:3]
        naipe = {"ffef94": "ouros", "9e0000": "copas", "0015a1": "espadas", "067500": "paus"}.get(chave)
        if naipe and naipe not in icones:
            icones[naipe] = recorte
    # dígitos 0-9: separados por colunas vazias
    tira = base["numbers"].crop(base["numbers"].getbbox())
    digitos = {}
    x = 0
    n = 0
    w, h = tira.size
    while x < w and n < 10:
        while x < w and all(tira.getpixel((x, y))[3] == 0 for y in range(h)):
            x += 1
        x0 = x
        while x < w and any(tira.getpixel((x, y))[3] for y in range(h)):
            x += 1
        digitos[str(n)] = tira.crop((x0, 0, x, h))
        n += 1
    # posições (centros) dos naipes do 2 ao 10
    pips = {}
    for v in range(2, 11):
        camadas = exportar_camadas(os.path.join(ARTE, "diamond", "diamond_%d.aseprite" % v), "d%d" % v)
        pips[v] = [((b[0] + b[2]) / 2.0, (b[1] + b[3]) / 2.0) for b in componentes(camadas["icon"])]
    return {"moldura": d7["frame"], "icones": icones, "digitos": digitos, "pips": pips}
