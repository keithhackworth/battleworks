-- Shared arcade contact law. The suspension owns vertical gravity and support;
-- this module resolves only the horizontal projection while grounded.
local T={GravityScale=.40,MaxSupportAngle=55}
T.MinSupportNormal=math.cos(math.rad(T.MaxSupportAngle))
T.MaxGradient=math.tan(math.rad(T.MaxSupportAngle))
local function blend(a,b,t) return a+(b-a)*t end
function T.contact(pitch,roll,tracked,static,kinetic)
 if (pitch or 0)==0 and (roll or 0)==0 then return 0,0,static,kinetic,1 end
 local forward,right=math.tan(pitch or 0),math.tan(roll or 0)
 local gradeSquared=forward*forward+right*right
 if gradeSquared<1e-8 then return 0,0,static,kinetic,1 end
 local grade=math.sqrt(gradeSquared)
 local degrees=math.deg(math.atan(grade))
 local normalSquared=1/(1+gradeSquared)
 local projection=T.GravityScale*normalSquared
 local fade=math.clamp(degrees/14,0,1)
 fade=fade*fade*(3-2*fade)
 local start,finish=if tracked then 34 else 24,if tracked then 45 else 39
 local failure=math.clamp((degrees-start)/(finish-start),0,1)
 local treadGrip=if tracked then 1.04 else .89
 local movingGrip=treadGrip*(1-.53*failure)
 local staticMaterial=math.min(1.15,static/12)
 local kineticMaterial=math.min(1.15,kinetic/8)
 local staticLimit=blend(static,projection*(movingGrip+.15)*staticMaterial,fade)
 local kineticLimit=math.min(staticLimit,blend(kinetic,projection*movingGrip*kineticMaterial,fade))
 -- The reserve describes uphill movement after paying gravity. A zero
 -- reserve still allows descent and lets the existing traction solver slip.
 local uphill=math.clamp((kineticLimit/projection-grade)/.36,0,1)
 return -forward*projection,-right*projection,staticLimit,kineticLimit,uphill
end
function T.classify(pitch,roll,profile)
 local gradeSquared=math.tan(pitch)^2+math.tan(roll)^2
 if gradeSquared>T.MaxGradient^2 then return "Impossible" end
 local _,_,_,_,wheels=T.contact(pitch,roll,false,profile.staticFriction,profile.kineticFriction)
 local _,_,_,_,tracks=T.contact(pitch,roll,true,profile.trackedStaticFriction or profile.staticFriction,profile.trackedKineticFriction or profile.kineticFriction)
 if wheels>=.35 and tracks>=.35 then return "Easy" end
 if tracks>=.35 then return "Treads" end
 return "Impossible"
end
return T
