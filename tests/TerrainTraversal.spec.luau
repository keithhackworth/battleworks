local Traverse=require(Shared.TerrainTraversal)
local Drive=require(Shared.RattlerDrive)
local Motion=require(Shared.VehicleMotion)
local Sim=require(Shared.TankSimulation)
local Input=require(Shared.InputCommand)
local Materials=require(Shared.TerrainMaterials)
local Environment=require(Shared.Environment)
local Heightfield=require(Shared.WorldHeightfield)
local Geometry=require(Shared.WorldObjectGeometry)
local Footprint=require(Shared.FootprintSupport)
local grass=Materials.fromMaterial("Grass")
local function run(kind,slope,rate,throttle,initial,roll,steer,profile)
 local body=Sim.new(Vector3.zero,kind)
 local command=Input.neutral();command.throttle=throttle;command.steer=steer or 0
 Motion.setVelocity(body,Vector3.new(0,0,-(initial or 0)))
 profile=profile or grass
 for _=1,rate*3 do
  Motion.beginStep(body,1/rate)
  Drive.ground(body,command,1/rate,1,profile.staticFriction,profile.kineticFriction,1,1,math.rad(slope),math.rad(roll or 0))
 end
 return body
end
for _,kind in {"Boomer","Rattler"} do
 assert(run(kind,15,60,1).speed>8,"both drivetrains climb gentle slopes")
 assert(math.abs(run(kind,15,60,0).speed)<1e-6,"brakes hold on gentle slopes")
 assert(run(kind,44,60,1).speed<0,"both drivetrains fail to climb excessively steep ground")
 assert(run(kind,44,60,0).speed<0,"gravity overcomes holding grip")
 local braking=run(kind,20,60,0,-12)
 assert(math.abs(braking.speed)<.1,"braking controls a downhill roll where grip is sufficient")
 local turn=run(kind,30,60,1,6,24,1)
 assert(math.abs(turn.velocityX)>.1 and turn.motionSlipping,"steering shares lateral and longitudinal slope traction")
end
local tracked=run("Boomer",32,60,1)
local wheeled=run("Rattler",32,60,1)
assert(tracked.speed>8 and wheeled.speed<tracked.speed*.35,"tracks climb the same slope that limits wheels")
for _,rate in {30,120} do
 assert(math.abs(run("Boomer",32,rate,1).speed-tracked.speed)<2,"uphill behavior stays comparable across tick rates")
end
assert(Traverse.classify(math.rad(15),0,grass)=="Easy")
assert(Traverse.classify(math.rad(32),0,grass)=="Treads")
assert(Traverse.classify(math.rad(44),0,grass)=="Impossible")
assert(Traverse.classify(math.rad(28),0,Materials.fromMaterial("Mud"))=="Impossible","material changes uphill classification")
assert(run("Boomer",23,60,1,0,0,0,Materials.profile("Grass",1,0,1)).speed<run("Boomer",23,60,1).speed,"wet grass lowers real uphill traction")
local field=Heightfield.new(96,96)
for z=0,field.rows do for x=0,field.columns do
 field.heights[Heightfield.index(field,x,z)]=math.round((48-z*96/field.rows)*.625*Heightfield.Unit)
end end
local env=Environment.create(Vector2.new(96,96))
env.rocks={};env.logs={};env.trees={};env.zones={}
env.terrainSettings={terrain=field,width=96,depth=96,ground={material="Grass"}}
local position=Vector3.zero
local shape={ContactWidth=5,ContactLength=6}
local h,p,r,_,_,material=Environment.pose(env,position,0,shape)
local board=Geometry.from({0,0,0},{math.deg(math.atan(.625)),0,0},{20,.1,40},1);board.material=grass
local bh,bp,br,bm=Footprint.solve({board},Vector3.new(0,Geometry.planeHeight(board,0,0),0),0,shape)
assert(bh and math.abs(p-bp)<.02 and math.abs(r-br)<.02 and material==bm,"equivalent sculpted and constructed grass surfaces provide equivalent contact inputs")
local steep=Geometry.from({0,0,0},{50,0,0},{20,.1,40},1)
assert(Footprint.solve({steep},Vector3.new(0,Geometry.planeHeight(steep,0,0),0),0,shape)~=nil,"steep ramp retains support so a vehicle may slide or descend")
assert(Geometry.support(Geometry.from({0,0,0},{70,0,0},{20,.1,40},1),0,0,100)==nil,"wall-like faces are never suspension support")
for z=0,field.rows do for x=0,field.columns do
 field.heights[Heightfield.index(field,x,z)]=math.clamp(-z*12+96,-96,96)*Heightfield.Unit
