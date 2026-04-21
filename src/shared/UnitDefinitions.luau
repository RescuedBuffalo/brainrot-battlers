--!strict
-- Source of truth for every brainrot unit. Stats are base values BEFORE
-- star, rarity, and trait multipliers are applied.

return {
    skibidi    = { name="Skibidi Scout",         emoji="🚽", cost=1, hp=500,  atk=45, attackSpeed=0.85, range=1, maxMana=60,  traits={"ohio","assassin"},   abilityName="Flush Strike",     abilityDesc="Teleport behind lowest HP enemy, deal 180% AD" },
    sigma      = { name="Sigma Slapper",         emoji="🗿", cost=1, hp=650,  atk=38, attackSpeed=0.7,  range=1, maxMana=70,  traits={"sigma","brawler"},   abilityName="Gigachad Slam",    abilityDesc="Deal 220% AD + 1s stun" },
    gyatt      = { name="Gyatt Gunner",          emoji="🔥", cost=1, hp=450,  atk=50, attackSpeed=0.9,  range=3, maxMana=50,  traits={"ohio","ranged"},     abilityName="Rapid Fire",       abilityDesc="Fire 3 shots at lowest HP, 70% AD each" },
    tralalero  = { name="Tralalero Tripler",     emoji="🦈", cost=2, hp=700,  atk=55, attackSpeed=0.95, range=1, maxMana=55,  traits={"italian","brawler"}, abilityName="Triple Chomp",     abilityDesc="3 rapid strikes, 80% AD each" },
    bombardiro = { name="Bombardiro Bomber",     emoji="✈️", cost=2, hp=550,  atk=50, attackSpeed=0.7,  range=4, maxMana=60,  traits={"italian","ranged"},  abilityName="Carpet Bomb",      abilityDesc="AoE: 170% AD in 2 tiles of target" },
    tungtung   = { name="Tung Tung Tanker",      emoji="🪵", cost=3, hp=1500, atk=60, attackSpeed=0.65, range=1, maxMana=80,  traits={"italian","brawler"}, abilityName="Timber Wall",      abilityDesc="Gain 700 shield, 3s taunt" },
    ballerina  = { name="Ballerina Cappuccina",  emoji="☕", cost=3, hp=800,  atk=65, attackSpeed=0.95, range=1, maxMana=45,  traits={"italian","sigma"},   abilityName="Caffeine Rush",    abilityDesc="Nearby allies: +50% AS for 5s" },
    capuchino  = { name="Capuchino Assasino",    emoji="🔪", cost=4, hp=850,  atk=90, attackSpeed=1.0,  range=1, maxMana=50,  traits={"assassin","sigma"},  abilityName="Shadow Leap",      abilityDesc="Leap to priciest enemy, 320% AD crit" },
    fanum      = { name="Fanum Tax Collector",   emoji="💰", cost=4, hp=950,  atk=78, attackSpeed=0.85, range=1, maxMana=65,  traits={"sigma","brawler"},   abilityName="Tax Collection",   abilityDesc="260% AD + steal 2 gold" },
    ohio       = { name="Ohio Final Boss",       emoji="👹", cost=5, hp=1200, atk=85, attackSpeed=0.8,  range=3, maxMana=100, traits={"ohio","mage"},       abilityName="Reality Collapse", abilityDesc="Deal 250% AD to ALL enemies" },
}
