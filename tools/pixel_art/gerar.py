#!/usr/bin/env python3
"""Gera a arte em pixel do jogo a partir da arte original do usuário.

1. Compõe as camadas (Python/Pillow) em tools/pixel_art/build/.
2. Monta os .aseprite com camadas e animações (script Lua rodando no Aseprite)
   em ~/Imagens/arts/project cards/: base/, special/, fx/, icons/.
   Um .aseprite que já existe NÃO é sobrescrito (dá para editá-lo à mão);
   use --refazer para gerar tudo de novo.
3. Exporta dos .aseprite para o jogo (assets/pixel/) e gera prévias em GIF
   (~/Imagens/arts/project cards/previews/).

Uso:  python3 tools/pixel_art/gerar.py [--refazer] [--so-exportar]
"""
import json
import os
import subprocess
import sys
from PIL import Image

import fonte as fonte_mod
import cartas
import especiais
import efeitos
import icones
import mini
from desenho import glifos

AQUI = os.path.dirname(os.path.abspath(__file__))
PROJETO = os.path.abspath(os.path.join(AQUI, "..", ".."))
BUILD = os.path.join(AQUI, "build", "camadas")
ARTE = fonte_mod.ARTE
ASSETS = os.path.join(PROJETO, "assets", "pixel")
PREVIAS = os.path.join(ARTE, "previews")
ASE = fonte_mod.ASEPRITE
VALOR_ARQ = {11: "J", 12: "Q", 13: "K", 14: "A"}
FX_DUR = {"corte": 60, "impacto": 60, "fogo": 80, "cura": 90, "veneno": 90, "escudo": 80, "gelo": 80, "morte": 90}
ESPECIAIS = {
    # id da carta: (naipe, valor, função, duração do quadro em ms)
    "lich": ("paus", 14, "lich", 100),
    "mercador_rei": ("ouros", 13, "mercador_rei", 100),
}
ICONES = [("atq", icones.ATQ), ("hp", icones.HP), ("arm", icones.ARM), ("veneno", icones.VENENO),
          ("sangramento", icones.SANGRAMENTO), ("escudo", icones.ESCUDO), ("congelado", icones.CONGELADO),
          ("exausto", icones.EXAUSTO), ("temporizador", icones.TEMPORIZADOR), ("raio", icones.RAIO)]


def salvar(img: Image.Image, *partes) -> str:
    p = os.path.join(BUILD, *partes)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p)
    return p


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def spec_lua(sp: dict) -> str:
    camadas = []
    for nome, quadros in sp["camadas"]:
        camadas.append("{name=%s, frames={%s}}" % (lua_str(nome), ",".join(lua_str(q) for q in quadros)))
    fatias = ",".join("{name=%s, x=%d, y=%d, w=%d, h=%d}" % (lua_str(n), x, y, w, h) for n, x, y, w, h in sp.get("fatias", []))
    return "{out=%s, w=%d, h=%d, n=%d, dur=%f, tag=%s, layers={%s}, slices={%s}}" % (
        lua_str(sp["out"]), sp["w"], sp["h"], sp["n"], sp["dur"] / 1000.0,
        lua_str(sp["tag"]) if sp.get("tag") else "nil", ",".join(camadas), fatias)


LUA_MONTAR = r'''
local function build(s)
  local spr = Sprite(s.w, s.h, ColorMode.RGB)
  for i = 2, s.n do spr:newEmptyFrame() end
  for li, L in ipairs(s.layers) do
    local layer = (li == 1) and spr.layers[1] or spr:newLayer()
    layer.name = L.name
    for fi = 1, s.n do
      local path = L.frames[(#L.frames == 1) and 1 or fi]
      spr:newCel(layer, spr.frames[fi], Image{ fromFile = path }, Point(0, 0))
    end
  end
  for fi = 1, s.n do spr.frames[fi].duration = s.dur end
  if s.tag then local t = spr:newTag(1, s.n); t.name = s.tag end
  for _, sl in ipairs(s.slices) do
    local slice = spr:newSlice(Rectangle(sl.x, sl.y, sl.w, sl.h)); slice.name = sl.name
  end
  spr:saveAs(s.out)
  spr:close()
end
for _, s in ipairs(SPECS) do build(s) end
'''