end end
local before=Vector3.new(0,0,0)
local wallTank=Sim.new(before,"Boomer")
local neutral=Input.neutral()
Motion.setVelocity(wallTank,Vector3.new(0,0,-12))
Sim.step(wallTank,neutral,1/60,Vector2.new(96,96),env)
assert(wallTank.position.Z==0,"incoming momentum cannot pull a tank up a wall-like sculpted rise")
Motion.setVelocity(wallTank,Vector3.new(0,0,12))
Sim.step(wallTank,neutral,1/60,Vector2.new(96,96),env)
assert(wallTank.position.Z>0,"the same geometric safeguard permits downhill movement")
for _,kind in {"Boomer","Rattler"} do
 local tank=Sim.new(before,kind)
 -- A tiny advance on a steep face previously fit inside the fixed tolerance.
 Motion.setVelocity(tank,Vector3.new(0,0,-.05))
 Sim.moveBody(tank,neutral,1/60,Vector2.new(96,96),env,true)
 tank.position=Vector3.new(0,tank.position.Y,-.001)
 Sim.reconcileGround(tank,env)
 assert(tank.position.Z==0,"deferred contact reconciliation blocks even tiny uphill wall advances")
 assert(tank.terrainFaceDegrees>60,"authoritative state reports the actual steep terrain face")
end
do
 local settings=env.terrainSettings
 local fresh=Heightfield.new(96,96);settings.terrain=fresh
 local point=Vector3.zero
 Heightfield.brush(fresh,96,96,point,"Carve",9,24,.45,-8,1)
 assert(Heightfield.sample(fresh,96,96,0,0)==-8 and Heightfield.sample(fresh,96,96,30,0)==0,
  "ravine tool cuts the channel while preserving distant ground")
 for code,name in Heightfield.Paint do
  assert(next(Heightfield.paint(fresh,96,96,point,8,code)),"changing paint touches terrain chunks")
  local _,kind,_,_,profile=Environment.sample(env,0,0,1)
  assert(kind==name and profile==Materials.fromMaterial(name),"paint changes real contact material: "..name)
 end
 for z=0,fresh.rows do for x=0,fresh.columns do
  fresh.heights[Heightfield.index(fresh,x,z)]=math.max(0,math.abs(x-8)+math.abs(z-8)-1)*16
 end end
 assert(next(Heightfield.fillWater(fresh,96,96,Vector3.new(0,8,30),1)),"water creates a downhill path")
 local _,basinLevel=Heightfield.surface(fresh,96,96,0,0)
 local _,sourceLevel=Heightfield.surface(fresh,96,96,0,30)
 local _,ridgeLevel=Heightfield.surface(fresh,96,96,35,35)
 assert(basinLevel and sourceLevel and sourceLevel>basinLevel and ridgeLevel==nil,"water follows elevation and remains out of high disconnected ground")
 local _,kind=Environment.sample(env,0,0,1)
 assert(kind=="Water","flooded cells affect vehicle physics")
 Heightfield.validate(fresh,96,96)
 settings.terrain=Heightfield.new(96,96)
 local pond=settings.terrain
 pond.water=table.create(pond.rows*pond.columns,0)
 local x,z=Heightfield.cell(pond,96,96,1,0)
 local index=z*pond.columns+x+1
 pond.water[index]=Heightfield.WaterOffset+20
 local _,_,_,_,bottom=Environment.sample(env,1,0,1)
 assert(bottom==Materials.fromMaterial("Mud"),"flooded ground uses mud traction automatically")
 local crossing=Input.neutral();crossing.throttle=1
 for _,kind in {"Boomer","Rattler"} do
  for _,depth in {20,21} do
   pond.water[index]=Heightfield.WaterOffset+depth
   local tank=Sim.new(Vector3.new(-.1,0,0),kind);tank.yaw=-math.pi/2
   Motion.setVelocity(tank,Vector3.new(12,0,0))
   Sim.step(tank,crossing,1/60,Vector2.new(96,96),env)
   assert((tank.position.X>=0)==(depth==20),"both drivetrains stop only when water is deeper than half the hull")
  end
 end
end
print("Unified terrain slopes, traction, braking, tick-rate stability and geometry passed")
