# Generated from PokeScript by pokemondsl::Compile. Do not edit.
from pokescript_rt import *


def prepare_for_lapras():
    if (count("GreatBall") < 10):
        navigate("CeruleanCity")  # TODO: navigation
        buy("GreatBall", 10)
    if is_full():
        navigate("CeruleanPokeCenter")  # TODO: navigation
        interact("PC")
        pc_deposit("6")
    navigate("SilphCo_Floor7")  # TODO: navigation
    interact("SilphEmployee")


if __name__ == "__main__":
    prepare_for_lapras()
