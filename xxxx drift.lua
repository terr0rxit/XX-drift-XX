-- ╔══════════════════════════════════════════════════════════════╗
-- ║                    X • الانجراف  Controller                  ║
-- ║     Carro | Jogador | Camber | Câmera | Visual | HUD | Painel║
-- ╚══════════════════════════════════════════════════════════════╝

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local Lighting         = game:GetService("Lighting")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

local C = {
	bg = Color3.fromRGB(8, 8, 8),
	panel = Color3.fromRGB(16, 16, 16),
	border = Color3.fromRGB(45, 45, 45),
	title = Color3.fromRGB(230, 230, 230),
	text = Color3.fromRGB(220, 220, 220),
	dim = Color3.fromRGB(140, 140, 140),
	inputBg = Color3.fromRGB(12, 12, 12),
	divider = Color3.fromRGB(35, 35, 35),
	on = Color3.fromRGB(0, 180, 70),
	off = Color3.fromRGB(40, 40, 40),
	apply = Color3.fromRGB(35, 35, 35),
	green = Color3.fromRGB(0, 170, 60),
	red = Color3.fromRGB(170, 30, 30),
	tabActive = Color3.fromRGB(0, 160, 65),
	tabInactive = Color3.fromRGB(28, 28, 28),
}

local connections, sectionRefs = {}, {}

local currentCar = nil
local driftState = { front = { enabled = false }, rear = { enabled = false } }
local driftOriginals = { front = nil, rear = nil }
local motorState = { enabled = false, maxVel = 100, maxTorque = 50000, currentDir = "Parar" }
local steerState = { enabled = false, autoAlign = false, maxAngle = 0.4, speed = 0.5, currentSteer = 0, isA = false, isD = false }

local playerState = { speed = 16, jump = 50 }

local stanceActiveTab = "FRENTE"
local FrontConfig = { PositionX = 0, PositionY = 0, PositionZ = 0, Camber = 0 }
local RearConfig  = { PositionX = 0, PositionY = 0, PositionZ = 0, Camber = 0 }
local originalOffsets, lastStanceCar = {}, nil

local camState = { spectating = false, spectateTarget = nil, spectateIndex = 1 }

local shaderState = { enabled = false }
local originalLighting = {}

local hudState = {
	arrowsEnabled = true,
	btnSize = 80,
	transparency = 0,
}
local motorFrame, steerFrame
local mobileButtons, lockButtons = {}, {}

local uiState = {
	scale = 0.75,
	locked = false,
}

--------------------------------------------------------------------
-- Utils
--------------------------------------------------------------------
local function parseNum(str)
	return tonumber((tostring(str):gsub(",", ".")))
end

local function uiCorner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = parent
end

local function uiStroke(parent, color, thick)
	local s = Instance.new("UIStroke")
	s.Color = color or C.border
	s.Thickness = thick or 1
	s.Parent = parent
end

-- Arraste: retorna setLocked + beginDrag (pra usar nas setas)
local function makeDraggable(frame, handle)
	local dragging, dragStart, startPos, locked = false, nil, nil, false
	handle = handle or frame

	local function beginDrag(input)
		if locked then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
		end
	end

	local function endDrag(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end

	handle.InputBegan:Connect(beginDrag)
	handle.InputEnded:Connect(endDrag)

	local conn = UserInputService.InputChanged:Connect(function(input)
		if locked or not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local d = input.Position - dragStart
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y
			)
		end
	end)
	table.insert(connections, conn)

	local conn2 = UserInputService.InputEnded:Connect(endDrag)
	table.insert(connections, conn2)

	return function(state)
		locked = state
		if state then dragging = false end
	end, beginDrag
end

--------------------------------------------------------------------
-- CARRO
--------------------------------------------------------------------
local function findPlayerCar()
	local folder = workspace:FindFirstChild("Cars")
	if not folder then return nil end
	for _, car in ipairs(folder:GetChildren()) do
		local stats = car:FindFirstChild("Stats")
		if stats then
			local owner = stats:FindFirstChild("Owner")
			if owner then
				local v = owner.Value
				if v == player.Name or v == player or v == player.UserId
					or tostring(v) == player.Name or tostring(v) == tostring(player.UserId) then
					return car
				end
			end
		end
	end
	return nil
end

local function isPlayerInCar(car)
	if not car or not player.Character then return false end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not humanoid.SeatPart then return false end
	return humanoid.SeatPart:IsDescendantOf(car)
end

local WHEEL_PREFIXES = { front = { "FL", "FR" }, rear = { "RL", "RR" } }

local function getWheels(car, group)
	local result = {}
	for _, obj in ipairs(car:GetChildren()) do
		for _, pfx in ipairs(WHEEL_PREFIXES[group]) do
			if obj.Name == pfx or obj.Name:match("^" .. pfx .. "_%d+$") then
				local w = obj:FindFirstChild("Wheel")
				if w and w:IsA("BasePart") then
					table.insert(result, w)
				end
			end
		end
	end
	return result
end

local function readPhysics(wheel)
	local p = wheel.CustomPhysicalProperties
	if typeof(p) == "PhysicalProperties" then
		return {
			density = p.Density,
			friction = p.Friction,
			elasticity = p.Elasticity,
			frictionWeight = p.FrictionWeight,
			elasticityWeight = p.ElasticityWeight,
		}
	end
	return { density = 0.7, friction = 0.3, elasticity = 0.5, frictionWeight = 1.0, elasticityWeight = 1.0 }
end

local function applyDrift(group, friction, frictionWeight)
	if not currentCar then return false end
	local wheels = getWheels(currentCar, group)
	if #wheels == 0 then return false end
	if not driftOriginals[group] then
		driftOriginals[group] = readPhysics(wheels[1])
	end
	local base = driftOriginals[group]
	for _, w in ipairs(wheels) do
		w.CustomPhysicalProperties = PhysicalProperties.new(
			base.density, friction, base.elasticity, frictionWeight, base.elasticityWeight
		)
	end
	return true
end

local function revertDrift(group)
	if not currentCar or not driftOriginals[group] then return end
	local wheels = getWheels(currentCar, group)
	local o = driftOriginals[group]
	for _, w in ipairs(wheels) do
		w.CustomPhysicalProperties = PhysicalProperties.new(
			o.density, o.friction, o.elasticity, o.frictionWeight, o.elasticityWeight
		)
	end
