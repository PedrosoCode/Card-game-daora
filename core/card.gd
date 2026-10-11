class_name Card
extends RefCounted
## Instância de uma carta em jogo. A definição (imutável) fica em `def`,
## vinda do data/cards.json. Todo o estado mutável fica aqui.

var uid: int
var def: Dictionary
var id: String
var owner: int
var kind: String          # "unit" ou "effect"
var name: String
var suit: String          # "" para cartas de efeito
var base_value: int       # 2..14 (11=J, 12=Q, 13=K, 14=A)
var value_mod := 0
var max_hp := 0
var hp := 0
var atk := 0
var atk_mod := 0
var armor := 0
var poison := 0           # acúmulos: 1 de dano por turno do dono, cai 1 por tick, ignora armadura
var bleed := 0            # idem ao veneno
var shield := 0           # Escudo: anula por completo a próxima instância de dano (não DoT)
var frozen := 0           # Congelada: turnos do dono em que fica sem agir
var stunned := false      # congelada NESTE turno (não ataca nem ativa, nem com Investida)
var silenced := false     # Silenciada: perde passivas, ativo, auras e palavras-chave
var row := ""             # "" = fora do tabuleiro
var exhausted := true     # entrou neste turno: não ataca nem usa ativo
var attacked := false      # sem ataques sobrando neste turno
var attacks_made := 0      # Fúria permite 2 ataques por turno
var active_used := false
var keywords: Array = []
## Temporizadores: chave ("active" ou "p<índice da passiva>") -> turnos que faltam.
## Qualquer ativo/passiva com "cooldown": N ganha um. Ele começa em N quando a
## carta entra, desce 1 no início de cada turno do dono e, em 0, o efeito pode
## acontecer; depois de acontecer, volta para N.
var timers: Dictionary = {}


func _init(p_uid: int, p_def: Dictionary, p_owner: int) -> void:
	uid = p_uid
	def = p_def
	owner = p_owner
	reset()


## Volta a carta ao estado de fábrica (usado ao sair do cemitério).
func reset() -> void:
	id = def.get("id", "")
	kind = def.get("kind", "unit")
	name = def.get("name", id)
	suit = def.get("suit", "")
	base_value = int(def.get("value", 0))
	value_mod = 0
	max_hp = int(def.get("hp", 0))
	hp = max_hp
	atk = int(def.get("atk", 0))
	atk_mod = 0
	armor = int(def.get("armor", 0))
	poison = 0
	bleed = 0
	shield = int(def.get("shield", 0))
	frozen = 0
	stunned = false
	silenced = false
	attacks_made = 0
	row = ""
	exhausted = true
	attacked = false
	active_used = false
	keywords = (def.get("keywords", []) as Array).duplicate()
	timers = {}
	var act: Dictionary = def.get("active", {})
	if act.has("cooldown"):
		timers["active"] = int(act["cooldown"])
	var passives: Array = def.get("passives", [])
	for i in passives.size():
		if (passives[i] as Dictionary).has("cooldown"):
			timers["p%d" % i] = int(passives[i]["cooldown"])


func is_unit() -> bool:
	return kind == "unit"


func has_kw(k: String) -> bool:
	return not silenced and keywords.has(k)


func on_board() -> bool:
	return row != ""
