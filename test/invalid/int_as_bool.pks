// error: condition must be Bool, got Int
goal bad {
    if (party.lead_hp_percent()) {
        flee();
    }
}