end

local function obterConstraints()
	if not currentCar then return nil end
	local constraints = currentCar:FindFirstChild("Constraints")
	if not constraints then return nil end
	for _, item in pairs(constraints:GetChildren()) do
		if item.Name == "Front" or item.Name == "Rear" then
			item.Name = "Rodas"
		end
	end
	return constraints
end

local function aplicarMotor(direcao)
	if not motorState.enabled then return end
	local constraints = obterConstraints()
	if not constraints then return end
	local velocidadeAlvo = 0
	if direcao == "Frente" then
		velocidadeAlvo = -math.abs(motorState.maxVel)
	elseif direcao == "Re" then
		velocidadeAlvo = math.abs(motorState.maxVel)
	end
	if direcao ~= "Parar" and not isPlayerInCar(currentCar) then
		velocidadeAlvo = 0
	end
	for _, motor in pairs(constraints:GetChildren()) do
		if motor.Name == "Rodas" and (motor:IsA("CylindricalConstraint") or motor:IsA("HingeConstraint")) then
			motor.ActuatorType = Enum.ActuatorType.Motor
			motor.MotorMaxTorque = motorState.maxTorque
			motor.AngularVelocity = velocidadeAlvo
		end
	end
end

local function applySteerAngle(angle)
	if not currentCar then return end
	for _, name in ipairs({ "FR", "FL" }) do
		local wheel = currentCar:FindFirstChild(name)
		if wheel then
			local axel = wheel:FindFirstChild("Axel")
			if axel then
				local attachment = axel:FindFirstChild("Attachment0")
				if attachment then
					local axis = attachment.Axis
					attachment.Axis = Vector3.new(axis.X, axis.Y, angle)
				end
			end
		end
	end
end

local function resetSteerOnExit()
	steerState.isA = false
	steerState.isD = false
	steerState.currentSteer = 0
	applySteerAngle(0)
end

--------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------
local function applyHudSettings()
	local size = math.clamp(hudState.btnSize or 80, 40, 140)
	local gap = 12
	local frameW = size * 2 + gap
	local frameH = size
	local trans = math.clamp(hudState.transparency or 0, 0, 1)
	local show = hudState.arrowsEnabled and UserInputService.TouchEnabled

	if motorFrame then
		motorFrame.Size = UDim2.new(0, frameW, 0, frameH)
		motorFrame.Visible = show
	end
	if steerFrame then
		steerFrame.Size = UDim2.new(0, frameW, 0, frameH)
		steerFrame.Visible = show
	end

	for _, data in ipairs(mobileButtons) do
		local btn = data.btn
		btn.Size = UDim2.new(0, size, 0, size)
		btn.Position = data.right and UDim2.new(0, size + gap, 0, 0) or UDim2.new(0, 0, 0, 0)
		btn.BackgroundTransparency = math.clamp(0.35 + trans * 0.65, 0, 1)
		btn.TextTransparency = trans
		btn.TextSize = math.floor(size * 0.5)
		local stroke = btn:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Transparency = trans end
	end

	for _, lock in ipairs(lockButtons) do
		lock.BackgroundTransparency = math.clamp(0.35 + trans * 0.65, 0, 1)
		lock.TextTransparency = trans
		local stroke = lock:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Transparency = trans end
	end
end

--------------------------------------------------------------------
-- JOGADOR
--------------------------------------------------------------------
local function applySpeed(val)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = val end
end

local function applyJump(val)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.JumpPower = val
		pcall(function() hum.JumpHeight = val / 2.5 end)
	end
end

--------------------------------------------------------------------
-- CAMBER
--------------------------------------------------------------------
local wheelNames = { "FL", "FR", "RL", "RR" }

local function getWheelAttachments(car)
	local attachments = {}
	for _, name in ipairs(wheelNames) do
		local wheelModel = car:FindFirstChild(name)
		if wheelModel then
			local holder = wheelModel:FindFirstChild("Holder")
			if holder then
				local att = holder:FindFirstChild("Attachment0")
				if att and att:IsA("Attachment") then
					attachments[name] = att
					if not originalOffsets[att] then
						originalOffsets[att] = { CFrame = att.CFrame }
					end
				end
			end
		end
	end
	return attachments
end

local function applyStance()
	local myCar = findPlayerCar()
	if not myCar then return end
	for name, att in pairs(getWheelAttachments(myCar)) do
		local orig = originalOffsets[att]
		if orig then
			local config = (name == "RL" or name == "RR") and RearConfig or FrontConfig
			local mx = (name == "FL" or name == "RL") and -1 or 1
			local cs = (name == "FL" or name == "RL") and -1 or 1
			local pos = Vector3.new(
				orig.CFrame.Position.X + config.PositionX * mx,
				orig.CFrame.Position.Y + config.PositionY,
				orig.CFrame.Position.Z + config.PositionZ
			)
			att.CFrame = CFrame.new(pos) * orig.CFrame.Rotation * CFrame.Angles(0, 0, config.Camber * cs)
		end
	end
end

local function resetStance()
	FrontConfig = { PositionX = 0, PositionY = 0, PositionZ = 0, Camber = 0 }
	RearConfig  = { PositionX = 0, PositionY = 0, PositionZ = 0, Camber = 0 }
	local myCar = findPlayerCar()
	if myCar then
		for _, att in pairs(getWheelAttachments(myCar)) do
			if originalOffsets[att] then
				att.CFrame = originalOffsets[att].CFrame
			end
		end
	end
end

--------------------------------------------------------------------
-- SPECTATE
--------------------------------------------------------------------
local function getPlayerList(includeSelf)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if (includeSelf or p ~= player) and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			table.insert(list, p)
		end
	end
	return list
end

local function restoreNormalCam()
	camera.CameraType = Enum.CameraType.Custom
	if player.Character then
		local h = player.Character:FindFirstChildOfClass("Humanoid")
		if h then camera.CameraSubject = h end
	end
end

local function stopSpectate()
	camState.spectating = false
	camState.spectateTarget = nil
	restoreNormalCam()
end

