extends GutTest
## Small Relaxed Campaign regression tests. These do not require card packs
## or UI scenes to be installed, and do not alter saved games.

func test_original_booster_sizes() -> void:
	var expected := {"2ed": 15, "4ed": 15, "arn": 8, "atq": 8,
		"leg": 15, "drk": 8, "fem": 8, "ice": 15,
		"hml": 8, "all": 12}
	for code in expected:
		var product := CampaignBoosters.product_of(code)
		assert_eq(int(product.get("count", 0)), int(expected[code]), code)


func test_slot_count_matches_each_product() -> void:
	for product in CampaignBoosters.PRODUCTS:
		var code := String(product["code"])
		var plan := CampaignBoosters.recipe(code)
		var total := 0
		for kind in plan:
			total += int(plan[kind])
		assert_eq(total, int(product["count"]), code)


func test_small_sets_have_two_upper_sheet_slots_without_a_rare_slot() -> void:
	for code in CampaignBoosters.EIGHT_CARD_SETS:
		var plan := CampaignBoosters.recipe(code)
		assert_eq(int(plan.get("common", 0)), 6, code)
		assert_eq(int(plan.get("upper_sheet", 0)), 2, code)
		assert_false(plan.has("rare"), code)


func test_alliances_twelve_card_recipe() -> void:
	var plan := CampaignBoosters.recipe("all")
	assert_eq(int(plan.get("common", 0)), 8)
	assert_eq(int(plan.get("uncommon", 0)), 3)
	assert_eq(int(plan.get("rare", 0)), 1)


func test_booster_prices_are_fixed_across_settlements() -> void:
	for product in CampaignBoosters.PRODUCTS:
		var code := String(product["code"])
		var fixed_price := CampaignBoosters.list_price(code)
		assert_gt(fixed_price, 0, code)
		assert_eq(CampaignBoosters.price(code), fixed_price, code)
		assert_eq(CampaignBoosters.price_at(null, -1, code), fixed_price, code)
		assert_eq(CampaignBoosters.price_at(null, 99, code), fixed_price, code)


func test_unknown_product_does_not_have_a_price() -> void:
	assert_eq(CampaignBoosters.price("unknown"), 0)
	assert_eq(CampaignBoosters.price_at(null, 0, "unknown"), 0)
