# Generated from PokeScript by pokemondsl::Compile. Do not edit.
from pokescript_rt import *


def grind():
    navigate("Route24_Grass")  # TODO: navigation
    while (lead_hp_percent() > 20):
        roam_grass()  # TODO: navigation
        engage("WildPokemon", "Aggressive")
    navigate("CeruleanPokeCenter")  # TODO: navigation
    heal_team()


def challenge_misty():
    navigate("CeruleanGym")  # TODO: navigation
    engage("GymLeader_Misty", "TypeAdvantage")


def main():
    while not (has_badge("Cascade")):
        if (average_level() < 18):
            grind()
        else:
            challenge_misty()


if __name__ == "__main__":
    main()