local function startSpectate(target)
	if not target or not target.Character then return false end
	local hum = target.Character:FindFirstChildOfClass("Humanoid")
	local root = target.Character:FindFirstChild("HumanoidRootPart")
	local subject = hum or root
	if not subject then return false end
	camState.spectating = true
	camState.spectateTarget = target
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = subject
	return true
end

local function cycleSpectate(dir)
	local list = getPlayerList(true)
	if #list == 0 then stopSpectate() return nil end
	camState.spectateIndex += dir
	if camState.spectateIndex > #list then camState.spectateIndex = 1 end
	if camState.spectateIndex < 1 then camState.spectateIndex = #list end
	local t = list[camState.spectateIndex]
	startSpectate(t)
	return t
end

--------------------------------------------------------------------
-- SHADERS
--------------------------------------------------------------------
local function saveLighting()
	originalLighting = {
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		GlobalShadows = Lighting.GlobalShadows,
		Technology = Lighting.Technology,
	}
end

local function applyShaders(state)
	shaderState.enabled = state
	if state then
		if not next(originalLighting) then saveLighting() end
		Lighting.Brightness = 2.2
		Lighting.Ambient = Color3.fromRGB(90, 90, 90)
		Lighting.OutdoorAmbient = Color3.fromRGB(110, 110, 110)
		Lighting.FogEnd = 100000
		Lighting.FogStart = 0
		Lighting.GlobalShadows = false
		pcall(function() Lighting.Technology = Enum.Technology.Compatibility end)
	elseif next(originalLighting) then
		Lighting.Brightness = originalLighting.Brightness
		Lighting.Ambient = originalLighting.Ambient
		Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient
		Lighting.FogEnd = originalLighting.FogEnd
		Lighting.FogStart = originalLighting.FogStart
		Lighting.GlobalShadows = originalLighting.GlobalShadows
		pcall(function() Lighting.Technology = originalLighting.Technology end)
	end
end

--------------------------------------------------------------------
-- GUI
--------------------------------------------------------------------
local old = playerGui:FindFirstChild("CDTController")
if old then old:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name = "CDTController"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.IgnoreGuiInset = true
sg.Parent = playerGui

sg:GetPropertyChangedSignal("Parent"):Connect(function()
	if not sg.Parent then
		for _, c in ipairs(connections) do
			pcall(function() c:Disconnect() end)
		end
	end
end)

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 110, 0, 28)
toggleBtn.Position = UDim2.new(0, 14, 0.5, -14)
toggleBtn.BackgroundColor3 = C.bg
toggleBtn.Text = "X • الانجراف"
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 12
toggleBtn.TextColor3 = C.text
toggleBtn.Parent = sg
uiCorner(toggleBtn, 7)
uiStroke(toggleBtn, C.border, 1)
makeDraggable(toggleBtn)

local menu = Instance.new("Frame")
menu.Size = UDim2.new(0, 400, 0, 480)
menu.Position = UDim2.new(0.5, -200, 0.5, -240)
menu.BackgroundColor3 = C.bg
menu.Visible = false
menu.ClipsDescendants = true
menu.Parent = sg
uiCorner(menu, 10)
uiStroke(menu, C.border, 1.5)

local uiScale = Instance.new("UIScale")
uiScale.Scale = uiState.scale
uiScale.Parent = menu

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 34)
titleBar.BackgroundColor3 = C.panel
titleBar.Parent = menu
uiCorner(titleBar, 10)

local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0.5, 0)
titleFix.Position = UDim2.new(0, 0, 0.5, 0)
titleFix.BackgroundColor3 = C.panel
titleFix.BorderSizePixel = 0
titleFix.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Size = UDim2.new(1, -40, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.Text = "X • الانجراف"
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 14
titleLabel.TextColor3 = C.title
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local setMenuLock = makeDraggable(menu, titleBar)

local tabBarFrame = Instance.new("Frame")
tabBarFrame.Size = UDim2.new(1, -12, 0, 28)
tabBarFrame.Position = UDim2.new(0, 6, 0, 40)
tabBarFrame.BackgroundTransparency = 1
tabBarFrame.ClipsDescendants = true
tabBarFrame.Parent = menu

local tabScroll = Instance.new("ScrollingFrame")
tabScroll.Size = UDim2.new(1, 0, 1, 0)
tabScroll.BackgroundTransparency = 1
tabScroll.BorderSizePixel = 0
tabScroll.ScrollBarThickness = 3
tabScroll.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 70)
tabScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
tabScroll.ScrollingDirection = Enum.ScrollingDirection.X
tabScroll.Parent = tabBarFrame

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 4)
tabLayout.Parent = tabScroll

local tabs, pages = {}, {}

local function createTab(name)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 60, 0, 26)
	btn.BackgroundColor3 = C.tabInactive
	btn.Text = name
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 10
	btn.TextColor3 = C.dim
	btn.AutoButtonColor = false
	btn.Parent = tabScroll
	uiCorner(btn, 6)

	local page = Instance.new("ScrollingFrame")
	page.Size = UDim2.new(1, -16, 1, -80)
	page.Position = UDim2.new(0, 8, 0, 74)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 4
	page.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 70)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.Visible = false
	page.Parent = menu

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 2)
	pad.PaddingRight = UDim.new(0, 2)
	pad.Parent = page

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = page

	tabs[name] = btn
	pages[name] = page

	btn.MouseButton1Click:Connect(function()
		for n, b in pairs(tabs) do
			b.BackgroundColor3 = (n == name) and C.tabActive or C.tabInactive
			b.TextColor3 = (n == name) and C.text or C.dim
			pages[n].Visible = (n == name)
		end
	end)
	return page
end

local pageCarro  = createTab("Carro")
local pagePlayer = createTab("Jogador")
local pageCamber = createTab("Camber")
local pageCamera = createTab("Câmera")
local pageVisual = createTab("Visual")
local pageHud    = createTab("HUD")
local pagePainel = createTab("Painel")

tabs["Carro"].BackgroundColor3 = C.tabActive
tabs["Carro"].TextColor3 = C.text
pages["Carro"].Visible = true

