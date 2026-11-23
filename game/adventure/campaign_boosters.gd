class_name CampaignBoosters
extends RefCounted
## Relaxed Campaign shop. Historical slot counts, an approximate early-set
## uncommon sheet, and fixed prices that can be edited in debug builds.
## These are *virtual* boosters and never enable/install a card pack.

const PRODUCTS: Array[Dictionary] = [
	{"code": "2ed", "name": "Unlimited", "count": 15, "price": 220},
	{"code": "4ed", "name": "Fourth Edition", "count": 15, "price": 180},
	{"code": "arn", "name": "Arabian Nights", "count": 8, "price": 120},
	{"code": "atq", "name": "Antiquities", "count": 8, "price": 120},
	{"code": "leg", "name": "Legends", "count": 15, "price": 200},
	{"code": "drk", "name": "The Dark", "count": 8, "price": 120},
	{"code": "fem", "name": "Fallen Empires", "count": 8, "price": 120},
	{"code": "ice", "name": "Ice Age", "count": 15, "price": 190},
	{"code": "hml", "name": "Homelands", "count": 8, "price": 120},
	{"code": "all", "name": "Alliances", "count": 12, "price": 160},
]
const PRICE_FILE := "user://relaxed_campaign_booster_prices.json"
const MAX_EDITABLE_PRICE := 100000
const EIGHT_CARD_SETS: Array[String] = ["arn", "atq", "drk", "fem", "hml"]

static var _pool_cache := {}


static func unlocked_expansions(player: AdventurePlayer) -> int:
	if player == null or player.world == null:
		return 0
	var count := 0
	for index in range(DungeonDoors.CASTLES, mini(DungeonDoors.CASTLES + 10, player.world.encounters.size())):
		if bool(player.world.encounters[index].get("relaxed_booster_unlocked", false)):
			count += 1
	return mini(count, 8)


static func unlock_name(player: AdventurePlayer) -> String:
	var count := unlocked_expansions(player)
	return String(PRODUCTS[count + 1]["name"]) if count > 0 else ""


static func available(player: AdventurePlayer) -> Array[Dictionary]:
	var out: Array[Dictionary] = [PRODUCTS[0], PRODUCTS[1]]
	for index in unlocked_expansions(player):
		out.append(PRODUCTS[index + 2])
	return out


static func product_of(code: String) -> Dictionary:
	for product in PRODUCTS:
		if String(product["code"]) == code:
			return product
	return {}


static func is_small(code: String) -> bool:
	return code in EIGHT_CARD_SETS


## The size and distribution of the actual sealed products. For early
## expansions, the two uncommon-sheet slots can yield scarce U1 cards,
## represented as "rare" by modern card databases.
static func recipe(code: String) -> Dictionary:
	if is_small(code):
		return {"common": 6, "upper_sheet": 2}
	if code == "all":
		return {"common": 8, "uncommon": 3, "rare": 1}
	return {"common": 11, "uncommon": 3, "rare": 1}


static func price_overrides() -> Dictionary:
	if not FileAccess.file_exists(PRICE_FILE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRICE_FILE))
	return parsed if parsed is Dictionary else {}


static func list_price(code: String) -> int:
	var product := product_of(code)
	if product.is_empty():
		return 0
	var overrides := price_overrides()
	return clampi(int(overrides.get(code, product["price"])), 1, MAX_EDITABLE_PRICE)


## The exact fixed price charged in every settlement.
static func price(code: String) -> int:
	return list_price(code)


## Replace all edited prices in a single write, preserving any additional
## configuration entries written by a newer version.
static func set_prices(edited: Dictionary) -> bool:
	var overrides := price_overrides()
	for code in edited:
		var amount := int(edited[code])
		if product_of(String(code)).is_empty() or amount < 1 or amount > MAX_EDITABLE_PRICE:
			return false
		for product in PRODUCTS:
			if String(product["code"]) == String(code):
				overrides[String(code)] = amount
	var file := FileAccess.open(PRICE_FILE, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(overrides, "  "))
	file.close()
	return true


