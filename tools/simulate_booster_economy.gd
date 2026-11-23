extends SceneTree
## Evaluate the installed Relaxed Campaign booster generator against the
## game's real CardValue.sell_price formula. No saves or prices are changed.

const SAMPLES_PER_EDITION := 10000
const SIMULATION_SEED := 20261123
const PRICE_ROUNDING := 50
const OUTPUT_FILE := "res://booster_economy_results.csv"
const CSV_COLUMNS := [
	"edition", "cards_per_pack", "current_price_gold", "samples",
	"mean_village_resale", "mean_town_resale", "mean_city_resale",
	"median_city_resale", "p80_city_resale", "p90_city_resale",
	"p95_city_resale", "p90_best_city_resale",
	"profit_at_current_price_city_pct", "profit_at_current_price_best_city_pct",
	"tentative_fixed_price_rounded_50"
]

var _card_price_cache: Dictionary = {}
var _terrain_masks: Array[int] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(SIMULATION_SEED)
	CardRegistry.ensure_loaded()
	for terrain in ShandalarWorld.LANDS_MADE:
		_terrain_masks.append(ShandalarWorld.magic_mask(terrain))
	if _terrain_masks.is_empty():
		printerr("No valid settlement terrain masks were found.")
		quit(1)
		return

	print("Relaxed Campaign booster economy simulation")
	print("Seed: %d; openings per edition: %d" % [SIMULATION_SEED, SAMPLES_PER_EDITION])
	print("Source: CampaignBoosters.generate + CardValue.sell_price")
	print("For each opening, the settlement terrain is sampled uniformly from the 9 generated land types.")
	print("Best-city case means the highest price for ALL cards in one city terrain, not per-card teleportation.")
	print("A profit means selling all the pack's contents for MORE than the purchase price.")
	print("This measures resale, not the economic value of keeping or playing the cards.")
	print("")

	var lines: Array[String] = [",".join(PackedStringArray(CSV_COLUMNS))]
	var missing: Array[String] = []
	for product in CampaignBoosters.PRODUCTS:
		var edition := String(product["code"])
		if not CampaignBoosters.ready(edition):
			missing.append("%s (%s)" % [product["name"], edition])
			print("SKIPPED %s: printing sheets are not available in the active card registry." % product["name"])
			continue
		var result := _simulate(product)
		if result.is_empty():
			missing.append("%s (%s)" % [product["name"], edition])
			continue
		var columns: Array[String] = []
		for key in CSV_COLUMNS:
			columns.append(str(result.get(key, "")))
		lines.append(",".join(PackedStringArray(columns)))
		print("%s (%d): price %d; average resale village %d, city %d; city P90 %d; best-city P90 %d; profit at listed price in city %.1f%%; tentative fixed price %d" % [
			product["name"], product["count"], result["current_price_gold"],
			result["mean_village_resale"], result["mean_city_resale"],
			result["p90_city_resale"], result["p90_best_city_resale"],
			result["profit_at_current_price_city_pct"],
			result["tentative_fixed_price_rounded_50"]])

	var file := FileAccess.open(OUTPUT_FILE, FileAccess.WRITE)
	if file == null:
		printerr("Could not write %s (file error %d)" % [OUTPUT_FILE, FileAccess.get_open_error()])
		quit(2)
		return
	file.store_string("\n".join(PackedStringArray(lines)) + "\n")
	file.close()
	print("")
	print("CSV: " + ProjectSettings.globalize_path(OUTPUT_FILE))
	if not missing.is_empty():
		printerr("Missing/unavailable printings: " + ", ".join(PackedStringArray(missing)))
		printerr("Enable the corresponding card packs in Options > Card Packs and rerun for all ten editions.")
		quit(3)
		return
	print("All ten editions completed. No in-game prices or saved campaigns were changed.")
	quit(0)