local function createSection(parent, title, order)
	local sec = Instance.new("Frame")
	sec.BackgroundColor3 = C.panel
	sec.AutomaticSize = Enum.AutomaticSize.Y
	sec.Size = UDim2.new(1, 0, 0, 0)
	sec.LayoutOrder = order
	sec.Parent = parent
	uiCorner(sec, 8)
	uiStroke(sec, C.divider, 1)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = sec

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = sec

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 16)
	header.Text = title
	header.Font = Enum.Font.GothamBold
	header.TextSize = 12
	header.TextColor3 = C.title
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.LayoutOrder = 0
	header.Parent = sec
	return sec
end

local function makeToggle(parent, label, default, order, callback)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(0.7, 0, 1, 0)
	lbl.Text = label
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 11
	lbl.TextColor3 = C.dim
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 44, 0, 20)
	btn.Position = UDim2.new(1, -44, 0.5, -10)
	btn.BackgroundColor3 = default and C.on or C.off
	btn.Text = default and "ON" or "OFF"
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 10
	btn.TextColor3 = C.text
	btn.AutoButtonColor = false
	btn.Parent = row
	uiCorner(btn, 10)

	local state = default
	btn.MouseButton1Click:Connect(function()
		state = not state
		btn.Text = state and "ON" or "OFF"
		TweenService:Create(btn, TweenInfo.new(0.15), {
			BackgroundColor3 = state and C.on or C.off
		}):Play()
		if callback then callback(state) end
	end)

	return function(val)
		state = val
		btn.Text = val and "ON" or "OFF"
		btn.BackgroundColor3 = val and C.on or C.off
	end
end

local function makeInput(parent, label, default, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(0.5, 0, 1, 0)
	lbl.Text = label
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 11
	lbl.TextColor3 = C.dim
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0, 100, 0, 22)
	box.Position = UDim2.new(1, -100, 0.5, -11)
	box.BackgroundColor3 = C.inputBg
	box.Text = tostring(default)
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 11
	box.TextColor3 = C.text
	box.ClearTextOnFocus = true
	box.Parent = row
	uiCorner(box, 5)
	uiStroke(box, C.border, 1)
	return box
end

local function makeButton(parent, text, order, callback)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 28)
	btn.BackgroundColor3 = C.apply
	btn.Text = text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = C.text
	btn.LayoutOrder = order
	btn.Parent = parent
	uiCorner(btn, 6)
	btn.MouseButton1Click:Connect(callback)
	return btn
end

local function makeStanceRow(parent, label, configKey, order, getConfig, setConfig)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(0.45, 0, 1, 0)
	lbl.Text = label
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 11
	lbl.TextColor3 = C.dim
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local selector = Instance.new("Frame")
	selector.Size = UDim2.new(0, 130, 0, 24)
	selector.Position = UDim2.new(1, -130, 0.5, -12)
	selector.BackgroundColor3 = C.inputBg
	selector.Parent = row
	uiCorner(selector, 5)
	uiStroke(selector, C.border, 1)

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -48, 1, 0)
	box.Position = UDim2.new(0, 24, 0, 0)
	box.BackgroundTransparency = 1
	box.Text = "0.00"
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 11
	box.TextColor3 = C.text
	box.Parent = selector

	local dec = Instance.new("TextButton")
	dec.Size = UDim2.new(0, 24, 1, 0)
	dec.BackgroundTransparency = 1
	dec.Text = "<"
	dec.TextColor3 = C.dim
	dec.TextSize = 12
	dec.Font = Enum.Font.GothamBold
	dec.Parent = selector

	local inc = Instance.new("TextButton")
	inc.Size = UDim2.new(0, 24, 1, 0)
	inc.Position = UDim2.new(1, -24, 0, 0)
	inc.BackgroundTransparency = 1
	inc.Text = ">"
	inc.TextColor3 = C.dim
	inc.TextSize = 12
	inc.Font = Enum.Font.GothamBold
	inc.Parent = selector

	local function updateValue(v)
		setConfig(configKey, v)
		box.Text = string.format("%.2f", v)
		applyStance()
	end

	dec.MouseButton1Click:Connect(function() updateValue(getConfig(configKey) - 0.05) end)
	inc.MouseButton1Click:Connect(function() updateValue(getConfig(configKey) + 0.05) end)
	box.FocusLost:Connect(function()
		local v = parseNum(box.Text)
		if v then updateValue(v) else box.Text = string.format("%.2f", getConfig(configKey)) end
	end)
	return box
end

--------------------------------------------------------------------
-- ABA CARRO
--------------------------------------------------------------------
local secDrift = createSection(pageCarro, "الانجراف (Drift)", 1)
local frictionBox = makeInput(secDrift, "Friction", "0.30", 1)
local weightBox = makeInput(secDrift, "Weight", "1.00", 2)
local setDriftToggle = makeToggle(secDrift, "Ativar Drift", false, 3, function(val)
	driftState.front.enabled = val
	driftState.rear.enabled = val
	if val then
		local f, fw = parseNum(frictionBox.Text), parseNum(weightBox.Text)
		if f and fw then
			applyDrift("front", f, fw)
			applyDrift("rear", f, fw)
		end
	else
		revertDrift("front")
		revertDrift("rear")
	end
end)
makeButton(secDrift, "Aplicar Drift", 4, function()
	local f, fw = parseNum(frictionBox.Text), parseNum(weightBox.Text)
	if f and fw and currentCar then
		if not driftState.front.enabled then setDriftToggle(true) end
		applyDrift("front", f, fw)
		applyDrift("rear", f, fw)
	end
end)

local secMotor = createSection(pageCarro, "المحرك (Motor)", 2)
local velBox = makeInput(secMotor, "Velocidade", "100", 1)
local torqueBox = makeInput(secMotor, "Torque", "50000", 2)
local setMotorToggle = makeToggle(secMotor, "Ativar Motor", false, 3, function(val)
	motorState.enabled = val
	if not val then
		motorState.currentDir = "Parar"
		aplicarMotor("Parar")
	end
end)
makeButton(secMotor, "Aplicar Motor", 4, function()
	local v, t = parseNum(velBox.Text), parseNum(torqueBox.Text)
	if v and t then
		motorState.maxVel = v
		motorState.maxTorque = t
		if not motorState.enabled then setMotorToggle(true) end
	end
end)

