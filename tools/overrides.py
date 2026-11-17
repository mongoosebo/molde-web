"""Corrections made by hand, from notes left inside the game (right mouse button, scripts/devtool.gd).
What the map and the laser data cannot know, or get wrong, is put right here by someone who knows the town."""

# OSM building id -> what is known about it.
#   wall / roof: colour (r, g, b);  levels: full storeys under the eaves;  style: one of the style numbers
BUILDINGS = {
    976346672: {"levels": 3},                          # Kirkebakken, by Storgata: three storeys
    88452659: {"wall": (172, 172, 168), "roof": (120, 122, 124)},   # Moldebadet: grey, like the stadium
}

# Trees that are not there: (x, z), anything within 1.5 m goes.
NO_TREES = [(22.97, -58.17)]

# Rådhusplassen: where Rosepiken stands (the south-west corner of the square, by Storgata).
ROSEPIKEN = (-10.6, -14.4)

# The terrace in front of the town hall: flat at the level of the entrance, with a flight of long steps
# down to the square. How far the terrace reaches out from the front wall, and the number of steps.
RADHUS_TERRACE = {"out": 6.0, "steps": 5, "tread": 0.32}

# Extra doors on the hand-built buildings: landmark key -> [(x, z, text of the sign over it)]
DOORS = {"storgata33": [(22.9, -37.3, "ROR-IKT")]}

# Car parks the map does not have: outlines (x, z).
PARKING = [
    [(-884, 347), (-846, 347), (-846, 364), (-884, 364)],        # in front of the houses on Julsundvegen at Reknes
]

# Buildings the map has lost or never had, traced from the laser surface model instead: everything that stands
# higher than min_h above the ground inside the window (x0, x1, z0, z1) and is smooth like a roof, not rough like
# a tree. `replaces` are the OSM ways that the tracing makes redundant.
LASER_BUILDINGS = [
    {"name": "Molde sjukehus", "kind": "hospital", "window": (-1140, -955, 18, 125), "min_h": 4.0, "replaces": [976341433]},
]

# Ways taken out of the ordinary handling because they are built by hand (the main stand of the athletics ground).
DROP_WAYS = [825396099]

# Molde idrettspark: the running track and the pitch inside it (OSM ways), the main stand on the north side
# (blue seats, roofed) and where the two open concrete stands on the south side are.
SPORTS = {"track": 945754531, "pitch": 1266294481, "tribune": 825396099, "stands": [(-203.5, -374.0), (-171.4, -382.7)]}

# The harbour front of the town centre is a built quay along the mapped shore line inside this box (x0, z0, x1, z1).
QUAY_BOX = (-150.0, 40.0, 330.0, 260.0)

# Where a cruise ship lies alongside instead of the car ferry.
CRUISE_AT = (-86.2, 309.9)

# Enclosed footbridges between buildings, above the ground: the line each follows, its width, and the height
# of its floor (None: 5 m over the highest ground under it). Brunvollbrua crosses Fannestrandvegen; the other
# joins the two parts of Molde Storsenter over the car park.
SKYWALKS = [
    {"pts": [(4766, -1064), (4772, -1052), (4790, -1016), (4795, -1006)], "w": 5.0, "y": None},
    {"pts": [(1216.5, -19.2), (1231.0, -23.8)], "w": 3.6, "y": 10.0},
]
DROP_WAYS += [730652403, 730652405, 730652406, 730652413]      # Brunvollbrua as the map has it: a building and footbridges

# Football pitches. Every pitch the map has for football gets its lines and goals; these are the exceptions.
#   PITCH_AT: a pitch of a given half length and half width at a point, in place of the mapped outline `way`
#   (a small five-a-side pitch on a larger gravel ground). STANDS: a roofed stand with seats along one long
#   side of a mapped pitch — the side nearest the given point.
PITCH_AT = [{"at": (3330.7, -742.9), "half": (20.0, 10.0), "way": 375663502}]
STANDS = [{"way": 121271815, "toward": (-494.0, -406.0), "length": 46.0, "rows": 6}]       # Reknesbanen, Træff's ground

