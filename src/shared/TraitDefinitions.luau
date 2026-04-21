--!strict
-- Trait tier tables. tiers = { {requiredCount, uiLabel}, ... } ordered ascending.
-- CombatEngine resolves active tier by matching the highest tier whose
-- requiredCount is met by distinct-unitId count on the board.

return {
    italian   = { name="Brainrot Italian", emoji="🍝", tiers={ {2, "+20% ATK"},         {4, "+50% ATK"} } },
    ohio      = { name="Ohio Chaos",       emoji="🌀", tiers={ {2, "+20% crit"},        {3, "+40% crit, 2x dmg"} } },
    sigma     = { name="Sigma Grindset",   emoji="💪", tiers={ {2, "+25 start mana"},   {3, "+50 start mana"} } },
    brawler   = { name="Brawler",          emoji="🛡️", tiers={ {2, "+300 HP"},          {4, "+800 HP"} } },
    ranged    = { name="Ranged",           emoji="🎯", tiers={ {2, "+25% AS"},          {3, "+55% AS"} } },
    assassin  = { name="Assassin",         emoji="🗡️", tiers={ {2, "1st hit: 2x crit"},  {3, "1st hit: 3x crit"} } },
    mage      = { name="Mage",             emoji="🔮", tiers={ {1, "Abilities +30% dmg"} } },
}
