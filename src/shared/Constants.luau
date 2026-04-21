--!strict
-- Global game tunables. All times are in seconds.

return {
    COLS = 6,
    ROWS = 6,
    BENCH_SIZE = 9,
    TICK_RATE = 0.22,
    PLAYER_ROWS = {3, 4, 5},
    ENEMY_ROWS = {0, 1, 2},
    TOTAL_ROUNDS = 10,
    STARTING_GOLD = 4,
    STARTING_HP = 100,
    STARTING_LEVEL = 2,
    BASE_INCOME = 5,
    MAX_INTEREST = 5,
    MAX_LEVEL = 8,
    REROLL_COST = 2,
    XP_COST = 4,
    XP_PER_BUY = 4,
    COMBAT_MAX_TICKS = 500,
    STAR_MULT = { [1] = 1.0, [2] = 1.8, [3] = 3.2 },
    RARITY_ORDER = { "common", "rare", "epic", "legendary", "mythic" },
    SHOP_SIZE = 5,
    ABILITY_FLASH_TICKS = 4,
    HIT_FLASH_TICKS = 2,
    MOVE_COOLDOWN = 0.45,
    ATTACK_MANA_GAIN = 10,
}
