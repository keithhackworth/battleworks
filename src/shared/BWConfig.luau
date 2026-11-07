-- Deliberately bounded BW v0.1; no expressions or general scripting features.
return table.freeze({
	MaxSourceBytes=16384, MaxLines=400, MaxInstructions=128,
	MaxDistance=1000, MaxRelativeAngle=1440, MaxAbsoluteAngle=36000, MaxFireSeconds=10,
	MaxProgramSeconds=180, MaxInstructionSeconds=90, StuckSeconds=3,
	DistanceTolerance=0.12, AngleTolerance=math.rad(0.8), ProgressDistance=0.03, ProgressAngle=math.rad(0.1),
	DefaultSource=[[# BattleWorks BW v0.1

forward(20)
turn_right(90)
forward(10)

turret_left(to=0)
fire()

back(5)
turn_left(90)
fire(2)]],
})