local secSteer = createSection(pageCarro, "التوجيه (Direção)", 3)
local angleBox = makeInput(secSteer, "Max Angle", "0.40", 1)
local speedBox = makeInput(secSteer, "Speed", "0.50", 2)
local setSteerToggle = makeToggle(secSteer, "Ativar Direção", false, 3, function(val)
	steerState.enabled = val
	if not val then resetSteerOnExit() end
end)
makeToggle(secSteer, "Auto-Alinhar", false, 4, function(val)
	steerState.autoAlign = val
end)
makeButton(secSteer, "Aplicar Direção", 5, function()
	local a, s = parseNum(angleBox.Text), parseNum(speedBox.Text)
	if a and s then
		steerState.maxAngle = a
		steerState.speed = s
		if not steerState.enabled then setSteerToggle(true) end
	end
end)

sectionRefs.drift = { setToggle = setDriftToggle }
sectionRefs.motor = { setToggle = setMotorToggle }
sectionRefs.steer = { setToggle = setSteerToggle }

--------------------------------------------------------------------
-- ABA JOGADOR
--------------------------------------------------------------------
local secSpeed = createSection(pagePlayer, "Speed", 1)
local speedInput = makeInput(secSpeed, "WalkSpeed", "16", 1)
makeButton(secSpeed, "Aplicar Speed", 2, function()
	local v = parseNum(speedInput.Text)
	if v then playerState.speed = v applySpeed(v) end
end)

local secJump = createSection(pagePlayer, "Jump", 2)
local jumpInput = makeInput(secJump, "JumpPower", "50", 1)
makeButton(secJump, "Aplicar Jump", 2, function()
	local v = parseNum(jumpInput.Text)
	if v then playerState.jump = v applyJump(v) end
end)

--------------------------------------------------------------------
-- ABA CAMBER
--------------------------------------------------------------------
local secStance = createSection(pageCamber, "Stance & Suspension", 1)

local stanceTabRow = Instance.new("Frame")
stanceTabRow.Size = UDim2.new(1, 0, 0, 26)
stanceTabRow.BackgroundTransparency = 1
stanceTabRow.LayoutOrder = 1
stanceTabRow.Parent = secStance

local btnFrenteTab = Instance.new("TextButton")
btnFrenteTab.Size = UDim2.new(0.48, 0, 1, 0)
btnFrenteTab.BackgroundColor3 = C.tabActive
btnFrenteTab.Text = "FRENTE"
btnFrenteTab.Font = Enum.Font.GothamBold
btnFrenteTab.TextSize = 11
btnFrenteTab.TextColor3 = C.text
btnFrenteTab.Parent = stanceTabRow
uiCorner(btnFrenteTab, 6)

local btnTrasTab = Instance.new("TextButton")
btnTrasTab.Size = UDim2.new(0.48, 0, 1, 0)
btnTrasTab.Position = UDim2.new(0.52, 0, 0, 0)
btnTrasTab.BackgroundColor3 = C.tabInactive
btnTrasTab.Text = "TRÁS"
btnTrasTab.Font = Enum.Font.GothamBold
btnTrasTab.TextSize = 11
btnTrasTab.TextColor3 = C.dim
btnTrasTab.Parent = stanceTabRow
uiCorner(btnTrasTab, 6)

local stanceBoxes = {}
local function getStanceConfig(key)
	return (stanceActiveTab == "TRAS" and RearConfig or FrontConfig)[key]
end
local function setStanceConfig(key, val)
	if stanceActiveTab == "TRAS" then RearConfig[key] = val else FrontConfig[key] = val end
end
local function refreshStanceBoxes()
	for key, box in pairs(stanceBoxes) do
		box.Text = string.format("%.2f", getStanceConfig(key))
	end
end

btnFrenteTab.MouseButton1Click:Connect(function()
	stanceActiveTab = "FRENTE"
	btnFrenteTab.BackgroundColor3 = C.tabActive
	btnFrenteTab.TextColor3 = C.text
	btnTrasTab.BackgroundColor3 = C.tabInactive
	btnTrasTab.TextColor3 = C.dim
	refreshStanceBoxes()
end)
btnTrasTab.MouseButton1Click:Connect(function()
	stanceActiveTab = "TRAS"
	btnTrasTab.BackgroundColor3 = C.tabActive
	btnTrasTab.TextColor3 = C.text
	btnFrenteTab.BackgroundColor3 = C.tabInactive
	btnFrenteTab.TextColor3 = C.dim
	refreshStanceBoxes()
end)

stanceBoxes.PositionX = makeStanceRow(secStance, "Largura (X)", "PositionX", 2, getStanceConfig, setStanceConfig)
stanceBoxes.PositionY = makeStanceRow(secStance, "Altura (Y)", "PositionY", 3, getStanceConfig, setStanceConfig)
stanceBoxes.PositionZ = makeStanceRow(secStance, "Frente/Trás (Z)", "PositionZ", 4, getStanceConfig, setStanceConfig)
stanceBoxes.Camber = makeStanceRow(secStance, "Cambagem", "Camber", 5, getStanceConfig, setStanceConfig)
refreshStanceBoxes()
makeButton(secStance, "RESTAURAR ORIGINAL", 6, function()
	resetStance()
	refreshStanceBoxes()
end)

--------------------------------------------------------------------
-- ABA CÂMERA
--------------------------------------------------------------------
local secSpec = createSection(pageCamera, "Spectate", 1)

local specLabel = Instance.new("TextLabel")
specLabel.BackgroundTransparency = 1
specLabel.Size = UDim2.new(1, 0, 0, 18)
specLabel.Text = "Alvo: Nenhum"
specLabel.Font = Enum.Font.Gotham
specLabel.TextSize = 12
specLabel.TextColor3 = C.dim
specLabel.TextXAlignment = Enum.TextXAlignment.Left
specLabel.LayoutOrder = 1
specLabel.Parent = secSpec

local row = Instance.new("Frame")
row.Size = UDim2.new(1, 0, 0, 28)
row.BackgroundTransparency = 1
row.LayoutOrder = 2
row.Parent = secSpec

