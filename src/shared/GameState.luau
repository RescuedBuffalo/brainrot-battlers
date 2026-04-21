--!strict
-- Shared type definitions. This module exports types only; its runtime return
-- is an empty table so it can still be `require`d from the client for type use.

export type UnitId = string
export type Rarity = "common" | "rare" | "epic" | "legendary" | "mythic"
export type Side = "player" | "enemy"
export type Phase = "lobby" | "shop" | "combat" | "postcombat" | "victory" | "defeat"

export type BoardUnit = {
    unitId: UnitId,
    star: number,
    rarity: Rarity,
    x: number,
    y: number,
}

export type BenchUnit = {
    unitId: UnitId,
    star: number,
    rarity: Rarity,
}

export type ShopSlot = {
    unitId: UnitId?,
    sold: boolean,
}

export type PlayerState = {
    phase: Phase,
    round: number,
    gold: number,
    hp: number,
    level: number,
    xp: number,
    bench: { BenchUnit? },
    board: { BoardUnit },
    shop: { ShopSlot },
    streak: number,
    streakType: "win" | "loss" | "none",
    collection: { [UnitId]: Rarity },
    bestRound: number,
    totalWins: number,
}

export type CombatUnit = {
    side: Side,
    unitId: UnitId,
    star: number,
    rarity: Rarity,
    x: number,
    y: number,
    hp: number,
    maxHp: number,
    atk: number,
    attackSpeed: number,
    range: number,
    mana: number,
    maxMana: number,
    atkCd: number,
    moveCd: number,
    shield: number,
    stunned: number,
    asBuff: number,
    hasAttacked: boolean,
    dead: boolean,
}

export type CombatEventKind = "dmg" | "death" | "ability" | "shoot" | "aoe" | "move" | "heal" | "shield"
export type CombatEvent = {
    kind: CombatEventKind,
    tick: number,
    source: number?,
    target: number?,
    targets: { number }?,
    amount: number?,
    extra: any?,
}

return {}
