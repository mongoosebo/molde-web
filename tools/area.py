"""The piece of the world the game covers. World frame: +X east, +Z south, metres, origin = Molde town centre.

West:  the east mouth of Haukabøtunnelen (fv. 662), which is blocked with rubble.
East:  100 m past the fence of Molde lufthavn, Årø.
North: just past Frænavarden (588 m); Tussentunnelen's south mouth lies inside.
South: out in the fjord."""
import math

LAT0, LON0 = 62.7375, 7.1591
MX = 111320.0 * math.cos(math.radians(LAT0))   # metres per degree of longitude
MZ = 111430.0                                   # metres per degree of latitude

X0, X1 = -5960.0, 6700.0
Z0, Z1 = -3960.0, 2840.0


def to_latlon(x, z):
    return LAT0 - z / MZ, LON0 + x / MX
