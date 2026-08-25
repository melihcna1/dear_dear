class_name MarketModel
extends Node

signal changed
signal status_changed(message: String)

const MAX_CART_QUANTITY := 10
const SELLABLE_CATEGORIES := ["Crops", "Food", "Fish"]

var cart: Dictionary = {}


func add_to_cart(definition_id: String, quantity: int) -> bool:
	if quantity < 1 or quantity > MAX_CART_QUANTITY:
		status_changed.emit("Maximum quantity is 10")
		return false
	var current := int(cart.get(definition_id, 0))
	if current + quantity > MAX_CART_QUANTITY:
		status_changed.emit("Maximum quantity is 10")
		return false
	cart[definition_id] = current + quantity
	changed.emit()
	return true


func remove_from_cart(definition_id: String) -> void:
	if cart.erase(definition_id):
		changed.emit()


func clear_cart() -> void:
	if cart.is_empty():
		return
	cart.clear()
	changed.emit()


func cart_total(catalog: ItemCatalog) -> int:
	var total := 0
	for id in cart.keys():
		var definition := catalog.get_definition(str(id))
		if definition:
			total += definition.buy_price * int(cart[id])
	return total


func purchase(wallet: WalletModel, inventory: InventoryModel, catalog: ItemCatalog) -> bool:
	if cart.is_empty():
		status_changed.emit("Cart Is Empty")
		return false
	for id in cart.keys():
		var definition := catalog.get_definition(str(id))
		if not definition or not definition.is_buyable or definition.item_type != "STANDARD":
			status_changed.emit("Item Cannot Be Purchased")
			return false
	var total := cart_total(catalog)
	if not wallet.can_spend(total):
		status_changed.emit("Not Enough Coins")
		return false
	if not inventory.can_add_cart(cart, catalog):
		status_changed.emit("Not Enough Inventory Space")
		return false
	if not wallet.spend(total):
		status_changed.emit("Not Enough Coins")
		return false
	for id in cart.keys():
		for _i in int(cart[id]):
			inventory.add_instance(catalog.create_instance(str(id)), catalog)
	clear_cart()
	status_changed.emit("Purchase Complete")
	return true


func purchase_single_placeable(definition_id: String, wallet: WalletModel, catalog: ItemCatalog) -> bool:
	var definition := catalog.get_definition(definition_id)
	if not definition or not definition.is_buyable or not definition.is_placeable:
		status_changed.emit("Item Cannot Be Purchased")
		return false
	if not wallet.spend(definition.buy_price):
		status_changed.emit("Not Enough Coins")
		return false
	status_changed.emit("Purchase Complete")
	return true


func sell_slot_quantity(slot_index: int, quantity: int, wallet: WalletModel, inventory: InventoryModel, catalog: ItemCatalog) -> bool:
	var stack := inventory.get_slot_stack(slot_index)
	if stack.is_empty():
		return false
	var definition := catalog.get_definition(stack[0].definition_id)
	if not is_sellable(definition):
		status_changed.emit("Item Cannot Be Sold")
		return false
	quantity = clampi(quantity, 1, stack.size())
	var removed := inventory.remove_quantity_from_slot(slot_index, quantity)
	if removed.is_empty():
		return false
	wallet.earn(definition.sell_price * removed.size())
	status_changed.emit("Sold %d" % removed.size())
	return true


func is_sellable(definition: PlaceableItemDefinition) -> bool:
	return definition != null and definition.is_sellable and definition.category in SELLABLE_CATEGORIES and definition.sell_price > 0
