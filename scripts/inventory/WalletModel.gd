class_name WalletModel
extends Node

signal changed

const DEFAULT_COINS := 1000
const DEFAULT_GEMS := 500
const SOFT := "soft"
const HARD := "hard"

var coins := DEFAULT_COINS
var gems := DEFAULT_GEMS


func can_spend(amount: int, currency_type := SOFT) -> bool:
	return amount <= (gems if currency_type == HARD else coins)


func spend(amount: int, currency_type := SOFT) -> bool:
	if amount < 0 or not can_spend(amount, currency_type):
		return false
	if currency_type == HARD:
		gems -= amount
	else:
		coins -= amount
	changed.emit()
	return true


func earn(amount: int, currency_type := SOFT) -> void:
	if currency_type == HARD:
		gems += maxi(amount, 0)
	else:
		coins += maxi(amount, 0)
	changed.emit()


func can_spend_totals(totals: Dictionary) -> bool:
	return can_spend(int(totals.get(SOFT, 0)), SOFT) and can_spend(int(totals.get(HARD, 0)), HARD)


func spend_totals(totals: Dictionary) -> bool:
	var soft_total := int(totals.get(SOFT, 0))
	var hard_total := int(totals.get(HARD, 0))
	if soft_total < 0 or hard_total < 0 or not can_spend_totals(totals):
		return false
	coins -= soft_total
	gems -= hard_total
	changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"coins": coins, "gems": gems}


func load_dict(data: Dictionary) -> void:
	coins = int(data.get("coins", DEFAULT_COINS))
	gems = int(data.get("gems", DEFAULT_GEMS))
	changed.emit()
