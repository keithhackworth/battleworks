-- Editor UI only. Picking, transactions and world geometry live elsewhere.
local Placement=require(game.ReplicatedStorage.Shared.ModelPlacement)
local Document=require(game.ReplicatedStorage.Shared.WorldEditorDocument)
local Presentation=require(script.Parent.WorldEditorPresentation)
local Skin=require(script.Parent.WorldEditorSkin)
local View={};View.__index=View
local ink=Color3.fromRGB(241,222,174)
local accent=Color3.fromRGB(233,181,80)
local panel=Color3.fromRGB(33,39,25)
local collisionTile=Color3.fromRGB(41,70,53)
View.buttonColor=Color3.fromRGB(61,71,45)
View.activeColor=Color3.fromRGB(105,112,56)
local function make(class,parent,props)
 local p=Instance.new(class);for key,value in props do p[key]=value end;p.Parent=parent;return p
end
local function text(parent,name,value,height)
 return make("TextLabel",parent,{Name=name,Text=value,Size=UDim2.new(1,-8,0,height or 24),BackgroundTransparency=1,TextColor3=ink,TextSize=13,Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true})
end
local function button(parent,name,value,size,position)
 local control=make("TextButton",parent,{Name=name,Text=value,Size=size or UDim2.new(1,0,0,32),Position=position or UDim2.fromOffset(0,0),TextColor3=ink,BackgroundColor3=View.buttonColor,TextSize=13,Font=Enum.Font.GothamMedium,Selectable=true,BorderSizePixel=0,AutoButtonColor=true})
 make("UICorner",control,{CornerRadius=UDim.new(0,5)})
 return control
end
local function scrolling(parent,name,size,position)
 local p=make("ScrollingFrame",parent,{Name=name,Size=size,Position=position,BackgroundColor3=panel,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=5,ScrollBarImageColor3=accent,Active=true})
 return p
end
local function rectContains(p,point)
 local at,size=p.AbsolutePosition,p.AbsoluteSize
 return point.X>=at.X and point.X<=at.X+size.X and point.Y>=at.Y and point.Y<=at.Y+size.Y
