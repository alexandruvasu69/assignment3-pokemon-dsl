goal simple {
    navigate(Location::PalletTown);
    if (party.is_full()) {
        heal_team();
    } else {
        roam_grass();
    }
}
