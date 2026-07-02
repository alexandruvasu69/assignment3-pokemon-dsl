# Generated from PokeScript by pokemondsl::Compile. Do not edit.
from pokescript_rt import *


def defeat_brock():
    while not (has_badge("Boulder")):
        if (average_level() < 12):
            navigate("Route2")  # TODO: navigation
            _m298 = lead_hp_percent()
            if 0 <= _m298 <= 25:
                navigate("PewterPokeCenter")  # TODO: navigation
                heal_team()
            else:
                engage("WildPokemon", "Aggressive")
        else:
            navigate("PewterGym")  # TODO: navigation
            engage("GymLeader_Brock", "TypeAdvantage")


if __name__ == "__main__":
    defeat_brock()
