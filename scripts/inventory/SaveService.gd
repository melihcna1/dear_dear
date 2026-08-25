class_name SaveService
extends RefCounted

const SAVE_PATH := "user://savegame.json"
const VERSION := 5

var save_path := SAVE_PATH


func save_game(inventory: InventoryModel, placed_items: Array, wallet: WalletModel = null, profile: AvatarProfile = null) -> bool:
	var world: Array = []
	for item in placed_items:
		if item is PlacementItem:
			var parent_id := ""
			if item.get_parent() is PlacementItem:
				parent_id = item.get_parent().instance_id
			world.append(item.to_save_dict(parent_id))
	var data := {
		"version": VERSION,
		"inventory": inventory.to_dict(),
		"world": world,
		"wallet": wallet.to_dict() if wallet else {},
		"profile": profile.to_dict() if profile else {},
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


func load_game() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if not file:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
