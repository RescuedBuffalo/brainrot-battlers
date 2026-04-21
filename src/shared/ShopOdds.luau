--!strict
-- Shop tier probability (percent) by player level.
-- Row = level, Column = unit cost tier (1..5).

return {
    [1] = {100, 0,  0,  0,  0},
    [2] = {75,  25, 0,  0,  0},
    [3] = {55,  30, 15, 0,  0},
    [4] = {45,  33, 20, 2,  0},
    [5] = {35,  35, 25, 5,  0},
    [6] = {22,  33, 30, 13, 2},
    [7] = {14,  22, 30, 25, 9},
    [8] = {8,   14, 23, 33, 22},
}
