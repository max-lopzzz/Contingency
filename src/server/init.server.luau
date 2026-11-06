local SurvivorService = require(script.SurvivorService)
local BombService = require(script.BombService)
local RoundService = require(script.RoundService)

SurvivorService.Init()
BombService.Init()
RoundService.Init()
RoundService.Run()