def montar(specs: list, refazer: bool) -> None:
    pend = [s for s in specs if refazer or not os.path.exists(s["out"])]
    print("  .aseprite: %d novos, %d já existiam (mantidos)" % (len(pend), len(specs) - len(pend)))
    if not pend:
        return
    for s in pend:
        os.makedirs(os.path.dirname(s["out"]), exist_ok=True)
    lua = os.path.join(AQUI, "build", "montar.lua")
    with open(lua, "w") as fh:
        fh.write("SPECS = {\n" + ",\n".join(spec_lua(s) for s in pend) + "\n}\n" + LUA_MONTAR)
    subprocess.run([ASE, "-b", "--script", lua], check=True)


def ase(*args) -> None:
    subprocess.run([ASE, "-b"] + list(args), check=True, stdout=subprocess.DEVNULL)


def compor_tudo(f: dict) -> list:
    specs = []
    pad = cartas.baralho_padrao()
    # ---- cartas base (52) com camadas frame / icon / numbers / stats / stats_valores
    for naipe in cartas.NAIPES:
        moldura = salvar(cartas.moldura(f, naipe), naipe, "frame.png")
        stats = salvar(cartas.camada_stats_icones(False), "stats_unidade.png")
        for v in range(2, 15):
            nome = "%s_%s" % (cartas.NOME_ARQ[naipe], VALOR_ARQ.get(v, str(v)))
            c = pad[(naipe, v)]
            specs.append({"out": os.path.join(ARTE, "base", cartas.NOME_ARQ[naipe], nome + ".aseprite"),
                          "w": 160, "h": 192, "n": 1, "dur": 100, "jogo": ("cartas", "%s_%d" % (naipe, v)),
                          "camadas": [("frame", [moldura]),
                                      ("icon", [salvar(cartas.camada_naipes(f, naipe, v), nome, "icon.png")]),
                                      ("numbers", [salvar(cartas.camada_valor(f, v), nome, "numbers.png")]),
                                      ("stats", [stats]),
                                      ("stats_valores", [salvar(cartas.camada_stats_valores(f, int(c["atk"]), int(c["hp"])), nome, "valores.png")])]})
        # instantânea do naipe
        specs.append({"out": os.path.join(ARTE, "base", "instant", "instant_%s.aseprite" % cartas.NOME_ARQ[naipe]),
                      "w": 160, "h": 192, "n": 1, "dur": 100, "jogo": ("cartas", "instantanea_%s" % naipe),
                      "camadas": [("frame", [moldura]),
                                  ("icon", [salvar(cartas.camada_instantanea(f, naipe), "inst_" + naipe, "icon.png")]),
                                  ("numbers", [salvar(cartas.camada_valor(f, "Z"), "inst_numbers.png")]),
                                  ("stats", [salvar(cartas.camada_stats_icones(True), "stats_inst.png")])]})
    specs.append({"out": os.path.join(ARTE, "base", "back.aseprite"), "w": 160, "h": 192, "n": 1, "dur": 100,
                  "jogo": ("cartas", "verso"), "camadas": [("frame", [salvar(cartas.verso(f), "verso.png")])]})
    # ---- especiais animadas
    for cid, (naipe, v, fn, dur) in ESPECIAIS.items():
        quadros = getattr(especiais, fn)(f) if fn != "lich" else especiais.lich(f)
        arte = [salvar(q, "esp_" + cid, "arte_%02d.png" % i) for i, q in enumerate(quadros)]
        c = pad.get((naipe, v))
        dados = json.load(open(os.path.join(PROJETO, "data", "cards.json")))
        carta = next(x for x in dados["cards"] if x["id"] == cid)
        specs.append({"out": os.path.join(ARTE, "special", cid + ".aseprite"), "w": 160, "h": 192,
                      "n": len(quadros), "dur": dur, "tag": "idle", "jogo": ("especiais", cid),
                      "camadas": [("frame", [salvar(cartas.moldura(f, naipe), "esp_" + cid, "frame.png")]),
                                  ("arte", arte),
                                  ("numbers", [salvar(cartas.camada_valor(f, v), "esp_" + cid, "numbers.png")]),
                                  ("stats", [salvar(cartas.camada_stats_icones(False), "esp_" + cid, "stats.png")]),
                                  ("stats_valores", [salvar(cartas.camada_stats_valores(f, int(carta["atk"]), int(carta["hp"])), "esp_" + cid, "valores.png")])]})
    # ---- efeitos
    for nome, fn in efeitos.TODOS.items():
        quadros = fn()
        specs.append({"out": os.path.join(ARTE, "fx", "fx_%s.aseprite" % nome), "w": quadros[0].width,
                      "h": quadros[0].height, "n": len(quadros), "dur": FX_DUR[nome], "tag": "play",
                      "jogo": ("fx", nome),
                      "camadas": [("fx", [salvar(q, "fx_" + nome, "%02d.png" % i) for i, q in enumerate(quadros)])]})
    # ---- ícones de stats/estados e dígitos (fatias nomeadas)
    cel = 16
    tira = Image.new("RGBA", (cel * len(ICONES), cel), (0, 0, 0, 0))
    fatias = []
    for i, (nome, img) in enumerate(ICONES):
        x = i * cel + (cel - img.width) // 2
        y = (cel - img.height) // 2
        tira.alpha_composite(img, (x, y))
        fatias.append((nome, x, y, img.width, img.height))
    specs.append({"out": os.path.join(ARTE, "icons", "stats_icons.aseprite"), "w": tira.width, "h": cel, "n": 1,
                  "dur": 100, "jogo": ("ui", "icones"), "fatias": fatias,
                  "camadas": [("icons", [salvar(tira, "icones.png")])]})
    g = glifos(f["digitos"])
    chars = "0123456789JQKA+-Z"
    larg = sum(g[c].width + 1 for c in chars)
    tira = Image.new("RGBA", (larg, 9), (0, 0, 0, 0))
    fatias = []
    x = 0
    for c in chars:
        tira.alpha_composite(g[c], (x, 0))
        fatias.append((c, x, 0, g[c].width, g[c].height))
        x += g[c].width + 1
    specs.append({"out": os.path.join(ARTE, "icons", "digits.aseprite"), "w": larg, "h": 9, "n": 1, "dur": 100,
                  "jogo": ("ui", "digitos"), "fatias": fatias, "camadas": [("digits", [salvar(tira, "digitos.png")])]})
    # ---- carta de mesa (mini 48x60): um atlas com fatias "<naipe>_<n|a|j|q|k>", "instantanea_<naipe>", "verso"
    celulas = []
    for naipe in cartas.NAIPES:
        for tipo in ("n", "a", "j", "q", "k", "inst"):
            im = mini.moldura(naipe, stats=tipo != "inst")
            im.alpha_composite(mini.arte(f, naipe, tipo))
            celulas.append(("instantanea_" + naipe if tipo == "inst" else "%s_%s" % (naipe, tipo), im))
    celulas.append(("verso", mini.verso()))
    atlas = Image.new("RGBA", (mini.W * len(celulas), mini.H), (0, 0, 0, 0))
    fatias = []
    for i, (nome, im) in enumerate(celulas):
        atlas.alpha_composite(im, (i * mini.W, 0))
        fatias.append((nome, i * mini.W, 0, mini.W, mini.H))
    specs.append({"out": os.path.join(ARTE, "base_mini", "mini_cards.aseprite"), "w": atlas.width, "h": mini.H,
                  "n": 1, "dur": 100, "jogo": ("mini", "cartas"), "fatias": fatias,
                  "camadas": [("cards", [salvar(atlas, "mini_cartas.png")])]})
    cel = 8
    tira = Image.new("RGBA", (cel * len(mini.ICONES_MINI), cel), (0, 0, 0, 0))
    fatias = []
    for i, (nome, img) in enumerate(mini.ICONES_MINI):
        x, y = i * cel + (cel - img.width) // 2, (cel - img.height) // 2
        tira.alpha_composite(img, (x, y))
        fatias.append((nome, x, y, img.width, img.height))
    specs.append({"out": os.path.join(ARTE, "icons", "mini_icons.aseprite"), "w": tira.width, "h": cel, "n": 1,
                  "dur": 100, "jogo": ("ui", "icones_mini"), "fatias": fatias,
                  "camadas": [("icons", [salvar(tira, "icones_mini.png")])]})
    for cid, fn in (("lich", mini.lich_mini), ("mercador_rei", mini.mercador_mini)):
        quadros = fn(f)
        specs.append({"out": os.path.join(ARTE, "special", "mini_%s.aseprite" % cid), "w": mini.W, "h": mini.H,
                      "n": len(quadros), "dur": 100, "tag": "idle", "jogo": ("mini", "especial_" + cid),
                      "camadas": [("card", [salvar(q, "mini_" + cid, "%02d.png" % i) for i, q in enumerate(quadros)])]})
    return specs