func _prices_for_card(card_name: String) -> Dictionary:
	if _card_price_cache.has(card_name):
		return _card_price_cache[card_name]
	var data: CardData = CardRegistry.get_card(card_name)
	var facts := CardValue.facts(data)
	var out := {"village": [] as Array[int], "town": [] as Array[int], "city": [] as Array[int]}
	for terrain_mask in _terrain_masks:
		(out["village"] as Array[int]).append(CardValue.sell_price(data, ShandalarWorld.VILLAGE, terrain_mask, facts))
		(out["town"] as Array[int]).append(CardValue.sell_price(data, ShandalarWorld.TOWN, terrain_mask, facts))
		(out["city"] as Array[int]).append(CardValue.sell_price(data, ShandalarWorld.CITY, terrain_mask, facts))
	_card_price_cache[card_name] = out
	return out


func _simulate(product: Dictionary) -> Dictionary:
	var edition := String(product["code"])
	var price := CampaignBoosters.price(edition)
	var terrain_count := _terrain_masks.size()
	var village_sales: Array[int] = []
	var town_sales: Array[int] = []
	var city_sales: Array[int] = []
	var best_city_sales: Array[int] = []
	var profitable_city := 0
	var profitable_best_city := 0

	for sample in range(SAMPLES_PER_EDITION):
		var cards: Array[String] = CampaignBoosters.generate(edition)
		if cards.size() != int(product["count"]):
			printerr("Invalid booster generated: %s, %d cards instead of %d." % [edition, cards.size(), product["count"]])
			return {}
		var by_village: Array[int] = []
		var by_town: Array[int] = []
		var by_city: Array[int] = []
		by_village.resize(terrain_count)
		by_town.resize(terrain_count)
		by_city.resize(terrain_count)
		by_village.fill(0)
		by_town.fill(0)
		by_city.fill(0)
		for card_name in cards:
			var quotes := _prices_for_card(card_name)
			var village_quotes: Array = quotes["village"]
			var town_quotes: Array = quotes["town"]
			var city_quotes: Array = quotes["city"]
			for j in range(terrain_count):
				by_village[j] += int(village_quotes[j])
				by_town[j] += int(town_quotes[j])
				by_city[j] += int(city_quotes[j])
		# Rotate evenly through the nine generated settlement terrain types.
		# This prevents random terrain sampling noise from obscuring pack outcomes.
		var selected := sample % terrain_count
		var village_gold := by_village[selected]
		var town_gold := by_town[selected]
		var city_gold := by_city[selected]
		var max_city_gold: int = int(by_city.max())
		village_sales.append(village_gold)
		town_sales.append(town_gold)
		city_sales.append(city_gold)
		best_city_sales.append(max_city_gold)
		if city_gold > price:
			profitable_city += 1
		if max_city_gold > price:
			profitable_best_city += 1

	city_sales.sort()
	best_city_sales.sort()
	var p90 := _percentile(city_sales, 0.90)
	var price_candidate := int(ceilf(float(p90) / float(PRICE_ROUNDING))) * PRICE_ROUNDING
	return {
		"edition": String(product["name"]),
		"cards_per_pack": int(product["count"]),
		"current_price_gold": price,
		"samples": SAMPLES_PER_EDITION,
		"mean_village_resale": _average(village_sales),
		"mean_town_resale": _average(town_sales),
		"mean_city_resale": _average(city_sales),
		"median_city_resale": _percentile(city_sales, 0.50),
		"p80_city_resale": _percentile(city_sales, 0.80),
		"p90_city_resale": p90,
		"p95_city_resale": _percentile(city_sales, 0.95),
		"p90_best_city_resale": _percentile(best_city_sales, 0.90),
		"profit_at_current_price_city_pct": snappedf(100.0 * float(profitable_city) / SAMPLES_PER_EDITION, 0.1),
		"profit_at_current_price_best_city_pct": snappedf(100.0 * float(profitable_best_city) / SAMPLES_PER_EDITION, 0.1),
		"tentative_fixed_price_rounded_50": price_candidate,
	}


func _average(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var total := 0
	for value in values:
		total += value
	return roundi(float(total) / float(values.size()))


## Nearest-rank empirical percentile, so P90 is the value at or below which
## at least 90 percent of simulated packs' resale values fall.
func _percentile(sorted_values: Array[int], portion: float) -> int:
	if sorted_values.is_empty():
		return 0
	var index := clampi(ceili(float(sorted_values.size()) * portion) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]
