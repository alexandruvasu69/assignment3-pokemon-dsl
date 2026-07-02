goal match_ok {
    match (party.lead_hp_percent()) {
        0..20 => { navigate(Location::PewterPokeCenter); heal_team(); }
        _     => roam_grass(),
    }
}
