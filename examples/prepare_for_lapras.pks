// Party/PC management + shopping. Exercises interact(Interactable::PC), pc.deposit, buy.
goal prepare_for_lapras {
    if (inventory.count(Item::GreatBall) < 10) {
        navigate(Location::CeruleanCity);
        buy(Item::GreatBall, 10);
    }
    if (party.is_full()) {
        navigate(Location::CeruleanPokeCenter);
        interact(Interactable::PC);
        pc.deposit(Slot::6);
    }
    navigate(Location::SilphCo_Floor7);
    interact(NPC::SilphEmployee);
}
