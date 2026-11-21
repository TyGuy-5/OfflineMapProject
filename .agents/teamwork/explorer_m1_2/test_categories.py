def get_category(name: str) -> str:
    lower = name.lower()
    import re
    words = set(re.findall(r'[a-zA-Z0-9]+', lower))
    
    gasKeywords = {"gas", "gasoline", "fuel", "oil", "petrol", "chevron", "shell", "exxon", "texaco", "bp", "mobil", "conoco", "tesoro"}
    coffeeKeywords = {"coffee", "cafe", "espresso", "starbucks", "barista"}
    foodKeywords = {"restaurant", "restaurants", "pizza", "diner", "grill", "burger", "burgers", "bar", "bakery", "kitchen", "pub", "bistro", "steakhouse", "taco", "sushi", "dining"}
    hotelKeywords = {"hotel", "motel", "inn", "resort", "suites", "lodge", "hostel"}
    parkingKeywords = {"parking", "garage"}
    parkKeywords = {"park", "parks", "trail", "lake", "forest"}
    hospitalKeywords = {"hospital", "clinic", "medical", "health", "doctor", "pharmacy", "infirmary"}
    airportKeywords = {"airport", "airfield", "airstrip"}
    groceryKeywords = {
        "grocery", "groceries", "supermarket", "supermarkets", "safeway",
        "walmart", "costco", "carrs", "kroger", "albertsons", "aldi",
        "sprouts", "bodega", "foodmart", "iga"
    }

    isFredMeyer = "fred" in words and "meyer" in words
    isTraderJoes = "trader" in words and ("joe" in words or "joes" in words)
    isWholeFoods = "whole" in words and ("foods" in words or "food" in words)

    if not words.isdisjoint(gasKeywords):
        return "gas"
    elif not words.isdisjoint(coffeeKeywords):
        return "coffee"
    elif not words.isdisjoint(foodKeywords):
        return "food"
    elif not words.isdisjoint(hotelKeywords):
        return "hotel"
    elif not words.isdisjoint(parkingKeywords):
        return "parking"
    elif not words.isdisjoint(parkKeywords):
        return "park"
    elif not words.isdisjoint(hospitalKeywords):
        return "hospital"
    elif not words.isdisjoint(airportKeywords):
        return "airport"
    elif not words.isdisjoint(groceryKeywords) or "market" in words or isFredMeyer or isTraderJoes or isWholeFoods:
        return "grocery"
    else:
        return "place"

test_items = [
    ("Chevron Gas Station", "gas"),
    ("Mocha Dan's Coffee Shop", "coffee"),
    ("The Pump House Restaurant", "food"),
    ("Las Vegas Pizza", "food"),
    ("Downtown Parking Garage", "parking"),
    ("Fairbanks Airport", "airport"),
    ("Fairbanks Memorial Hospital", "hospital"),
    ("Pioneer Park", "park"),
    ("Westmark Hotel", "hotel"),
    ("Fred Meyer", "grocery"),
    ("Fred Meyer Superstore", "grocery"),
    ("Fred Meyer Fuel", "gas"),
    ("Fred Meyer Pharmacy", "hospital"),
    ("Carrs", "grocery"),
    ("Carrs-Safeway", "grocery"),
    ("Costco Wholesale", "grocery"),
    ("Safeway", "grocery"),
    ("Walmart Supercenter", "grocery"),
    ("Trader Joe's", "grocery"),
    ("Whole Foods Market", "grocery"),
    ("Kroger", "grocery"),
    ("Albertsons", "grocery"),
    ("Aldi", "grocery"),
    ("Co-Op Market Grocery & Deli", "grocery"),
    ("Birch Hill Market", "grocery"),
    ("Missler's IGA", "grocery"),
    ("Public Toilet", "place"),
    ("Barrow High School", "place"),
]

for name, expected in test_items:
    cat = get_category(name)
    assert cat == expected, f"Failed for {name}: got {cat}, expected {expected}"
print("All 28 category classification tests passed!")