end
function View.new(context)
 local self=setmetatable({connections={},paletteConnections={},thumbnails={},fields={},fieldLabels={},displayedFields={},callbacks={},buttons={}},View)
 local frame=make("Frame",context.parent,{Name="World Editor",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(30,36,24),BorderSizePixel=0,Visible=false});self.frame=frame
 local viewport=make("ViewportFrame",frame,{Name="EditorViewport",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(52,66,44),BorderSizePixel=0,Ambient=Color3.fromRGB(170,180,190),LightColor=Color3.fromRGB(255,239,210),LightDirection=Vector3.new(-1,-1,-1),Active=false});self.viewport=viewport
 local scale=make("Frame",viewport,{Name="TankScale",AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-10,1,-10),Size=UDim2.fromOffset(112,108),BackgroundColor3=panel,BackgroundTransparency=.12,BorderSizePixel=0});self.tankScaleCard=scale
 make("UICorner",scale,{CornerRadius=UDim.new(0,6)})
 self.tankScaleViewport=make("ViewportFrame",scale,{Name="TankPreview",Size=UDim2.new(1,0,1,-40),BackgroundTransparency=1,Ambient=Color3.fromRGB(170,180,190),LightDirection=Vector3.new(-1,-1,-1)})
 local scaleLabel=text(scale,"Label","Tank Scale",22);scaleLabel.Position=UDim2.new(0,4,1,-40);scaleLabel.TextXAlignment=Enum.TextXAlignment.Center
 self.tankScaleSize=text(scale,"FootprintSize","",16)
 self.tankScaleSize.Position=UDim2.new(0,4,1,-21);self.tankScaleSize.TextXAlignment=Enum.TextXAlignment.Center;self.tankScaleSize.TextSize=11
 local toolbar=make("Frame",frame,{Name="Toolbar",Size=UDim2.new(1,0,0,54),ZIndex=6,BackgroundColor3=Color3.fromRGB(33,39,25),BorderSizePixel=0,Active=true});self.toolbar=toolbar
 self.back=button(toolbar,"MainMenu","← Main Menu",UDim2.fromOffset(120,38),UDim2.fromOffset(8,8));self.buttons={self.back}
 self:on(self.back.Activated,function() if self.requestHome then self.requestHome() else context.home() end end)
 self.tools={}
 for index,name in {"Move","Rotate","Scale"} do
  self.tools[name]=button(toolbar,name,name,UDim2.fromOffset(60,32),UDim2.fromOffset(224+(index-1)*64,12))
 end
 self.delete=button(toolbar,"Delete","Delete",UDim2.fromOffset(60,32),UDim2.fromOffset(488,12));self.delete.BackgroundColor3=Color3.fromRGB(139,57,49)
 self.undo=button(toolbar,"Undo","Undo",UDim2.fromOffset(44,32),UDim2.fromOffset(736,12));self.undo.TextSize=11
 self.redo=button(toolbar,"Redo","Redo",UDim2.fromOffset(44,32),UDim2.fromOffset(788,12));self.redo.TextSize=11
 self.export=button(toolbar,"Export","Export JSON",UDim2.fromOffset(114,32),UDim2.new(1,-126,0,12));self.export.BackgroundColor3=Color3.fromRGB(121,89,37)
 local pane=make("Frame",frame,{Name="AssetCatalog",BackgroundColor3=panel,BorderSizePixel=0,Active=true});self.palette=pane
 self.search=make("TextBox",pane,{Name="SearchAssets",Position=UDim2.fromOffset(3,3),Size=UDim2.new(1,-6,0,26),Text="",PlaceholderText="Search assets…",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Gotham,TextSize=12})
 self.assetScroll=scrolling(pane,"AssetTree",UDim2.new(1,0,1,-32),UDim2.fromOffset(0,32))
 self.assetScroll.ScrollingDirection=Enum.ScrollingDirection.Y
 self.assetScroll.AutomaticCanvasSize=Enum.AutomaticSize.None
 make("UIListLayout",self.assetScroll,{Padding=UDim.new(0,2),SortOrder=Enum.SortOrder.LayoutOrder})
 self.properties=scrolling(frame,"ObjectProperties",UDim2.new(0,310,.52,-106),UDim2.new(1,-322,.48,44))
 make("UIPadding",self.properties,{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12),PaddingTop=UDim.new(0,8),PaddingBottom=UDim.new(0,10)})
 make("UIListLayout",self.properties,{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
 local order=0
 local function row(p) order+=1;p.LayoutOrder=order;return p end
 self.dimensionRows={row(text(self.properties,"WorldTitle","WORLD SIZE",24))}
 self.dimensions={}
 for _,axis in {"width","depth"} do
  table.insert(self.dimensionRows,row(text(self.properties,axis.."Label",if axis=="width" then "Width (studs)" else "Depth (studs)",20)))
  self.dimensions[axis]=row(make("TextBox",self.properties,{Name=axis,Size=UDim2.new(1,-8,0,28),Text="",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14}))
  table.insert(self.dimensionRows,self.dimensions[axis])
 end
 self.cameraSensitivity=row(make("TextBox",self.properties,{Name="CameraSensitivity",Size=UDim2.new(1,-8,0,28),Text="1",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14}))
 self.selected=row(text(self.properties,"SelectedObject","Select a placed object to inspect it.",46));self.selected.Size=UDim2.new(1,-8,0,0);self.selected.AutomaticSize=Enum.AutomaticSize.Y
 for _,spec in {{"x","Position X"},{"y","Height Y (lowest point)"},{"z","Position Z"},{"pitch","Tilt X / pitch (degrees)"},{"yaw","Yaw Y (degrees)"},{"roll","Tilt Z / roll (degrees)"},{"scale","Uniform scale"},{"sizeX","Local width (studs)"},{"sizeY","Local height (studs)"},{"sizeZ","Local length (studs)"},{"hp","Durability / HP"}} do
  self.fieldLabels[spec[1]]=row(text(self.properties,spec[1].."Label",spec[2],20))
  self.fields[spec[1]]=row(make("TextBox",self.properties,{Name=spec[1],Size=UDim2.new(1,-8,0,28),Text="",PlaceholderText="—",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=Color3.fromRGB(62,73,46),TextSize=14,Font=Enum.Font.Code}))
 end
 self.solid=row(button(self.properties,"Collision","Collision: —"));self.destructible=row(button(self.properties,"Destructible","Destructible: —"))
 self.regenerates=row(button(self.properties,"Regenerates","Regenerates: On"))
 self.regenerationLabel=row(text(self.properties,"RegenerationLabel","Regeneration delay (seconds)",20))
 self.regenerationDelay=row(make("TextBox",self.properties,{Name="RegenerationDelay",Size=UDim2.new(1,-8,0,28),Text="5",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14}))
 self.assetTractionLabel=row(text(self.properties,"AssetTractionLabel","Traction (% of pavement)",20))
 self.assetTraction=row(make("TextBox",self.properties,{Name="AssetTraction",Size=UDim2.new(1,-8,0,28),Text="",PlaceholderText="Use material default",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14}))
 self.soundButtons={}
 for _,spec in {{"effect","Choose Sound Effect"},{"preview","Preview Sound"},{"follow","Follow collision: Off"},{"paint","Repaint Sound Trail"},{"activation","Activation"},{"playback","Playback"},{"rollOff","RollOff"},{"filter","Trigger Filter"},{"origin","Sound Origin"},{"targets","Select Trigger Assets"},{"attach","Snap & Lock to Asset"}} do
  self.soundButtons[spec[1]]=row(button(self.properties,"Sfx_"..spec[1],spec[2]))
 end
 self.soundFields={}
 for _,spec in {{"interval","Repeat interval (sec)"},{"cooldown","Cooldown (sec)"},{"volume","Volume"},{"speed","Playback speed / pitch"},{"minDistance","Minimum audible distance"},{"maxDistance","Maximum audible distance"}} do
  local label=row(text(self.properties,"Sfx_"..spec[1].."Label",spec[2],20))
  local field=row(make("TextBox",self.properties,{Name="Sfx_"..spec[1],Size=UDim2.new(1,-8,0,28),Text="",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14}))
  self.soundFields[spec[1]]={label=label,field=field}
 end
 self.spinToggle=row(button(self.properties,"AssetSpin","Add automatic rotation"))
 self.spinSpace=row(button(self.properties,"SpinSpace","Axis space: Local"))
 self.spinMode=row(button(self.properties,"SpinMode","Rotation mode: Continuous"))
 self.spinFields={}
 for _,spec in {{"x","Rotation axis X (−1 to 1)"},{"y","Rotation axis Y (−1 to 1)"},{"z","Rotation axis Z (−1 to 1)"},{"speed","Rotation speed (degrees/sec)"},{"swing","Swing angle (degrees)"},{"pause","Pause at each end (seconds)"}} do
  local label=row(text(self.properties,"Spin"..spec[1].."Label",spec[2],20))
  local field=row(make("TextBox",self.properties,{Name="Spin"..spec[1],Size=UDim2.new(1,-8,0,28),Text="",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14}))
  self.spinFields[spec[1]]={label=label,field=field}
 end
 self.motionDraw=row(button(self.properties,"MotionDraw","Draw Motion Path"))
 self.motionPreview=row(button(self.properties,"MotionPreview","Preview Motion"))
 self.motionRemove=row(button(self.properties,"MotionRemove","Remove Motion Path"))
 self.motionPoint=row(button(self.properties,"MotionPoint","Remove Selected Waypoint"))
 self.waypointFields={}
 for axis,caption in {"Waypoint X","Waypoint elevation","Waypoint Z"} do
  local label=row(text(self.properties,"WaypointLabel"..axis,caption.." (studs)",20))
  local field=row(make("TextBox",self.properties,{Name="WaypointAxis"..axis,Size=UDim2.new(1,-8,0,28),Text="",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14}))
  self.waypointFields[axis]={label=label,field=field}
 end
 self.motionFace=row(button(self.properties,"MotionFace","Maintain orientation"))
 self.motionEnable=row(button(self.properties,"MotionEnable","Motion enabled"))
 self.motionFields={}
 for _,spec in {{"speed","Motion speed (studs/sec)"},{"pause","Endpoint pause (seconds)"}} do
  local label=row(text(self.properties,spec[1].."Label",spec[2],20))
  local field=row(make("TextBox",self.properties,{Name=spec[1],Size=UDim2.new(1,-8,0,28),Text="",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14}))
  self.motionFields[spec[1]]={label=label,field=field}
 end
 self.influences=row(text(self.properties,"Influences","Fixed objects • height / tilt • uniform scale",100))
 self.duplicate=row(button(self.properties,"Duplicate","Duplicate  •  Ctrl+D"))
 self.copyScale=row(button(self.properties,"CopyScale","Copy scale"))
 self.pasteScale=row(button(self.properties,"PasteScale","Apply copied scale"))
 local controls=make("Frame",frame,{Name="EditorOptions",Position=UDim2.fromOffset(12,66),Size=UDim2.fromOffset(208,76),BackgroundColor3=Color3.fromRGB(43,51,33),Active=true,BorderSizePixel=0});self.options=controls
 self.snap=button(controls,"GridSnap","Grid snap: OFF",UDim2.fromOffset(132,28),UDim2.fromOffset(8,8))
 self.grid=make("TextBox",controls,{Name="GridSize",Text="1",ClearTextOnFocus=false,Size=UDim2.fromOffset(48,28),Position=UDim2.fromOffset(150,8),BackgroundColor3=Color3.fromRGB(62,73,46),TextColor3=ink,TextSize=14,Font=Enum.Font.Code})
 self.frameWorld=button(controls,"FrameWorld","Frame world  •  F",UDim2.fromOffset(190,26),UDim2.fromOffset(8,42))
 self.worlds=button(frame,"SavedWorlds","My Worlds / Save & Play",UDim2.fromOffset(208,36),UDim2.fromOffset(12,150));self.worlds.BackgroundColor3=Color3.fromRGB(121,89,37)
 self.rotationAxes={}
 local rotations=make("Frame",frame,{Name="RotationAxes",Position=UDim2.fromOffset(12,194),Size=UDim2.fromOffset(208,64),BackgroundColor3=Color3.fromRGB(43,51,33),BorderSizePixel=0,Active=true});self.rotationPanel=rotations
 local axisTitle=text(rotations,"AxisTitle","LOCAL ROTATION AXIS",24);axisTitle.Position=UDim2.fromOffset(8,2)
 for index,axis in {"Pitch","Yaw","Roll"} do
  self.rotationAxes[axis]=button(rotations,axis,({Pitch="Tilt X",Yaw="Yaw Y",Roll="Tilt Z"})[axis],UDim2.fromOffset(60,28),UDim2.fromOffset(8+(index-1)*65,28))
 end
 local magnets=make("Frame",frame,{Name="EdgeSnapping",Position=UDim2.fromOffset(12,268),Size=UDim2.fromOffset(208,208),BackgroundColor3=Color3.fromRGB(43,51,33),BorderSizePixel=0,Active=true});self.magnets=magnets
 self.edgeSnap=button(magnets,"EdgeSnap","Edge snap: OFF",UDim2.fromOffset(192,28),UDim2.fromOffset(8,8))
 self.pinA=button(magnets,"PinA","Pin A here",UDim2.fromOffset(92,28),UDim2.fromOffset(8,42));self.pinA.TextColor3=Color3.fromRGB(80,215,255)
 self.pinB=button(magnets,"PinB","Pin B here",UDim2.fromOffset(92,28),UDim2.fromOffset(108,42));self.pinB.TextColor3=Color3.fromRGB(255,183,92)
 self.pinA.Visible=false;self.pinB.Visible=false
 self.releasePin=button(magnets,"ReleasePin","Clear contacts",UDim2.fromOffset(192,28),UDim2.fromOffset(8,76))
 self.pinStatus=text(magnets,"PinStatus","Enable snapping, select a board, then drag end A or B onto a top edge.",58);self.pinStatus.Position=UDim2.fromOffset(8,144);self.pinStatus.Size=UDim2.new(1,-16,0,58);self.pinStatus.TextSize=11
 self.pinStatus.Position=UDim2.fromOffset(8,110)
 magnets.Size=UDim2.fromOffset(208,174)
 self.placeStart=button(toolbar,"PlaceStartingPosition","Place start zone  •  0/5",UDim2.fromOffset(172,32),UDim2.fromOffset(556,12));self.placeStart.BackgroundColor3=Color3.fromRGB(121,89,37)
 self.sfxPicker=make("Frame",frame,{Name="SoundPicker",Size=UDim2.fromScale(.56,.67),Position=UDim2.fromScale(.22,.15),BackgroundColor3=panel,Visible=false,Active=true,ZIndex=25})
 self.sfxTitle=text(self.sfxPicker,"Title","Sound Effects",30);self.sfxTitle.ZIndex=26
 self.sfxSearch=make("TextBox",self.sfxPicker,{Name="Search",Size=UDim2.new(1,-108,0,32),Position=UDim2.fromOffset(8,35),Text="",PlaceholderText="Search by name or category",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,ZIndex=26})
 self.sfxClose=button(self.sfxPicker,"Close","Close",UDim2.fromOffset(86,32),UDim2.new(1,-94,0,35));self.sfxClose.ZIndex=26
 self.sfxList=scrolling(self.sfxPicker,"Choices",UDim2.new(1,-16,1,-82),UDim2.fromOffset(8,75));self.sfxList.ZIndex=26
 self.sfxList.AutomaticCanvasSize=Enum.AutomaticSize.Y
 make("UIListLayout",self.sfxList,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,3)})
 self.sfxConnections={}
 self.status=text(frame,"EditorStatus","Loading native asset library…",30);self.status.Position=UDim2.new(0,12,1,-72);self.status.Size=UDim2.new(1,-344,0,30);self.status.BackgroundTransparency=.1;self.status.BackgroundColor3=Color3.fromRGB(33,39,25)
 self.finishPaint=button(frame,"FinishPaint","Finish Painting",UDim2.fromOffset(132,24),UDim2.new(1,-140,1,-46))
 self.finishPaint.Visible=false
 self.paintBucket=button(frame,"PaintBucket","Paint Bucket",UDim2.fromOffset(132,24),UDim2.new(1,-140,1,-46))
 self.paintBucket.Visible=false
 self.hint=text(frame,"EditorHints","RMB orbit • MMB pan • WASD move • E/Q height while dragging • Wheel zoom • F reset",30);self.hint.Position=UDim2.new(0,12,1,-36);self.hint.Size=UDim2.new(1,-344,0,30)
 local overlay=make("Frame",frame,{Name="ExportOverlay",Position=UDim2.fromScale(.08,.12),Size=UDim2.fromScale(.84,.76),BackgroundColor3=Color3.fromRGB(30,36,24),Visible=false,Active=true,ZIndex=10});self.overlay=overlay
 local exportTitle=text(overlay,"ExportTitle","WORLD JSON  /  export or paste a backup to import",32);exportTitle.Position=UDim2.fromOffset(16,8);exportTitle.ZIndex=11
 self.name=make("TextBox",overlay,{Name="WorldName",Text="My BattleWorks World",PlaceholderText="World name",ClearTextOnFocus=false,Position=UDim2.fromOffset(16,48),Size=UDim2.new(.5,-24,0,30),TextColor3=ink,BackgroundColor3=Color3.fromRGB(62,73,46),Font=Enum.Font.Gotham,TextSize=14,ZIndex=11})
 self.worldId=make("TextBox",overlay,{Name="WorldId",Text="ingame_world",PlaceholderText="World ID",ClearTextOnFocus=false,Position=UDim2.new(.5,8,0,48),Size=UDim2.new(.5,-24,0,30),TextColor3=ink,BackgroundColor3=Color3.fromRGB(62,73,46),Font=Enum.Font.Code,TextSize=14,ZIndex=11})
 self.json=make("TextBox",overlay,{Name="ExportJSON",Position=UDim2.fromOffset(16,124),Size=UDim2.new(1,-32,1,-172),Text="",ClearTextOnFocus=false,MultiLine=true,TextEditable=true,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextColor3=ink,BackgroundColor3=Color3.fromRGB(45,54,34),Font=Enum.Font.Code,TextSize=12,ZIndex=11})
 self.generate=button(overlay,"GenerateJSON","Generate / Select JSON",UDim2.fromOffset(208,30),UDim2.fromOffset(16,86));self.generate.ZIndex=11
 self.import=button(overlay,"ImportJSON","Import JSON (replaces draft)",UDim2.fromOffset(226,30),UDim2.fromOffset(232,86));self.import.ZIndex=11
 self.closeExport=button(overlay,"CloseExport","Close",UDim2.fromOffset(72,30),UDim2.new(1,-88,1,-38));self.closeExport.ZIndex=11
 self.closeExport.Activated:Connect(function() overlay.Visible=false end)
 self.newWorld=button(toolbar,"NewWorld","New World")
 self.openWorld=button(toolbar,"OpenWorld","Open World")
 self.saveWorld=button(toolbar,"SaveWorld","Save")
 self.saveAs=button(toolbar,"SaveWorldAs","Save As")
 self.inspect=button(toolbar,"Inspector","Toggle Inspector")
 self.assets=button(toolbar,"Assets","Add Asset")
 self.soundVisibility=button(toolbar,"SoundVisibility","Hide Audio")
 self.terrain=button(toolbar,"TerrainMode","Terrain")
 self.openPlayground=button(toolbar,"OpenPlayground","Open Playground");self.openPlayground.Visible=context.royale==true
 self.tools.Select=button(toolbar,"Select","Select / Navigate")
 self.tools.Resize=button(toolbar,"Resize","Resize")
 self.terrainTools={}
 for _,name in {"Raise","Lower","Smooth","Flatten"} do
  self.terrainTools[name]=button(toolbar,"Terrain"..name,name)
 end
 self.repeatPlacement=button(pane,"RepeatPlacement","Repeat: Off")
 self.recentAssets=button(pane,"RecentAssets","Recent Assets")
 self.frameWorld.Text="Frame world  •  Home"
 self.brushPanel=scrolling(frame,"BrushSettings",UDim2.fromOffset(0,0),UDim2.fromOffset(0,0))
 make("UIPadding",self.brushPanel,{PaddingLeft=UDim.new(0,10),PaddingTop=UDim.new(0,8)})
 make("UIListLayout",self.brushPanel,{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
 self.brushFields={};self.brushLabels={}
 self.paintEntireWorld=button(self.brushPanel,"PaintEntireWorld","[ ] Paint entire world",UDim2.new(1,-14,0,28))
 self.paintEntireWorld.LayoutOrder=1;self.paintEntireWorld.Visible=false
 self.brushTractionLabel=text(self.brushPanel,"BrushTractionLabel","Brush traction (% of pavement)",24)
 self.brushTractionLabel.LayoutOrder=2;self.brushTractionLabel.Visible=false
 self.brushTraction=make("TextBox",self.brushPanel,{Name="BrushTraction",LayoutOrder=3,Size=UDim2.new(1,-14,0,28),
  Text="",PlaceholderText="Use material fallback",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14,Visible=false})
 self.tractionLabel=text(self.brushPanel,"TractionLabel","",24)
 self.tractionLabel.LayoutOrder=4;self.tractionLabel.Visible=false
 self.useWorldTraction=button(self.brushPanel,"UseWorldDefault","Use World Default",UDim2.new(1,-14,0,28))
 self.useWorldTraction.LayoutOrder=5;self.useWorldTraction.Visible=false
 for i,spec in {{"radius","Brush Size (studs)",26},{"strength","Heaviness",24},{"falloff","Steepness (0–1)",.65},{"elevation","Flatten elevation (studs)",0},{"depth","Water / ravine depth (studs)",4}} do
  local label=text(self.brushPanel,spec[1].."Label",spec[2],22);label.LayoutOrder=i*2+4
  self.brushLabels[spec[1]]=label
  self.brushFields[spec[1]]=make("TextBox",self.brushPanel,{Name=spec[1],LayoutOrder=i*2+5,Size=UDim2.new(1,-14,0,28),
   Text=tostring(spec[3]),ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14})
 end
 self.tunnelFields={}
 self.tunnelLabels={}
 for i,spec in {{"diameter","Inside diameter (studs)"},{"traction","Tunnel traction (% of pavement)"},{"start","Start elevation (studs)"},{"finish","End elevation (studs)"}} do
  local label=text(self.brushPanel,"Tunnel"..spec[1].."Label",spec[2],22)
  label.LayoutOrder=15+i*2;label.Visible=false
  self.tunnelLabels[spec[1]]=label
  self.tunnelFields[spec[1]]=make("TextBox",self.brushPanel,{Name="Tunnel"..spec[1],LayoutOrder=16+i*2,Size=UDim2.new(1,-14,0,28),Text="",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14,Visible=false})
 end
 self.tunnelNew=button(self.brushPanel,"NewTunnel","Draw new tunnel")
 self.tunnelNext=button(self.brushPanel,"NextTunnel","Select next tunnel")
 self.tunnelDelete=button(self.brushPanel,"DeleteTunnel","Delete selected tunnel")
 for i,b in {self.tunnelNew,self.tunnelNext,self.tunnelDelete} do b.LayoutOrder=25+i;b.Visible=false end
 self.traversability=button(self.brushPanel,"TerrainTraversability","Terrain Traversability")
 self.traversability.LayoutOrder=14;self.traversability.Size=UDim2.new(1,-14,0,34)
 self.traversalLegend=text(self.brushPanel,"TraversalLegend","No tint · Both drivetrains\nYellow · Requires treads\nRed · Too steep or too deep",84)
 self.traversalLegend.LayoutOrder=15;self.traversalLegend.Visible=false
 self.surfaceTools={}
 for _,name in {"Grass","Mud","Ice","Snow","Pavement","Water","Carve Ravine","Tunnel"} do
  self.surfaceTools[name]=button(toolbar,"Brush"..name,name)
 end
 self.hint.Text="Wheel zoom · MMB pan · RMB orbit · WASD / Q E fly · Shift boost · F focus · Home frame"
 Presentation.install(self,context,{make=make,button=button,text=text,scrolling=scrolling})
 -- Containers from the previous layout can go after their controls are reparented.
 self.properties:Destroy()
 self.properties=self.inspector
 self.options:Destroy()
 self.rotationPanel:Destroy()
 self.pinStatus.Parent=self.frame;self.pinStatus.Visible=false
 self.magnets:Destroy()
 return self
end
function View:showTerrainPreferences(brush)
 for _,group in {self.terrainTools,self.surfaceTools} do
  for name,control in group do
   Skin.select(control,name==brush.operation)
   Skin.remember(control,name==brush.material or name==brush.sculpt)
  end
 end
end
function View:on(event,callback) table.insert(self.connections,event:Connect(callback)) end
function View:message(message, invalid)
 local caption=tostring(message):gsub("^.-:%d+:%s*","")
 if self.status.Text~=caption then
  self.status.Text=caption
  self.status.Parent.CanvasPosition=Vector2.zero
 end
 self.status.TextColor3=if invalid then Skin.error else Skin.ink
end
function View:isModal() return self.sfxPicker.Visible or self.overlay.Visible or (self.library and self.library.frame.Visible) end
function View:isScene(point)
 return self.frame.Visible and not self:isModal() and rectContains(self.viewport,point) and not (self.left.Visible and rectContains(self.left,point))
  and not (self.terrainMaterialBar.Visible and rectContains(self.terrainMaterialBar,point))
end
function View:thumbnail(parent,item,assets)
 local templates=assets and assets:FindFirstChild("Templates")
 if not templates or not item.available then return end
 local viewport=make("ViewportFrame",parent,{Name="AssetPreview",Position=UDim2.fromOffset(4,4),Size=UDim2.new(1,-8,0,78),BackgroundColor3=if Document.canSetAssetTraction(item) then collisionTile else Color3.fromRGB(50,68,72),BorderSizePixel=0,Ambient=Color3.fromRGB(190,190,190),LightColor=Color3.fromRGB(255,235,210),Active=false})
 local world=Instance.new("Folder");world.Parent=viewport
 local model=Placement.place(templates,{id="thumbnail",template=item.model,position=Vector3.zero,rotation=Vector3.zero,scale=1},nil,world)
 if model then
  local box,size=model:GetBoundingBox();local radius=math.max(size.X,size.Y,size.Z,1)
  local camera=Instance.new("Camera");camera.FieldOfView=38;camera.CFrame=CFrame.lookAt(box.Position+Vector3.new(radius*.9,radius*.55,radius),box.Position);camera.Parent=viewport;viewport.CurrentCamera=camera
 end
 table.insert(self.thumbnails,viewport)
end
function View:paletteEntries(entries,selected,onFolder,onAsset,onDrag)
 for _,connection in self.paletteConnections do connection:Disconnect() end
 table.clear(self.paletteConnections)
 for _,child in self.assetScroll:GetChildren() do
  if child:IsA("GuiObject") then child:Destroy() end
 end
 self.assetRows={}
 for index,entry in ipairs(entries) do
  local item=entry.item
  local caption=if item then (if item.available then "" else "[Missing] ")..item.name else entry.name
  local tile=button(self.assetScroll,entry.path,caption,UDim2.new(1,-6,0,23))
  Skin.catalogRow(tile,entry.depth,entry.open,item~=nil,item and item.available)
  tile.LayoutOrder=index
  if item then
   self.assetRows[item.model]=tile
   Skin.highlightRow(tile,item.model==selected)
   table.insert(self.paletteConnections,tile.Activated:Connect(function() onAsset(item) end))
   table.insert(self.paletteConnections,tile.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then onDrag(item) end
   end))
  else
   table.insert(self.paletteConnections,tile.Activated:Connect(function() onFolder(entry.path) end))
  end
 end
 self.assetScroll.CanvasSize=UDim2.fromOffset(0,#entries*25)
end
function View:highlightCatalogAsset(path)
 for model,row in self.assetRows or {} do
  Skin.highlightRow(row,model==path)
 end
end
function View:soundChoices(rows,choose,preview)
 for _,connection in self.sfxConnections do connection:Disconnect() end
 self.sfxConnections={}
 for _,child in self.sfxList:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
 for i,item in rows do
  local row=make("Frame",self.sfxList,{Size=UDim2.new(1,-8,0,34),BackgroundTransparency=1,LayoutOrder=i,ZIndex=27})
  local select=button(row,"Choose",item.name,UDim2.new(1,if preview and item.assetId then -84 else 0,1,0));select.ZIndex=28
  table.insert(self.sfxConnections,select.Activated:Connect(function() choose(item) end))
  if preview and item.assetId then
   local play=button(row,"Preview","Preview",UDim2.fromOffset(78,34),UDim2.new(1,-78,0,0));play.ZIndex=28
   table.insert(self.sfxConnections,play.Activated:Connect(function() preview(item) end))
  end
 end
end
function View:selection(entry,item)
 local focused=game:GetService("UserInputService"):GetFocusedTextBox()
 local tractionVisible=entry~=nil and Document.canSetAssetTraction(item)
 self.assetTractionLabel.Visible=tractionVisible;self.assetTraction.Visible=tractionVisible
 if tractionVisible and focused~=self.assetTraction then
  self.assetTraction.Text=if entry.traction~=nil then tostring(entry.traction) else ""
 end
 local destructible=entry~=nil and entry.destructible==true
 local enabled=destructible and entry.regenerates~=false
 self.regenerates.Visible=destructible
 self.regenerates.Text=if enabled then "Regenerates: On" else "Regenerates: Off"
 self.regenerationDelay.Visible=destructible;self.regenerationLabel.Visible=destructible
 self.regenerationDelay.TextEditable=enabled
 if destructible and focused~=self.regenerationDelay then self.regenerationDelay.Text=tostring(entry.regenerationDelay or Document.DefaultRegenerationDelay) end
 if entry and entry.slot then
  self.selected.Text="PLAYER "..entry.slot.." STARTING AREA\nRoom for three tanks"
  for key,field in self.fields do
   local n=({x=entry.position[1],z=entry.position[3],yaw=entry.heading})[key]
   if focused~=field then
    self.displayedFields[key]=if n then tostring(n) else ""
    field.Text=self.displayedFields[key]
   end
   field.TextEditable=n~=nil
  end
  self.solid.Text="Ground marking • no collision";self.destructible.Text="Starting areas cannot be destroyed"
  self.influences.Text="Move on the ground or set X/Z. Yaw sets starting direction. Delete to relocate this numbered area. All five are required to play."
  return
 end
 for _,field in self.fields do field.TextEditable=true end
 self.selected.Text=if entry then entry.id.."\n"..entry.asset else "Select a placed object to inspect it."
 local values=if entry then {x=entry.position[1],y=entry.position[2],z=entry.position[3],pitch=entry.rotation[1],yaw=entry.rotation[2],roll=entry.rotation[3],scale=entry.scale,hp=entry.hp} else {}
 for axis,key in {"sizeX","sizeY","sizeZ"} do
  local field=self.fields[key]
  field.TextEditable=entry~=nil and Document.canResize(item,axis)
  if entry then values[key]=entry.bounds[axis]*entry.scale*(entry.stretch and entry.stretch[axis] or 1) end
 end
 for key,field in self.fields do
  if focused~=field then
   self.displayedFields[key]=if values[key] then string.format("%.5g",values[key]) else ""
   field.Text=self.displayedFields[key]
  end
 end
 self.solid.Text=if entry and entry.sound then "Audio trigger • no collision" else "Collision: "..(if entry then (if entry.solid then "SOLID" else "NONE") else "—")
 self.destructible.Text="Destructible: "..(if entry then (if entry.destructible then "YES" else "NO") else "—")
 self.influences.Text=if entry then "Physical movability: Fixed (read-only)\n"..(if item.zone then item.zone.." zone: "..(if item.zone=="Water" then "90%" else "75%").." speed\n" else "")..(if item.collider then string.format("Collider W %.3g / D %.3g / H %.3g",item.collider.widthFraction,item.collider.depthFraction,item.collider.heightFraction) else "No registered collider; visual only") else "Fixed objects • height / tilt • uniform scale"
end
function View:destroy()
 Skin.release(self)
 for _,connection in self.connections do connection:Disconnect() end
 for _,connection in self.paletteConnections do connection:Disconnect() end
 self.frame:Destroy()
end
return View
