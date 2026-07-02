// Goal composition: reusable routines invoked by name from an entry goal.
goal grind {
    navigate(Location::Route24_Grass);
    while (party.lead_hp_percent() > 20) {
        roam_grass();
        engage(Entity::WildPokemon, Strategy::Aggressive);
    }
    navigate(Location::CeruleanPokeCenter);
    heal_team();
}

goal challenge_misty {
    navigate(Location::CeruleanGym);
    engage(NPC::GymLeader_Misty, Strategy::TypeAdvantage);
}

goal main {
    while (!player.has_badge(Badge::Cascade)) {
        if (party.average_level() < 18) {
            grind();
        } else {
            challenge_misty();
        }
    }
}
