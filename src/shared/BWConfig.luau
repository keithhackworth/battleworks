-- Bounded BW v0.2; no loops, user functions or arbitrary Luau.
return table.freeze({
	MaxSourceBytes=16384, MaxLines=400, MaxInstructions=128,
	MaxCompiledInstructions=512,MaxBlockDepth=12,MaxExpressionDepth=32,MaxExpressionNodes=2048,
	MaxTokensPerLine=512,MaxArrayItems=64,MaxStringBytes=2048,MaxVariables=128,
	MaxScannerCalls=128,MaxOutputEvents=256,MaxOutputBytes=2048,IndentWidth=4,
	CycleCosts={read=1,write=1,arithmetic=1,comparison=1,logical=1,branch=1,call=0},
	MaxDistance=1000, MaxRelativeAngle=1440, MaxAbsoluteAngle=36000, MaxFireSeconds=10,
	MaxProgramSeconds=180, MaxInstructionSeconds=90, StuckSeconds=3,
	DistanceTolerance=0.12, AngleTolerance=math.rad(0.8), ProgressDistance=0.03, ProgressAngle=math.rad(0.1),
	DefaultSource=[[# BattleWorks BW v0.2

forward(20)
turn_right(90)
forward(10)

turret_left(to=0)
fire()

back(5)
turn_left(90)
fire(2)]],
})