static func set_price(code: String, gold: int) -> bool:
	return set_prices({code: gold})


## Restrict to cards that are actually installed/enabled, and to the
## specified historical printing. This is independent of campaign unlocks.
static func _sheets(code: String) -> Dictionary:
	CardRegistry.ensure_loaded()
	var key := "%d:%s" % [CardRegistry.revision, code]
	if _pool_cache.has(key):
		return _pool_cache[key]
	var sheets := {"rare": [] as Array[String], "uncommon": [] as Array[String],
		"common": [] as Array[String]}
	for card in CardRegistry.all_names():
		var name := String(card)
		if not CardRegistry.has_card(name):
			continue
		var rarity := CardRegistry.printed_rarity(name, code)
		if rarity == "" and CardRegistry.card_in_set(name, code):
			rarity = CardRegistry.rarity_of(name, code)
		if sheets.has(rarity):
			(sheets[rarity] as Array[String]).append(name)
	if _pool_cache.size() > 30:
		_pool_cache.clear()
	_pool_cache[key] = sheets
	return sheets


## The upper sheet of early eight-card products had no independent rare
## slot. Modern rarity metadata loses exact C1/U1/U2/U3 print runs, so
## use a documented approximation: scarce names 1x, uncommons 3x.
static func _upper_sheet(sheets: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for name in sheets["uncommon"]:
		for copy in 3:
			out.append(String(name))
	for name in sheets["rare"]:
		out.append(String(name))
	return out


static func _draw_pool(pool: Array[String]) -> String:
	return pool[randi_range(0, pool.size() - 1)] if not pool.is_empty() else ""


static func ready(code: String) -> bool:
	var sheets := _sheets(code)
	var plan := recipe(code)
	if plan.is_empty():
		return false
	if (sheets["common"] as Array).is_empty():
		return false
	if is_small(code):
		return not _upper_sheet(sheets).is_empty()
	return not (sheets["uncommon"] as Array).is_empty() and not (sheets["rare"] as Array).is_empty()


## Sample with replacement from the relevant printing sheets. The 15-card
## and 12-card products get their original slot counts, not a draft-era
## basic land/token slot. A pack contains exactly the advertised count.
static func generate(code: String) -> Array[String]:
	var out: Array[String] = []
	if not ready(code):
		return out
	var sheets := _sheets(code)
	var plan := recipe(code)
	for i in int(plan["common"]):
		out.append(_draw_pool(sheets["common"]))
	if is_small(code):
		var upper := _upper_sheet(sheets)
		for i in int(plan["upper_sheet"]):
			out.append(_draw_pool(upper))
	else:
		for i in int(plan["uncommon"]):
			out.append(_draw_pool(sheets["uncommon"]))
		for i in int(plan["rare"]):
			out.append(_draw_pool(sheets["rare"]))
	out.shuffle()
	return out


## All settlements charge the same price for a given expansion.
## The player and site arguments preserve compatibility with v2 callers.
## Random pack contents never affect the price of an unopened booster.
static func price_at(_player: AdventurePlayer, _slot: int, code: String) -> int:
	return list_price(code)


static func purchase(player: AdventurePlayer, code: String, slot := -1) -> Dictionary:
	var product := product_of(code)
	if player == null or product.is_empty() or not (product in available(player)):
		return {"ok": false, "message": "This booster is not unlocked."}
	if not ready(code):
		return {"ok": false, "message": "The edition's card data is not enabled. Check Options > Card Packs."}
	var charge := price_at(player, slot, code)
	if player.gold < charge:
		return {"ok": false, "message": "Not enough gold. This booster costs %d." % charge}
	var cards := generate(code)
	if cards.size() != int(product["count"]):
		return {"ok": false, "message": "Unable to collate a full booster."}
	if player.bag_room() < cards.size():
		return {"ok": false, "message": "Not enough space in your collection."}
	player.gold -= charge
	for card_name in cards:
		player.add_card(card_name)
	return {"ok": true, "product": product["name"], "cards": cards, "price": charge,
		"message": "Opened %s for %d gold. Gold remaining: %d" % [product["name"], charge, player.gold]}
