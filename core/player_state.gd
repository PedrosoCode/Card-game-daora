class_name PlayerState
extends RefCounted

var id := 0
var name := ""
var is_ai := false
var deck: Array[Card] = []
var hand: Array[Card] = []
var graveyard: Array[Card] = []
var rows := {"front": [], "back": [], "command": []}
var passed := false
var gems := 2
var played_card := false


func board_cards() -> Array[Card]:
	var out: Array[Card] = []
	for r in ["front", "back", "command"]:
		for c: Card in rows[r]:
			out.append(c)
	return out