local function miniBtn(parent, text, x, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0.3, -4, 1, 0)
	b.Position = UDim2.new(x, 0, 0, 0)
	b.BackgroundColor3 = color or C.apply
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.TextColor3 = C.text
	b.Parent = parent
	uiCorner(b, 6)
	return b
end

local prevBtn = miniBtn(row, "< Prev", 0)
local nextBtn = miniBtn(row, "Next >", 0.35)
local stopBtn = miniBtn(row, "Parar", 0.7, C.red)

prevBtn.MouseButton1Click:Connect(function()
	local t = cycleSpectate(-1)
	specLabel.Text = t and ("Alvo: " .. t.Name) or "Alvo: Nenhum"
end)
nextBtn.MouseButton1Click:Connect(function()
	local t = cycleSpectate(1)
	specLabel.Text = t and ("Alvo: " .. t.Name) or "Alvo: Nenhum"
end)
stopBtn.MouseButton1Click:Connect(function()
	stopSpectate()
	specLabel.Text = "Alvo: Nenhum"
end)
makeButton(secSpec, "Espectar Eu", 3, function()
	if startSpectate(player) then
		specLabel.Text = "Alvo: " .. player.Name .. " (você)"
	end
end)

--------------------------------------------------------------------
-- ABA VISUAL
--------------------------------------------------------------------
local secShader = createSection(pageVisual, "Shaders (Leve)", 1)
makeToggle(secShader, "Ativar Shaders", false, 1, function(val)
	applyShaders(val)
end)
local info = Instance.new("TextLabel")
info.BackgroundTransparency = 1
info.Size = UDim2.new(1, 0, 0, 36)
info.Text = "Remove sombra, aumenta brilho e remove fog."
info.Font = Enum.Font.Gotham
info.TextSize = 11
info.TextColor3 = C.dim
info.TextWrapped = true
info.LayoutOrder = 2
info.Parent = secShader

--------------------------------------------------------------------
-- ABA HUD
--------------------------------------------------------------------
local secHud = createSection(pageHud, "Setas Mobile", 1)
makeToggle(secHud, "Mostrar Setas", true, 1, function(val)
	hudState.arrowsEnabled = val
	applyHudSettings()
end)
local sizeBox = makeInput(secHud, "Tamanho (40-140)", "80", 2)
local transBox = makeInput(secHud, "Transparência (0-1)", "0", 3)
makeButton(secHud, "Aplicar HUD", 4, function()
	local s = parseNum(sizeBox.Text)
	local t = parseNum(transBox.Text)
	if s then hudState.btnSize = math.clamp(s, 40, 140) end
	if t then hudState.transparency = math.clamp(t, 0, 1) end
	sizeBox.Text = tostring(hudState.btnSize)
	transBox.Text = string.format("%.2f", hudState.transparency)
	applyHudSettings()
end)

--------------------------------------------------------------------
-- ABA PAINEL
--------------------------------------------------------------------
local secUISize = createSection(pagePainel, "Tamanho da Interface", 1)
local uiScaleLabel = Instance.new("TextLabel")
uiScaleLabel.BackgroundTransparency = 1
uiScaleLabel.Size = UDim2.new(1, 0, 0, 18)
uiScaleLabel.Text = string.format("Escala atual: %.2f", uiState.scale)
uiScaleLabel.Font = Enum.Font.Gotham
uiScaleLabel.TextSize = 11
uiScaleLabel.TextColor3 = C.dim
uiScaleLabel.TextXAlignment = Enum.TextXAlignment.Left
uiScaleLabel.LayoutOrder = 1
uiScaleLabel.Parent = secUISize

local function setUIScale(newScale, center)
	newScale = math.clamp(newScale, 0.4, 1.5)
	uiState.scale = newScale
	TweenService:Create(uiScale, TweenInfo.new(0.18), { Scale = newScale }):Play()
	uiScaleLabel.Text = string.format("Escala atual: %.2f", newScale)
	if center then
		task.defer(function()
			task.wait(0.05)
			local vp = camera.ViewportSize
			local w = menu.AbsoluteSize.X
			local h = menu.AbsoluteSize.Y
			TweenService:Create(menu, TweenInfo.new(0.18), {
				Position = UDim2.new(0, (vp.X - w) / 2, 0, (vp.Y - h) / 2)
			}):Play()
		end)
	end
end

local sizeRow = Instance.new("Frame")
sizeRow.Size = UDim2.new(1, 0, 0, 26)
sizeRow.BackgroundTransparency = 1
sizeRow.LayoutOrder = 2
sizeRow.Parent = secUISize

local function sizeBtn(text, scale, x)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0.23, 0, 1, 0)
	b.Position = UDim2.new(x, 0, 0, 0)
	b.BackgroundColor3 = C.apply
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.TextColor3 = C.text
	b.Parent = sizeRow
	uiCorner(b, 6)
	b.MouseButton1Click:Connect(function() setUIScale(scale, true) end)
	return b
end
sizeBtn("P", 0.6, 0)
sizeBtn("M", 0.75, 0.256)
sizeBtn("G", 1.0, 0.512)
sizeBtn("XG", 1.25, 0.768)

local secFine = createSection(pagePainel, "Ajuste Fino", 2)
local fineBox = makeInput(secFine, "Escala (0.4-1.5)", string.format("%.2f", uiState.scale), 1)
makeButton(secFine, "Aplicar e Centralizar", 2, function()
	local v = parseNum(fineBox.Text)
	if v then setUIScale(v, true) end
end)

local secActions = createSection(pagePainel, "Ações", 3)
makeButton(secActions, "Centralizar na Tela", 1, function()
	local vp = camera.ViewportSize
	local w = menu.AbsoluteSize.X
	local h = menu.AbsoluteSize.Y
	TweenService:Create(menu, TweenInfo.new(0.2), {
		Position = UDim2.new(0, (vp.X - w) / 2, 0, (vp.Y - h) / 2)
	}):Play()
end)
makeToggle(secActions, "Travar Arraste", false, 2, function(val)
	uiState.locked = val
	if setMenuLock then setMenuLock(val) end
end)

