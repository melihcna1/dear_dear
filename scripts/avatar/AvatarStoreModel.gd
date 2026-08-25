class_name AvatarStoreModel
extends Node

signal changed
signal status_changed(message: String)
signal purchase_completed

var cart: Dictionary = {}


func select_item(
		definition_id: String,
		duration_days: int,
		catalog: ItemCatalog,
		gender: String = AvatarProfile.DEFAULT_GENDER) -> bool:
	var active_gender := AvatarProfile.normalized_gender(gender)
	var definition := catalog.get_definition(definition_id)
	if (
		not definition
		or not definition.is_buyable
		or not catalog.is_avatar_definition_compatible(definition, active_gender)
	):
		status_changed.emit("Item Cannot Be Purchased")
		return false
	var price_option := definition.price_for_duration(duration_days)
	if price_option.is_empty():
		status_changed.emit("Invalid Duration")
		return false
	_remove_incompatible_lines(active_gender, catalog)
	var slot := definition.avatar_slot
	if slot == "fullbody":
		cart.erase("top")
		cart.erase("bottom")
	elif slot in ["top", "bottom"]:
		cart.erase("fullbody")
	cart[slot] = {
		"definition_id": definition_id,
		"duration_days": duration_days,
		"currency_type": str(price_option.get("currency_type", WalletModel.SOFT)),
		"price": int(price_option.get("price", 0)),
		"gender": active_gender,
	}
	changed.emit()
	return true


func remove_slot(slot: String) -> void:
	if cart.erase(slot):
		changed.emit()


func clear() -> void:
	if cart.is_empty():
		return
	cart.clear()
	changed.emit()


func totals() -> Dictionary:
	var result := {WalletModel.SOFT: 0, WalletModel.HARD: 0}
	for line in cart.values():
		var currency_type := str(line.get("currency_type", WalletModel.SOFT))
		result[currency_type] = int(result.get(currency_type, 0)) + int(line.get("price", 0))
	return result


func preview_state(base_state: Dictionary, catalog: ItemCatalog) -> Dictionary:
	var state := base_state.duplicate(true)
	var active_gender := AvatarProfile.normalized_gender(str(state.get("gender", AvatarProfile.DEFAULT_GENDER)))
	for slot in cart.keys():
		var line: Dictionary = cart[slot]
		var definition := catalog.get_definition(str(line.get("definition_id", "")))
		if not definition or not catalog.is_avatar_definition_compatible(definition, active_gender):
			continue
		match definition.avatar_slot:
			"fullbody":
				state["fullbody"] = definition.definition_id
				state["top"] = ""
				state["bottom"] = ""
			"top", "bottom":
				state[definition.avatar_slot] = definition.definition_id
				state["fullbody"] = ""
				if str(state.get("top", "")).is_empty():
					state["top"] = AvatarEquipmentModel.starter_for_gender(active_gender, "top")
				if str(state.get("bottom", "")).is_empty():
					state["bottom"] = AvatarEquipmentModel.starter_for_gender(active_gender, "bottom")
			"hair":
				state["hair"] = definition.definition_id
			"hair_color":
				state["hair_color"] = definition.definition_id
			"skin_tone":
				state["skin_tone"] = definition.definition_id
	return state


func purchase(
		wallet: WalletModel,
		inventory: InventoryModel,
		catalog: ItemCatalog,
		user_id: String,
		gender: String = AvatarProfile.DEFAULT_GENDER) -> bool:
	if cart.is_empty():
		status_changed.emit("Cart Is Empty")
		return false
	var instances: Array = []
	var active_gender := AvatarProfile.normalized_gender(gender)
	for line in cart.values():
		var definition_id := str(line.get("definition_id", ""))
		var definition := catalog.get_definition(definition_id)
		if (
			not definition
			or not definition.is_buyable
			or not catalog.is_avatar_definition_compatible(definition, active_gender)
		):
			status_changed.emit("Item Cannot Be Purchased")
			return false
		instances.append(catalog.create_instance(
			definition_id,
			{"source": "avatar_store"},
			int(line.get("duration_days", 0)),
			user_id
		))
	var purchase_totals := totals()
	if not wallet.can_spend_totals(purchase_totals):
		status_changed.emit("Not Enough Currency")
		return false
	if not inventory.can_add_instances(instances, catalog):
		status_changed.emit("Not Enough Inventory Space")
		return false
	if not wallet.spend_totals(purchase_totals):
		status_changed.emit("Not Enough Currency")
		return false
	for item in instances:
		inventory.add_instance(item, catalog)
	cart.clear()
	changed.emit()
	status_changed.emit("Purchase Complete - Items Are Packaged")
	purchase_completed.emit()
	return true


func _remove_incompatible_lines(gender: String, catalog: ItemCatalog) -> void:
	for slot in cart.keys():
		var line: Dictionary = cart[slot]
		var definition := catalog.get_definition(str(line.get("definition_id", "")))
		if not definition or not catalog.is_avatar_definition_compatible(definition, gender):
			cart.erase(slot)
