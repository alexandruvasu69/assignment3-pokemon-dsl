"""
World model for PokéScript navigation (demo route only), transcribed from pret/pokered.

Coordinates are map-local (x, y) and match /state's player.position frame — validated
against Red's House warps (pokered (2,7)/(7,1) == the coords the emulator reports).
Keys are the backend's `map_name` strings (note the apostrophes).

Only the Oak's Lab -> Pallet Town -> Route 1 route is authored; the structure scales to
the full corridor (add maps + warps/connections/waypoints).

Per map:
  warps       : [(x, y, dest_map)]      step onto (x,y) to warp (tiles may read non-walkable)
  connections : {edge: dest_map}        walk off that map edge (edge in N/S/E/W)
  waypoints   : {name: (x, y)}          named tiles (edge exit gap, grass, nurse, ...)
"""

WORLD = {
    "Oak's Lab": {
        "warps": [(4, 11, "Pallet Town"), (5, 11, "Pallet Town")],
        "connections": {},
        "waypoints": {},
    },
    "Pallet Town": {
        "warps": [(5, 5, "Red's House 1F"), (13, 5, "Blue's House"), (12, 11, "Oak's Lab")],
        "connections": {"north": "Route 1", "south": "Route 21"},
        # north_exit: the walkable gap in the top fence (empirically tuned).
        "waypoints": {"north_exit": (10, 0)},
    },
    "Route 1": {
        "warps": [],
        "connections": {"north": "Viridian City", "south": "Pallet Town"},
        # grass: a tall-grass tile to hunt in (empirically tuned).
        "waypoints": {"grass": (9, 32)},
    },
}

# DSL Location member -> (map_name, optional waypoint name)
LOCATION_MAP = {
    "PalletTown": ("Pallet Town", None),
    "OaksLab": ("Oak's Lab", None),
    "Route1": ("Route 1", "grass"),
    "ViridianCity": ("Viridian City", None),
}

# tile_ids that count as tall grass in the overworld tileset (empirically tuned).
GRASS_TILE_IDS = {0x52}