task.defer(function()
	task.wait(0.15)
	local vp = camera.ViewportSize
	local w = menu.AbsoluteSize.X
	local h = menu.AbsoluteSize.Y
	if w > 0 and h > 0 then
		menu.Position = UDim2.new(0, (vp.X - w) / 2, 0, (vp.Y - h) / 2)
	end
end)

--------------------------------------------------------------------
-- MOBILE (arraste pelas setas se não travado)
--------------------------------------------------------------------
local isMobile = UserInputService.TouchEnabled

local function createMobileBtn(parent, text, right)
	local btn = Instance.new("TextButton")
	btn.Name = "Arrow_" .. text
	btn.Size = UDim2.new(0, hudState.btnSize, 0, hudState.btnSize)
	btn.Position = right and UDim2.new(0, hudState.btnSize + 12, 0, 0) or UDim2.new(0, 0, 0, 0)
	btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	btn.BackgroundTransparency = 0.35
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = math.floor(hudState.btnSize * 0.5)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextTransparency = hudState.transparency
	btn.AutoButtonColor = false
	btn.Active = true
	btn.Selectable = false
	btn.ZIndex = 20
	btn.Parent = parent
	uiCorner(btn, 8)
	uiStroke(btn, Color3.fromRGB(90, 90, 90), 1)
	table.insert(mobileButtons, { btn = btn, right = right })
	return btn
end

local function createLockBtn(parent)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 22, 0, 22)
	b.Position = UDim2.new(1, -11, 0, -11)
	b.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	b.BackgroundTransparency = 0.35
	b.Text = "L"
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.TextColor3 = C.text
	b.TextTransparency = hudState.transparency
	b.AutoButtonColor = false
	b.ZIndex = 25
	b.Parent = parent
	uiCorner(b, 6)
	uiStroke(b, Color3.fromRGB(90, 90, 90), 1)
	table.insert(lockButtons, b)
	return b
end

local function bindHold(btn, onPress, onRelease)
	local activeInputs = {}
	local pressedCount = 0

	local function doPress(input)
		if activeInputs[input] then return end
		activeInputs[input] = true
		pressedCount += 1
		if pressedCount == 1 then onPress() end
	end

	local function doRelease(input)
		if not activeInputs[input] then return end
		activeInputs[input] = nil
		pressedCount -= 1
		if pressedCount <= 0 then
			pressedCount = 0
			onRelease()
		end
	end

	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			doPress(input)
		end
	end)
	btn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			doRelease(input)
		end
	end)
	local conn = UserInputService.InputEnded:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) and activeInputs[input] then
			doRelease(input)
		end
	end)
	table.insert(connections, conn)
end

-- Motor
motorFrame = Instance.new("Frame")
motorFrame.Name = "MotorHUD"
motorFrame.Size = UDim2.new(0, 172, 0, 80)
motorFrame.Position = UDim2.new(0.5, -86, 1, -170)
motorFrame.BackgroundTransparency = 1
motorFrame.Visible = isMobile and hudState.arrowsEnabled
motorFrame.ZIndex = 15
motorFrame.Parent = sg

local setMotorLock, motorBeginDrag = makeDraggable(motorFrame)
local motorLockBtn = createLockBtn(motorFrame)
local motorLocked = false
motorLockBtn.MouseButton1Click:Connect(function()
	motorLocked = not motorLocked
	setMotorLock(motorLocked)
	motorLockBtn.Text = motorLocked and "X" or "L"
end)

local btnRe = createMobileBtn(motorFrame, "v", false)
local btnFrente = createMobileBtn(motorFrame, "^", true)

-- Arrasta pelas setas se NÃO estiver travado
btnFrente.InputBegan:Connect(function(input)
	if not motorLocked then motorBeginDrag(input) end
end)
btnRe.InputBegan:Connect(function(input)
	if not motorLocked then motorBeginDrag(input) end
end)

bindHold(btnFrente, function()
	if not currentCar then currentCar = findPlayerCar() end
	if not isPlayerInCar(currentCar) then return end
	if not motorState.enabled then
		motorState.enabled = true
		if setMotorToggle then setMotorToggle(true) end
	end
	motorState.currentDir = "Frente"
	aplicarMotor("Frente")
end, function()
	motorState.currentDir = "Parar"
	aplicarMotor("Parar")
end)

bindHold(btnRe, function()
	if not currentCar then currentCar = findPlayerCar() end
	if not isPlayerInCar(currentCar) then return end
	if not motorState.enabled then
		motorState.enabled = true
		if setMotorToggle then setMotorToggle(true) end
	end
	motorState.currentDir = "Re"
	aplicarMotor("Re")
end, function()
	motorState.currentDir = "Parar"
	aplicarMotor("Parar")
end)

-- Direção
steerFrame = Instance.new("Frame")
steerFrame.Name = "SteerHUD"
steerFrame.Size = UDim2.new(0, 172, 0, 80)
steerFrame.Position = UDim2.new(0.5, -86, 1, -85)
steerFrame.BackgroundTransparency = 1
steerFrame.Visible = isMobile and hudState.arrowsEnabled
steerFrame.ZIndex = 15
steerFrame.Parent = sg

local setSteerLock, steerBeginDrag = makeDraggable(steerFrame)
local steerLockBtn = createLockBtn(steerFrame)
local steerLocked = false
steerLockBtn.MouseButton1Click:Connect(function()
	steerLocked = not steerLocked
	setSteerLock(steerLocked)
	steerLockBtn.Text = steerLocked and "X" or "L"
end)

local btnEsq = createMobileBtn(steerFrame, "<", false)
local btnDir = createMobileBtn(steerFrame, ">", true)

btnEsq.InputBegan:Connect(function(input)
	if not steerLocked then steerBeginDrag(input) end
end)
btnDir.InputBegan:Connect(function(input)
	if not steerLocked then steerBeginDrag(input) end
end)

bindHold(btnEsq, function()
	if not currentCar then currentCar = findPlayerCar() end
	if not isPlayerInCar(currentCar) then return end
	if not steerState.enabled then
		steerState.enabled = true
		if setSteerToggle then setSteerToggle(true) end
	end
	steerState.isA = true
end, function()
	steerState.isA = false
end)

