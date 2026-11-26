-- Editor UI only. Picking, transactions and world geometry live elsewhere.
local Placement=require(game.ReplicatedStorage.Shared.ModelPlacement)
local Paths=require(game.ReplicatedStorage.Shared.AssetPaths)
local Document=require(game.ReplicatedStorage.Shared.WorldEditorDocument)
local View={};View.__index=View
local ink=Color3.fromRGB(235,241,230)
local accent=Color3.fromRGB(174,135,255)
local panel=Color3.fromRGB(29,28,39)
local collisionTile=Color3.fromRGB(41,70,53)
View.buttonColor=Color3.fromRGB(46,44,62)
View.activeColor=Color3.fromRGB(92,65,145)
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
 local self=setmetatable({connections={},paletteConnections={},thumbnails={},fields={},callbacks={},buttons={}},View)
 local frame=make("Frame",context.parent,{Name="World Editor",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(17,28,33),BorderSizePixel=0,Visible=false});self.frame=frame
 local viewport=make("ViewportFrame",frame,{Name="EditorViewport",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(37,58,66),BorderSizePixel=0,Ambient=Color3.fromRGB(170,180,190),LightColor=Color3.fromRGB(255,239,210),LightDirection=Vector3.new(-1,-1,-1),Active=false});self.viewport=viewport
 local scale=make("Frame",viewport,{Name="TankScale",AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-10,1,-10),Size=UDim2.fromOffset(112,108),BackgroundColor3=panel,BackgroundTransparency=.12,BorderSizePixel=0});self.tankScaleCard=scale
 make("UICorner",scale,{CornerRadius=UDim.new(0,6)})
 self.tankScaleViewport=make("ViewportFrame",scale,{Name="TankPreview",Size=UDim2.new(1,0,1,-40),BackgroundTransparency=1,Ambient=Color3.fromRGB(170,180,190),LightDirection=Vector3.new(-1,-1,-1)})
 local scaleLabel=text(scale,"Label","Tank Scale",22);scaleLabel.Position=UDim2.new(0,4,1,-40);scaleLabel.TextXAlignment=Enum.TextXAlignment.Center
 self.tankScaleSize=text(scale,"FootprintSize","",16)
 self.tankScaleSize.Position=UDim2.new(0,4,1,-21);self.tankScaleSize.TextXAlignment=Enum.TextXAlignment.Center;self.tankScaleSize.TextSize=11
 local toolbar=make("Frame",frame,{Name="Toolbar",Size=UDim2.new(1,0,0,54),BackgroundColor3=Color3.fromRGB(19,30,35),BorderSizePixel=0,Active=true});self.toolbar=toolbar
 self.back=button(toolbar,"MainMenu","← Main Menu",UDim2.fromOffset(120,38),UDim2.fromOffset(8,8));self.buttons={self.back}
 self.back.Activated:Connect(context.home)
 local title=text(toolbar,"EditorTitle","BUILDER",32);title.Position=UDim2.fromOffset(144,12);title.Size=UDim2.fromOffset(76,32);title.TextSize=16;title.TextColor3=accent
 self.tools={}
 for index,name in {"Move","Rotate","Scale","Snap"} do
  self.tools[name]=button(toolbar,name,name,UDim2.fromOffset(60,32),UDim2.fromOffset(224+(index-1)*64,12))
 end
 self.delete=button(toolbar,"Delete","Delete",UDim2.fromOffset(60,32),UDim2.fromOffset(488,12));self.delete.BackgroundColor3=Color3.fromRGB(139,57,49)
 self.undo=button(toolbar,"Undo","Undo",UDim2.fromOffset(44,32),UDim2.fromOffset(736,12));self.undo.TextSize=11
 self.redo=button(toolbar,"Redo","Redo",UDim2.fromOffset(44,32),UDim2.fromOffset(788,12));self.redo.TextSize=11
 self.export=button(toolbar,"Export","Export JSON",UDim2.fromOffset(114,32),UDim2.new(1,-126,0,12));self.export.BackgroundColor3=Color3.fromRGB(121,89,37)
 local pane=make("Frame",frame,{Name="AssetPalette",AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,66),Size=UDim2.new(0,310,.48,-32),BackgroundColor3=Color3.fromRGB(23,35,39),BorderSizePixel=0,Active=true});self.palette=pane
 local label=text(pane,"PaletteTitle","ASSET LIBRARY  •  drag into the world",28);label.Position=UDim2.fromOffset(12,6)
 self.up=button(pane,"ParentDirectory","↑",UDim2.fromOffset(32,28),UDim2.fromOffset(10,38))
 self.breadcrumb=text(pane,"AssetDirectory","Assets /",28);self.breadcrumb.Position=UDim2.fromOffset(50,38);self.breadcrumb.Size=UDim2.new(1,-60,0,28)
 self.search=make("TextBox",pane,{Name="SearchAssets",Position=UDim2.fromOffset(10,72),Size=UDim2.new(1,-20,0,30),Text="",PlaceholderText="Search asset names or full paths…",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=Color3.fromRGB(43,61,66),Font=Enum.Font.Gotham,TextSize=13})
 self.assetScroll=scrolling(pane,"AssetTiles",UDim2.new(1,-20,1,-142),UDim2.fromOffset(10,108))
 local grid=make("UIGridLayout",self.assetScroll,{CellSize=UDim2.new(.5,-5,0,116),CellPadding=UDim2.fromOffset(6,6),SortOrder=Enum.SortOrder.LayoutOrder})
 self.page=text(pane,"Page","",24);self.page.Position=UDim2.new(0,10,1,-28);self.page.Size=UDim2.new(1,-90,0,24)
 self.nextPage=button(pane,"NextAssets","Next →",UDim2.fromOffset(72,24),UDim2.new(1,-82,1,-28))
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
 row(text(self.properties,"CameraSensitivityLabel","Camera sensitivity",20))
 self.cameraSensitivity=row(make("TextBox",self.properties,{Name="CameraSensitivity",Size=UDim2.new(1,-8,0,28),Text="1",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14}))
 row(text(self.properties,"PropertiesTitle","OBJECT PROPERTIES",24))
 self.selected=row(text(self.properties,"SelectedObject","Select a placed object to inspect it.",46));self.selected.Size=UDim2.new(1,-8,0,0);self.selected.AutomaticSize=Enum.AutomaticSize.Y
 for _,spec in {{"x","Position X"},{"y","Height Y (lowest point)"},{"z","Position Z"},{"pitch","Tilt X / pitch (degrees)"},{"yaw","Yaw Y (degrees)"},{"roll","Tilt Z / roll (degrees)"},{"scale","Uniform scale"},{"sizeX","Local width (studs)"},{"sizeY","Local height (studs)"},{"sizeZ","Local length (studs)"},{"hp","Durability / HP"}} do
  row(text(self.properties,spec[1].."Label",spec[2],20))
  self.fields[spec[1]]=row(make("TextBox",self.properties,{Name=spec[1],Size=UDim2.new(1,-8,0,28),Text="",PlaceholderText="—",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=Color3.fromRGB(43,61,66),TextSize=14,Font=Enum.Font.Code}))
 end
 self.solid=row(button(self.properties,"Collision","Collision: —"));self.destructible=row(button(self.properties,"Destructible","Destructible: —"))
 self.regenerates=row(button(self.properties,"Regenerates","☑ Regenerates"))
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
 local controls=make("Frame",frame,{Name="EditorOptions",Position=UDim2.fromOffset(12,66),Size=UDim2.fromOffset(208,76),BackgroundColor3=Color3.fromRGB(23,35,39),Active=true,BorderSizePixel=0});self.options=controls
 self.snap=button(controls,"GridSnap","Grid snap: OFF",UDim2.fromOffset(132,28),UDim2.fromOffset(8,8))
 self.grid=make("TextBox",controls,{Name="GridSize",Text="1",ClearTextOnFocus=false,Size=UDim2.fromOffset(48,28),Position=UDim2.fromOffset(150,8),BackgroundColor3=Color3.fromRGB(43,61,66),TextColor3=ink,TextSize=14,Font=Enum.Font.Code})
 self.frameWorld=button(controls,"FrameWorld","Frame world  •  F",UDim2.fromOffset(190,26),UDim2.fromOffset(8,42))
 self.worlds=button(frame,"SavedWorlds","My Worlds / Save & Play",UDim2.fromOffset(208,36),UDim2.fromOffset(12,150));self.worlds.BackgroundColor3=Color3.fromRGB(121,89,37)
 self.rotationAxes={}
 local rotations=make("Frame",frame,{Name="RotationAxes",Position=UDim2.fromOffset(12,194),Size=UDim2.fromOffset(208,64),BackgroundColor3=Color3.fromRGB(23,35,39),BorderSizePixel=0,Active=true});self.rotationPanel=rotations
 local axisTitle=text(rotations,"AxisTitle","LOCAL ROTATION AXIS",24);axisTitle.Position=UDim2.fromOffset(8,2)
 for index,axis in {"Pitch","Yaw","Roll"} do
  self.rotationAxes[axis]=button(rotations,axis,({Pitch="Tilt X",Yaw="Yaw Y",Roll="Tilt Z"})[axis],UDim2.fromOffset(60,28),UDim2.fromOffset(8+(index-1)*65,28))
 end
 local magnets=make("Frame",frame,{Name="EdgeSnapping",Position=UDim2.fromOffset(12,268),Size=UDim2.fromOffset(208,208),BackgroundColor3=Color3.fromRGB(23,35,39),BorderSizePixel=0,Active=true});self.magnets=magnets
 self.edgeSnap=button(magnets,"EdgeSnap","Edge snap: OFF",UDim2.fromOffset(192,28),UDim2.fromOffset(8,8))
 self.pinA=button(magnets,"PinA","Pin A here",UDim2.fromOffset(92,28),UDim2.fromOffset(8,42));self.pinA.TextColor3=Color3.fromRGB(80,215,255)
 self.pinB=button(magnets,"PinB","Pin B here",UDim2.fromOffset(92,28),UDim2.fromOffset(108,42));self.pinB.TextColor3=Color3.fromRGB(255,183,92)
 self.pinA.Visible=false;self.pinB.Visible=false
 self.releasePin=button(magnets,"ReleasePin","Clear contacts",UDim2.fromOffset(192,28),UDim2.fromOffset(8,76))
 self.snapContact=button(magnets,"SnapContactMode","Contact: edge center",UDim2.fromOffset(192,28),UDim2.fromOffset(8,110))
 self.pinStatus=text(magnets,"PinStatus","Enable snapping, select a board, then drag end A or B onto a top edge.",58);self.pinStatus.Position=UDim2.fromOffset(8,144);self.pinStatus.Size=UDim2.new(1,-16,0,58);self.pinStatus.TextSize=11
 self.snapContact.Position=UDim2.fromOffset(8,42)
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
 self.status=text(frame,"EditorStatus","Loading native asset library…",30);self.status.Position=UDim2.new(0,12,1,-72);self.status.Size=UDim2.new(1,-344,0,30);self.status.BackgroundTransparency=.1;self.status.BackgroundColor3=Color3.fromRGB(19,30,35)
 self.finishPaint=button(frame,"FinishPaint","Finish Painting",UDim2.fromOffset(132,24),UDim2.new(1,-140,1,-46))
 self.finishPaint.Visible=false
 self.paintBucket=button(frame,"PaintBucket","Paint Bucket",UDim2.fromOffset(132,24),UDim2.new(1,-140,1,-46))
 self.paintBucket.Visible=false
 self.hint=text(frame,"EditorHints","RMB orbit • MMB pan • WASD move • E/Q height while dragging • Wheel zoom • F reset",30);self.hint.Position=UDim2.new(0,12,1,-36);self.hint.Size=UDim2.new(1,-344,0,30)
 local overlay=make("Frame",frame,{Name="ExportOverlay",Position=UDim2.fromScale(.08,.12),Size=UDim2.fromScale(.84,.76),BackgroundColor3=Color3.fromRGB(17,28,33),Visible=false,Active=true,ZIndex=10});self.overlay=overlay
 local exportTitle=text(overlay,"ExportTitle","WORLD JSON  /  export or paste a backup to import",32);exportTitle.Position=UDim2.fromOffset(16,8);exportTitle.ZIndex=11
 self.name=make("TextBox",overlay,{Name="WorldName",Text="My BattleWorks World",PlaceholderText="World name",ClearTextOnFocus=false,Position=UDim2.fromOffset(16,48),Size=UDim2.new(.5,-24,0,30),TextColor3=ink,BackgroundColor3=Color3.fromRGB(43,61,66),Font=Enum.Font.Gotham,TextSize=14,ZIndex=11})
 self.worldId=make("TextBox",overlay,{Name="WorldId",Text="ingame_world",PlaceholderText="World ID",ClearTextOnFocus=false,Position=UDim2.new(.5,8,0,48),Size=UDim2.new(.5,-24,0,30),TextColor3=ink,BackgroundColor3=Color3.fromRGB(43,61,66),Font=Enum.Font.Code,TextSize=14,ZIndex=11})
 self.json=make("TextBox",overlay,{Name="ExportJSON",Position=UDim2.fromOffset(16,124),Size=UDim2.new(1,-32,1,-172),Text="",ClearTextOnFocus=false,MultiLine=true,TextEditable=true,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextColor3=ink,BackgroundColor3=Color3.fromRGB(27,40,46),Font=Enum.Font.Code,TextSize=12,ZIndex=11})
 self.generate=button(overlay,"GenerateJSON","Generate / Select JSON",UDim2.fromOffset(208,30),UDim2.fromOffset(16,86));self.generate.ZIndex=11
 self.import=button(overlay,"ImportJSON","Import JSON (replaces draft)",UDim2.fromOffset(226,30),UDim2.fromOffset(232,86));self.import.ZIndex=11
 self.closeExport=button(overlay,"CloseExport","Close",UDim2.fromOffset(72,30),UDim2.new(1,-88,1,-38));self.closeExport.ZIndex=11
 self.closeExport.Activated:Connect(function() overlay.Visible=false end)
 frame.BackgroundColor3=Color3.fromRGB(17,16,24)
 toolbar.BackgroundColor3=panel
 title.Text="WORLD EDITOR";title.Position=UDim2.fromOffset(14,0);title.Size=UDim2.fromOffset(220,26)
 local commands=scrolling(toolbar,"EditorCommands",UDim2.new(1,-16,0,36),UDim2.fromOffset(8,28))
 commands.AutomaticCanvasSize=Enum.AutomaticSize.X;commands.ScrollingDirection=Enum.ScrollingDirection.X
 make("UIListLayout",commands,{FillDirection=Enum.FillDirection.Horizontal,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,5)})
 self.newWorld=button(commands,"NewWorld","New World")
 self.openWorld=button(commands,"OpenWorld","Open")
 self.saveWorld=button(commands,"SaveWorld","Save")
 self.saveAs=button(commands,"SaveWorldAs","Save As")
 self.toolShelf=button(commands,"ToggleTools","Tools")
 self.inspect=button(commands,"Inspector","Inspector")
 self.assets=button(commands,"Assets","Object Library")
 self.soundVisibility=button(commands,"SoundVisibility","Hide Audio")
 self.terrain=button(commands,"TerrainMode","Terrain")
 self.openPlayground=button(frame,"OpenPlayground","Open Playground");self.openPlayground.Visible=context.royale==true
 for index,control in {self.back,self.newWorld,self.openWorld,self.openPlayground,self.saveWorld,self.saveAs,self.undo,self.redo,self.terrain,self.toolShelf,self.inspect,self.assets,self.soundVisibility,self.placeStart,self.worlds,self.export} do
  control.Parent=commands;control.LayoutOrder=index
  control.Size=UDim2.fromOffset(({100,90,55,130,55,74,68,68,78,62,80,108,136,156,156,100})[index],31)
 end
 self.worlds.Text="Save & Play Test";self.worlds.BackgroundColor3=View.activeColor
 self.export.BackgroundColor3=View.buttonColor
 local help=text(toolbar,"ToolbarHelp","",24);help.Position=UDim2.fromOffset(175,0);help.Size=UDim2.new(1,-185,0,24);help.TextColor3=accent
 for control,description in {
  [self.newWorld]="Start a blank draft. Undo restores the current world.",
  [self.openWorld]="Browse your private saved worlds.",
  [self.saveWorld]="Save a new revision of this world.",
  [self.saveAs]="Save this draft under a different World ID.",
  [self.inspect]="Show map dimensions and selected-object properties.",
  [self.assets]="Show or hide the searchable native asset library.",
  [self.worlds]="Save the draft and launch the existing private playtest.",
 } do
  self:on(control.MouseEnter,function() help.Text=description end)
  self:on(control.MouseLeave,function() if help.Text==description then help.Text="" end end)
 end
 self.left=scrolling(frame,"ToolShelf",UDim2.fromOffset(208,400),UDim2.fromOffset(6,74))
 local toolTitle=text(self.left,"ToolTitle","TOOLS",24);toolTitle.Position=UDim2.fromOffset(8,2)
 self.terrainTools={}
 for index,name in {"Raise","Lower","Smooth","Flatten"} do
  self.terrainTools[name]=button(self.left,"Terrain"..name,name.." Terrain",UDim2.new(1,-18,0,29),UDim2.fromOffset(8,28+(index-1)*34))
 end
 self.tools.Select=button(self.left,"Select","Select / Navigate")
 self.tools.Resize=button(self.left,"Resize","Resize")
 for index,name in {"Select","Move","Rotate","Scale","Resize","Snap"} do
  local control=self.tools[name];control.Parent=self.left
  control.Position=UDim2.fromOffset(8,28+(index-1)*34);control.Size=UDim2.new(1,-18,0,29)
 end
 self.delete.Parent=self.left;self.delete.Position=UDim2.fromOffset(8,232);self.delete.Size=UDim2.new(1,-18,0,29)
 for _,record in {{controls,267},{rotations,349},{magnets,419}} do
  record[1].Parent=self.left;record[1].Position=UDim2.fromOffset(0,record[2]);record[1].BackgroundColor3=panel
 end
 pane.BackgroundColor3=panel;pane.AnchorPoint=Vector2.zero
 label.Text="OBJECT LIBRARY";label.Position=UDim2.fromOffset(10,1);label.Size=UDim2.fromOffset(160,24)
 self.repeatPlacement=button(pane,"RepeatPlacement","Repeat: Off",UDim2.fromOffset(92,24),UDim2.new(1,-102,0,2))
 self.recentAssets=button(pane,"RecentAssets","Recent",UDim2.fromOffset(62,24),UDim2.new(1,-169,0,2))
 self.up.Position=UDim2.fromOffset(10,28)
 self.breadcrumb.Position=UDim2.fromOffset(50,28);self.breadcrumb.Size=UDim2.new(.48,-54,0,28)
 self.search.Position=UDim2.new(.48,0,0,26);self.search.Size=UDim2.new(.52,-10,0,28)
 self.assetScroll.Position=UDim2.fromOffset(10,58);self.assetScroll.Size=UDim2.new(1,-20,1,-85)
 grid.CellSize=UDim2.fromOffset(132,116)
 self.frameWorld.Text="Frame world  •  Home"
 self.brushPanel=scrolling(frame,"BrushSettings",UDim2.fromOffset(0,0),UDim2.fromOffset(0,0))
 make("UIPadding",self.brushPanel,{PaddingLeft=UDim.new(0,10),PaddingTop=UDim.new(0,8)})
 make("UIListLayout",self.brushPanel,{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
 self.brushFields={}
 self.tractionLabel=text(self.brushPanel,"TractionLabel","Traction (% of pavement)",24)
 self.tractionLabel.LayoutOrder=2;self.tractionLabel.Visible=false
 self.traction=make("TextBox",self.brushPanel,{Name="TractionPercent",LayoutOrder=3,Size=UDim2.new(1,-14,0,28),
  Text="",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=View.buttonColor,Font=Enum.Font.Code,TextSize=14,Visible=false})
 text(self.brushPanel,"BrushTitle","TERRAIN BRUSH",27).LayoutOrder=1
 for i,spec in {{"radius","Radius (studs)",26},{"strength","Strength",24},{"falloff","Falloff (0–1)",.65},{"elevation","Flatten elevation (studs)",0},{"depth","Water / ravine depth (studs)",4}} do
  text(self.brushPanel,spec[1].."Label",spec[2],22).LayoutOrder=i*2+2
  self.brushFields[spec[1]]=make("TextBox",self.brushPanel,{Name=spec[1],LayoutOrder=i*2+3,Size=UDim2.new(1,-14,0,28),
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
 self.terrainDock=scrolling(frame,"TerrainToolsDock",UDim2.fromOffset(0,0),UDim2.fromOffset(0,0))
 self.terrainDock.AutomaticCanvasSize=Enum.AutomaticSize.X;self.terrainDock.ScrollingDirection=Enum.ScrollingDirection.X
 make("UIListLayout",self.terrainDock,{FillDirection=Enum.FillDirection.Horizontal,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})
 self.surfaceTools={}
 for index,name in {"Grass","Mud","Ice","Snow","Pavement","Water","Carve Ravine","Tunnel"} do
  local tile=button(self.terrainDock,"Brush"..name,name,UDim2.fromOffset(if index==7 then 112 else 78,40))
  tile.LayoutOrder=index;self.surfaceTools[name]=tile
 end
 self.hint.Text="Wheel zoom · MMB pan · RMB orbit · WASD / Q E fly · Shift boost · F focus · Home frame"
 self.dockOpen=true;self.inspectorOpen=true
 self:on(self.toolShelf.Activated,function()
  self.toolsOpen=not self.left.Visible;self:layout()
 end)
 self:on(self.assets.Activated,function() self.dockOpen=not self.dockOpen;self:layout() end)
 self:on(self.inspect.Activated,function() self.inspectorOpen=not self.inspectorOpen;self:layout() end)
 self:on(frame:GetPropertyChangedSignal("AbsoluteSize"),function() self:layout() end)
 self:layout()
 return self
end
function View:layout()
 local size=self.frame.AbsoluteSize
 local compact=size.X>0 and size.X<830
 local toolsOpen=if self.toolsOpen==nil then not compact else self.toolsOpen
 local left=if toolsOpen then (if compact then 0 else 220) else 0
 local right=if self.inspectorOpen then (if compact then math.min(174,math.floor(size.X*.36)) else 258) else 0
 local dock=if self.terrainActive then 53 elseif self.dockOpen then (if size.Y>0 then math.min(218,math.floor(size.Y*.38)) else 218) else 0
 self.toolbar.Size=UDim2.new(1,0,0,68)
 self.left.Visible=toolsOpen;self.left.Size=UDim2.new(0,if compact then math.min(208,math.floor(size.X*.3)) else 208,1,-118)
 self.left.ZIndex=if compact then 5 else 1
 self.viewport.Position=UDim2.fromOffset(left,74);self.viewport.Size=UDim2.new(1,-left-right-6,1,-dock-122)
 self.properties.Visible=self.inspectorOpen and not self.terrainActive;self.properties.Position=UDim2.new(1,-right,0,74)
 self.properties.Size=UDim2.new(0,math.max(right-6,0),1,-122)
 self.brushPanel.Position=self.properties.Position;self.brushPanel.Size=self.properties.Size
 self.brushPanel.Visible=self.inspectorOpen and self.terrainActive==true
 self.palette.Visible=self.dockOpen and not self.terrainActive;self.palette.Position=UDim2.new(0,left,1,-dock-48)
 self.palette.Size=UDim2.new(1,-left-right-6,0,dock)
 self.terrainDock.Visible=self.terrainActive==true;self.terrainDock.Position=self.palette.Position;self.terrainDock.Size=self.palette.Size
 self.status.Position=UDim2.new(0,8,1,-46);self.status.Size=UDim2.new(1,if self.finishPaint.Visible or self.paintBucket.Visible then -154 else -16,0,24)
 self.hint.Position=UDim2.new(0,8,1,-23);self.hint.Size=UDim2.new(1,-16,0,22)
 self.inspect.BackgroundColor3=if self.inspectorOpen then View.activeColor else View.buttonColor
 self.assets.BackgroundColor3=if self.dockOpen then View.activeColor else View.buttonColor
 self.toolShelf.BackgroundColor3=if toolsOpen then View.activeColor else View.buttonColor
end
function View:terrainMode(enabled,operation)
 if enabled and not self.terrainActive then self.toolsOpen=true end
 self.terrainActive=enabled
 for index,row in self.dimensionRows do
  row.LayoutOrder=if enabled then index-#self.dimensionRows else index
  row.Parent=if enabled then self.brushPanel else self.properties
 end
 self.terrain.BackgroundColor3=if enabled then View.activeColor else View.buttonColor
 for name,control in self.terrainTools do
  control.Visible=enabled;control.BackgroundColor3=if operation==name then View.activeColor else View.buttonColor
 end
 for name,control in self.surfaceTools do control.BackgroundColor3=if operation==name then View.activeColor else View.buttonColor end
 for _,control in self.tools do control.Visible=not enabled end
 for _,control in {self.delete,self.options,self.rotationPanel,self.magnets} do control.Visible=not enabled end
 self:layout()
end
function View:on(event,callback) table.insert(self.connections,event:Connect(callback)) end
function View:message(message) self.status.Text=tostring(message):gsub("^.-:%d+:%s*","") end
function View:isModal() return self.sfxPicker.Visible or self.overlay.Visible or (self.library and self.library.frame.Visible) end
function View:isScene(point)
 return self.frame.Visible and not self:isModal() and rectContains(self.viewport,point) and not (self.left.Visible and rectContains(self.left,point))
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
function View:paletteEntries(directories,items,prefix,page,assets,onFolder,onAsset)
 for _,connection in self.paletteConnections do connection:Disconnect() end;self.paletteConnections={}
 for _,child in self.assetScroll:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
 self.thumbnails={};self.breadcrumb.Text="Assets / "..prefix
 local entries={};for _,folder in directories do table.insert(entries,{folder=folder}) end;for _,item in items do table.insert(entries,{item=item}) end
 local pages=math.max(1,math.ceil(#entries/24));page=math.clamp(page,1,pages)
 for index=(page-1)*24+1,math.min(#entries,page*24) do
  local entry=entries[index];local tile=button(self.assetScroll,entry.folder or entry.item.model,"");tile.LayoutOrder=index
  if entry.folder then
   local label=text(tile,"Folder","▸  "..entry.folder.." /",90);label.TextSize=17;label.TextColor3=accent
   table.insert(self.paletteConnections,tile.Activated:Connect(function() onFolder(entry.folder) end))
  else
   local item=entry.item;self:thumbnail(tile,item,assets)
   local name=text(tile,"AssetName",(if item.available then item.name.."\n"..item.model else "[Missing] "..item.model),30);name.Position=UDim2.fromOffset(5,83);name.Size=UDim2.new(1,-10,0,30);name.TextSize=11
   if not item.available then tile.BackgroundColor3=Color3.fromRGB(64,45,43)
   elseif Document.canSetAssetTraction(item) then tile.BackgroundColor3=collisionTile end
   if tile.MouseButton1Down then
    table.insert(self.paletteConnections,tile.MouseButton1Down:Connect(function() onAsset(item) end))
   else
    table.insert(self.paletteConnections,tile.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 then onAsset(item) end end))
   end
  end
 end
 self.page.Text=string.format("%d assets / folders • %d/%d",#entries,page,pages)
 return page,pages
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
 local tractionVisible=entry~=nil and Document.canSetAssetTraction(item)
 self.assetTractionLabel.Visible=tractionVisible;self.assetTraction.Visible=tractionVisible
 if tractionVisible and game:GetService("UserInputService"):GetFocusedTextBox()~=self.assetTraction then
  self.assetTraction.Text=if entry.traction~=nil then tostring(entry.traction) else ""
 end
 local destructible=entry~=nil and entry.destructible==true
 local enabled=destructible and entry.regenerates~=false
 self.regenerates.Visible=destructible
 self.regenerates.Text=if enabled then "☑ Regenerates" else "☐ Regenerates"
 self.regenerationDelay.Visible=destructible;self.regenerationLabel.Visible=destructible
 self.regenerationDelay.TextEditable=enabled
 if destructible then self.regenerationDelay.Text=tostring(entry.regenerationDelay or Document.DefaultRegenerationDelay) end
 if entry and entry.slot then
  self.selected.Text="PLAYER "..entry.slot.." STARTING AREA\nRoom for three tanks"
  for key,field in self.fields do
   local n=({x=entry.position[1],z=entry.position[3],yaw=entry.heading})[key]
   field.Text=if n then tostring(n) else "";field.TextEditable=n~=nil
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
 for key,field in self.fields do field.Text=if values[key] then string.format("%.5g",values[key]) else "" end
 self.solid.Text=if entry and entry.sound then "Audio trigger • no collision" else "Collision: "..(if entry then (if entry.solid then "SOLID" else "NONE") else "—")
 self.destructible.Text="Destructible: "..(if entry then (if entry.destructible then "YES" else "NO") else "—")
 self.influences.Text=if entry then "physical.movable = false\n"..(if item.zone then item.zone.." zone: "..(if item.zone=="Water" then "90%" else "75%").." speed\n" else "")..(if item.collider then string.format("Collider W %.3g / D %.3g / H %.3g",item.collider.widthFraction,item.collider.depthFraction,item.collider.heightFraction) else "No registered collider; visual only") else "Fixed objects • height / tilt • uniform scale"
end
function View:destroy()
 for _,connection in self.connections do connection:Disconnect() end
 for _,connection in self.paletteConnections do connection:Disconnect() end
 self.frame:Destroy()
end
return View