def exportar(specs: list) -> None:
    """Exporta dos .aseprite (que podem ter sido editados à mão) para o jogo."""
    os.makedirs(PREVIAS, exist_ok=True)
    for s in specs:
        pasta, nome = s["jogo"]
        destino = os.path.join(ASSETS, pasta)
        os.makedirs(destino, exist_ok=True)
        png = os.path.join(destino, nome + ".png")
        if s["n"] > 1:
            # (as opções de camada valem para o arquivo que vem DEPOIS delas)
            ase("--ignore-layer", "stats_valores", s["out"], "--sheet", png, "--sheet-type", "horizontal",
                "--data", os.path.join(destino, nome + ".json"), "--format", "json-array", "--list-tags")
            ase(s["out"], "--scale", "3", "--save-as", os.path.join(PREVIAS, "%s_%s.gif" % (pasta, nome)))
        elif s.get("fatias"):
            ase(s["out"], "--save-as", png, "--data", os.path.join(destino, nome + ".json"),
                "--format", "json-array", "--list-slices")
        else:
            ase("--ignore-layer", "stats_valores", s["out"], "--save-as", png)
    # prévia das cartas base (com os números de exemplo)
    base = [s for s in specs if s["jogo"][0] == "cartas"]
    cols = 13
    folha = Image.new("RGBA", (cols * 164 + 4, ((len(base) + cols - 1) // cols) * 196 + 4), (40, 40, 48, 255))
    tmp = os.path.join(AQUI, "build", "previa_tmp.png")
    for i, s in enumerate(base):
        ase(s["out"], "--save-as", tmp)
        folha.alpha_composite(Image.open(tmp).convert("RGBA"), (4 + (i % cols) * 164, 4 + (i // cols) * 196))
    folha.save(os.path.join(PREVIAS, "cartas_base.png"))


def main() -> None:
    refazer = "--refazer" in sys.argv
    print("Lendo a arte original em", ARTE)
    f = fonte_mod.carregar()
    print("Compondo camadas...")
    specs = compor_tudo(f)
    if "--so-exportar" not in sys.argv:
        print("Montando .aseprite...")
        montar(specs, refazer)
    print("Exportando para o jogo e prévias...")
    exportar(specs)
    print("Pronto:")
    print("  fontes .aseprite: %s/{base,special,fx,icons}" % ARTE)
    print("  jogo:             %s" % ASSETS)
    print("  prévias:          %s" % PREVIAS)


if __name__ == "__main__":
    main()