bindHold(btnDir, function()
	if not currentCar then currentCar = findPlayerCar() end
	if not isPlayerInCar(currentCar) then return end
	if not steerState.enabled then
		steerState.enabled = true
		if setSteerToggle then setSteerToggle(true) end
	end
	steerState.isD = true
end, function()
	steerState.isD = false
end)

applyHudSettings()

--------------------------------------------------------------------
-- Abrir / Fechar
--------------------------------------------------------------------
local menuOpen, animating = false, false

local function openMenu()
	if animating then return end
	animating = true
	menu.Visible = true
	uiScale.Scale = uiState.scale * 0.85
	menu.BackgroundTransparency = 0.35
	local t1 = TweenService:Create(uiScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = uiState.scale })
	local t2 = TweenService:Create(menu, TweenInfo.new(0.2), { BackgroundTransparency = 0 })
	t1:Play()
	t2:Play()
	t1.Completed:Connect(function() animating = false end)
end

local function closeMenu()
	if animating then return end
	animating = true
	local t1 = TweenService:Create(uiScale, TweenInfo.new(0.18), { Scale = uiState.scale * 0.85 })
	local t2 = TweenService:Create(menu, TweenInfo.new(0.16), { BackgroundTransparency = 0.4 })
	t1:Play()
	t2:Play()
	t1.Completed:Connect(function()
		menu.Visible = false
		menu.BackgroundTransparency = 0
		uiScale.Scale = uiState.scale
		animating = false
	end)
end

toggleBtn.MouseButton1Click:Connect(function()
	menuOpen = not menuOpen
	if menuOpen then
		toggleBtn.Text = "✕"
		openMenu()
	else
		toggleBtn.Text = "X • الانجراف"
		closeMenu()
	end
end)

--------------------------------------------------------------------
-- Teclado
--------------------------------------------------------------------
local conn1 = UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not isPlayerInCar(currentCar) then return end
	if input.KeyCode == Enum.KeyCode.W then
		motorState.currentDir = "Frente"
		aplicarMotor("Frente")
	elseif input.KeyCode == Enum.KeyCode.S then
		motorState.currentDir = "Re"
		aplicarMotor("Re")
	elseif input.KeyCode == Enum.KeyCode.A then
		steerState.isA = true
	elseif input.KeyCode == Enum.KeyCode.D then
		steerState.isD = true
	end
end)
table.insert(connections, conn1)

local conn2 = UserInputService.InputEnded:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.S then
		motorState.currentDir = "Parar"
		aplicarMotor("Parar")
	elseif input.KeyCode == Enum.KeyCode.A then
		steerState.isA = false
	elseif input.KeyCode == Enum.KeyCode.D then
		steerState.isD = false
	end
end)
table.insert(connections, conn2)

--------------------------------------------------------------------
-- Loop
--------------------------------------------------------------------
local updateTick, wasInCar = 0, false

local conn3 = RunService.RenderStepped:Connect(function(dt)
	if camState.spectating and camState.spectateTarget then
		local char = camState.spectateTarget.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart")
			local sub = hum or root
			if sub and camera.CameraSubject ~= sub then
				camera.CameraType = Enum.CameraType.Custom
				camera.CameraSubject = sub
			end
		end
	end

	updateTick += dt
	if updateTick >= 0.4 then
		updateTick = 0
		local found = findPlayerCar()
		if found ~= currentCar then
			currentCar = found
			driftOriginals = { front = nil, rear = nil }
			resetSteerOnExit()
			for name, ref in pairs(sectionRefs) do
				if name ~= "steer" and name ~= "motor" then
					ref.setToggle(false)
				end
			end
		end
		if found and found ~= lastStanceCar then
			lastStanceCar = found
			table.clear(originalOffsets)
			getWheelAttachments(found)
			FrontConfig = { PositionX = 0, PositionY = 0, PositionZ = 0, Camber = 0 }
			RearConfig  = { PositionX = 0, PositionY = 0, PositionZ = 0, Camber = 0 }
			refreshStanceBoxes()
		elseif not found then
			lastStanceCar = nil
		end
	end

	local inCar = isPlayerInCar(currentCar)
	if wasInCar and not inCar then
		resetSteerOnExit()
		if motorState.enabled then aplicarMotor("Parar") end
	end
	if (not wasInCar) and inCar then
		steerState.isA = false
		steerState.isD = false
		steerState.currentSteer = 0
		if steerState.enabled then applySteerAngle(0) end
	end
	wasInCar = inCar

	if steerState.enabled and currentCar and inCar then
		local steerDirection = 0
		if steerState.isA and not steerState.isD then
			steerDirection = -1
		elseif steerState.isD and not steerState.isA then
			steerDirection = 1
		end

		local slipAngle = 0
		if steerState.autoAlign then
			local root = currentCar:FindFirstChild("DriveSeat")
				or currentCar.PrimaryPart
				or currentCar:FindFirstChildWhichIsA("BasePart", true)
			if root then
				local vel = root.AssemblyLinearVelocity
				if vel.Magnitude > 5 then
					local localVel = root.CFrame:VectorToObjectSpace(vel)
					slipAngle = math.clamp(math.atan2(localVel.X, -localVel.Z), -steerState.maxAngle, steerState.maxAngle)
				end
			end
		end

		if steerDirection ~= 0 then
			steerState.currentSteer = math.clamp(
				steerState.currentSteer + (steerDirection * steerState.speed * dt),
				-steerState.maxAngle, steerState.maxAngle
			)
		else
			local target = steerState.autoAlign and slipAngle or 0
			if steerState.currentSteer < target then
				steerState.currentSteer = math.min(target, steerState.currentSteer + (steerState.speed * dt))
			elseif steerState.currentSteer > target then
				steerState.currentSteer = math.max(target, steerState.currentSteer - (steerState.speed * dt))
			end
		end
		applySteerAngle(steerState.currentSteer)
	elseif steerState.enabled and currentCar and not inCar then
		if steerState.currentSteer ~= 0 then
			steerState.currentSteer = 0
			applySteerAngle(0)
		end
	end
end)
table.insert(connections, conn3)

player.CharacterAdded:Connect(function()
	task.wait(0.4)
	applySpeed(playerState.speed)
	applyJump(playerState.jump)
	resetSteerOnExit()
	if not camState.spectating then restoreNormalCam() end
end)