# ---- from the notes of the evening of 15 November 2026 ----
BUILDINGS[1181478352] = {"levels": 2}                 # Strandgata / Kåre Solhjells veg: two storeys, not a low shed
LASER_BUILDINGS += [
    {"name": "Roseby", "kind": "retail", "window": (1015, 1165, -205, -95), "min_h": 4.0, "replaces": []},       # the shopping centre, east part
    {"name": "", "kind": "commercial", "window": (208, 250, -90, -54), "min_h": 4.0, "replaces": []},            # Romsdalsgata, by the park
]
PARKING += [[(172, -88), (200, -88), (200, -72), (172, -72)]]                # behind that building
# Squares paved for people, where the map has grass: outlines (x, z).
PAVED = [[(98, -176), (128, -170), (130, -154), (104, -150)]]                # Veøygata: the place for outdoor concerts
# Things that are not there: anything standing within 2 m of these points.
NO_PROPS = [(-49.26, -7.76)]                                                 # a bus shelter on Kirkebakken
# Barriers that are another kind than the map says: OSM way -> kind.
BARRIER_KIND = {375107678: "wall"}                                           # Gotfred Lies park: a concrete parapet, not a fence
# Ponds with benches round them (they face away from the water) and what stands in the middle.
PONDS = [{"way": 779119435, "fountain": "whale"}]
# Signs by doors: where on the wall was pointed at, and what it says.
DOOR_SIGNS = [{"at": (265.5, -303.8), "text": "Petter, Hanna og Laura <3"}]
# Ways into the parking hall in the hill under the church: the end of the way in, the way it goes in, its width and height.
PORTALS = [
    {"at": (60.0, -176.5), "dir": (0.0, -1.0), "w": 6.0, "h": 4.2, "name": "Molde parkeringshus"},       # for cars, from Kirkebakken
    {"at": (-61.0, -80.5), "dir": (-0.61, -0.79), "w": 2.6, "h": 2.9, "name": "Molde parkeringshus"},    # on foot
]

# ---- from the notes of the night of 15-16 November 2026 ----
NO_PROPS += [(-44.81, 2.43), (-38.19, 0.93), (-45.38, -0.88), (-16.38, 14.5), (-12.96, 28.1)]      # signs on Kirkebakken, benches on Torget
PARKING[-1] = [(184, -79), (200, -79), (200, -68), (184, -68)]            # the car park behind Romsdalsgata: only the level part
# Ground that is asphalt where the map has nothing: (x, z, how far it reaches). The open ground round the point,
# out to that distance, as far as the nearest buildings, roads and sidewalks.
ASPHALT_AT = [
    (171.1, 63.5, 10), (178.8, 64.4, 10), (221.1, 61.6, 8), (220.6, 65.0, 8), (230.3, 66.2, 8), (232.6, 62.5, 8),          # Apoteker Aas gate
    (-950.3, 12.7, 12), (-960.3, -10.2, 12),                                                                              # Parkvegen, by the hospital
    (-823.1, 343.2, 10), (-833.0, 346.9, 10), (-839.0, 354.4, 10), (-853.9, 386.8, 10), (-843.8, 385.8, 10),               # Julsundvegen
    (-831.8, 394.6, 10), (-826.9, 402.9, 10), (-829.8, 427.5, 10), (-811.6, 434.2, 10),                                    # Gideonvegen
    (174.4, -124.7, 14),                                                                                                  # a car park on Øvre veg
]
# Places where the sidewalk is broken by a way in for cars: (x, z, half width of the opening).
KERB_OPENINGS = [(225.0, 63.9, 3.5)]
BUILDINGS[976346020] = {"plain": True}                # Øvre veg: a plain roof, the fitted one was a mess
BUILDINGS[976347024] = {"plain": True, "levels": 2}   # Øvre veg: likewise, and two storeys
BUILDINGS[976348871] = {"levels": 5}                  # the apartment block on Elvemoloen
BUILDINGS[976346084] = {"name": "Bunnpris"}           # Bunnpris sentrum, Fjordgata
BUILDINGS[976346023] = {"join": True}                 # Romsdalsgata: built wall to wall with its neighbours
DOOR_SIGNS += [{"at": (-84.3, 108.4), "text": "BUNNPRIS", "shop": True, "osm_id": 976346084}]         # the way in to Bunnpris
LASER_BUILDINGS[1] = {"name": "Roseby", "kind": "retail", "window": (935, 1165, -260, -95), "min_h": 4.0, "replaces": [401877342], "one": True}
PLAYGROUNDS = [(224.3, 82.2)]                         # Apoteker Aas gate
STATUES = [{"kind": "donut", "at": (234.4, 78.6), "height": 4.0}]                # a stone ring standing on edge

