// Beat Brock: navigate + grind + heal + gym battle.
// Exercises while(!...), nested if, match on an Int sensor, and Entity subtyping.
goal defeat_brock {
    while (!player.has_badge(Badge::Boulder)) {
        if (party.average_level() < 12) {
            navigate(Location::Route2);
            match (party.lead_hp_percent()) {
                0..25 => { navigate(Location::PewterPokeCenter); heal_team(); }
                _     => engage(Entity::WildPokemon, Strategy::Aggressive),
            }
        } else {
            navigate(Location::PewterGym);
            engage(NPC::GymLeader_Brock, Strategy::TypeAdvantage);
        }
    }
}
