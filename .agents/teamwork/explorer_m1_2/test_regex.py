import re

def parse_coordinates(query: str):
    trimmed = query.strip()
    if not trimmed:
        return None
    
    pattern = r"([+-]?\d+(?:\.\d+)?)\s*°?\s*([NSEWnsew])?"
    matches = list(re.finditer(pattern, trimmed))
    matches = [m for m in matches if m.group(1)]
    if len(matches) != 2:
        return None
    
    non_coord = re.sub(pattern, "", trimmed)
    allowed = set(" ,;\t\n°/")
    if not all(c in allowed for c in non_coord):
        return None
    
    components = []
    for m in matches:
        val = float(m.group(1))
        card = m.group(2).upper() if m.group(2) else None
        components.append((val, card))
        
    c0, c1 = components[0], components[1]
    val0, dir0 = c0
    val1, dir1 = c1
    
    lat = None
    lon = None
    
    if dir0 and dir1:
        if dir0 in ("N", "S") and dir1 in ("E", "W"):
            lat = -abs(val0) if dir0 == "S" else abs(val0)
            lon = -abs(val1) if dir1 == "W" else abs(val1)
        elif dir0 in ("E", "W") and dir1 in ("N", "S"):
            lon = -abs(val0) if dir0 == "W" else abs(val0)
            lat = -abs(val1) if dir1 == "S" else abs(val1)
        else:
            return None
    elif dir0:
        if dir0 in ("N", "S"):
            lat = -abs(val0) if dir0 == "S" else abs(val0)
            lon = val1
        else:
            lon = -abs(val0) if dir0 == "W" else abs(val0)
            lat = val1
    elif dir1:
        if dir1 in ("N", "S"):
            lat = -abs(val1) if dir1 == "S" else abs(val1)
            lon = val0
        else:
            lon = -abs(val1) if dir1 == "W" else abs(val1)
            lat = val0
    else:
        lat = val0
        lon = val1
        
    if lat is None or lon is None:
        return None
    if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
        return None
        
    return (lat, lon)

test_cases = [
    ("64.8436, -147.7215", (64.8436, -147.7215)),
    ("  64.8569 ;  -147.8028 ", (64.8569, -147.8028)),
    ("64.8436° N, 147.7215° W", (64.8436, -147.7215)),
    ("64.8436° S, 147.7215° E", (-64.8436, 147.7215)),
    ("147.7215° W, 64.8436° N", (64.8436, -147.7215)),
    ("64.8436 ° N , 147.7215 ° W", (64.8436, -147.7215)),
    ("64.8436° N, -147.7215", (64.8436, -147.7215)),
    ("-147.7215 W, 64.8436", (64.8436, -147.7215)),
    ("-64.8436 S, -147.7215 W", (-64.8436, -147.7215)),
    ("64.8436n 147.7215w", (64.8436, -147.7215)),
    ("Fairbanks, AK", None),
    ("95.0, -147.0", None),
    ("64.0, -185.0", None),
    ("64° N, 65° N", None),
    ("140° W, 145° W", None),
    ("Room 10, Table 20", None),
    ("Highway 101, Mile 50", None),
    ("64.8436° N, 147.7215° W extra", None),
    ("123.456.789", None),
    ("64.8436 / -147.7215", (64.8436, -147.7215)),
]

for query, expected in test_cases:
    res = parse_coordinates(query)
    assert res == expected, f"Failed for {query}: got {res}, expected {expected}"
print("All 20 test cases passed!")