# ---- notes of 16 November 2026, just after midnight ----
ASPHALT_AT += [(192.2, 66.2, 10), (198.8, 67.2, 10)]                         # Apoteker Aas gate / Rektor Brinchmanns gate
BUILDINGS[339192904] = {"wall": (150, 40, 34)}                                # Langmyrvegen: a red house
WHALE_LIFT = 0.30                                                             # the whale sits this much higher in its pond

# ---- notes of 16 November 2026, 00:30 ----
SKYWALKS[1]["y"] = 13.0                                # the walkway at Molde Storsenter: a floor higher, to drive under
BUILDINGS[1087692413] = {"add_levels": 1}              # Fannestrandvegen: one floor higher than measured
ASPHALT_AT += [(273.0, -571.0, 2.8), (273.0, -574.5, 2.8), (273.0, -578.0, 2.8), (273.0, -581.5, 2.8), (273.0, -585.0, 2.8),
               (273.0, -588.5, 2.8), (273.0, -591.5, 3.2)]             # Langmyrvegen: the drive up to the garage
MERCEDES_AT = (273.0, -583.0, 0.0)                  # a Mercedes estate standing in that drive, nose to the garage
DOOR_SIGNS += [{"at": (264.3, -582.3), "text": "", "window": True, "osm_id": 339192904}]     # a big upstairs window with the dog in it
# Places without road paint: no lines, crossings or give-way marks within the distance of the point.
NO_MARKINGS = [(120.0, 35.0, 62.0)]                    # Rutebilholdeplassen: one big open sheet of asphalt
BICYCLE_AT = (-1.0, -37.9)                             # Rådhusplassen
BUILDINGS[945122874] = {"wall": (236, 236, 230)}       # Glomstuvegen: a white house

# Storgata, building by building, from Statens vegvesen's road photos of 2025 (tools/vegbilder.py lists them,
# tools/colours.py --vegbilder --crops cuts out a picture of each house): the wall colour as seen by eye, where
# the colour read off automatically (data/colours_vegbilder.json) was missing or wrong.
for _id, _wall in {
    401877809: (176,180,182), 401865571: (122,72,60), 733022952: (236,234,226), 976346097: (206,112,88),
    401865430: (236,234,226), 976346098: (236,234,226), 976346108: (178,56,54), 976347688: (236,234,226),
    976342817: (214,150,128), 976346107: (168,160,148), 976346102: (228,214,186), 976346103: (170,160,146),
    976346086: (208,194,182), 976346085: (212,122,98), 976346067: (204,186,166), 976342811: (236,234,226),
    976342807: (200,196,186), 976347696: (224,104,90), 976346081: (188,190,188), 976346087: (226,216,186),
    976347493: (226,226,222), 976346071: (190,192,190), 976346077: (168,164,154), 976346075: (236,234,226),
    976346073: (158,54,50), 976346079: (98,128,158), 401866062: (232,226,212), 172575812: (222,222,218),
    976346024: (212,214,212), 976346023: (236,176,72), 172575284: (236,234,226), 9100000040: (188,62,58),
    976346101: (236,234,226), 401865420: (236,234,226), 976346105: (236,234,226),
}.items():
    BUILDINGS.setdefault(_id, {})["wall"] = _wall
BUILDINGS[733022952]["roof"] = (186, 128, 92)            # orange tiles
BUILDINGS[976346023]["roof"] = (170, 80, 60)             # red tiles
# no colour from the photos for these: scaffolding, a tree or a parked lorry stood in the way
NO_PHOTO_COLOUR = {730684613, 976346106, 935525934, 320343046, 976346076, 401877810}
for _id, _wall in {320343046: (236, 234, 226), 320343048: (236, 234, 226), 976330687: (216, 200, 160), 976346076: (158, 160, 138)}.items():
    BUILDINGS.setdefault(_id, {})["wall"] = _wall
