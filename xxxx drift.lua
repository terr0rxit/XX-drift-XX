-- ╔══════════════════════════════════════════════════════════════╗
-- ║                    Drift X  Controller                        ║
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
CRIADOR_CORES = {
	Maxx54        = Color3.fromRGB(160, 60, 220),
	Dzin          = Color3.fromRGB(80, 180, 255),
	Antipathicox  = Color3.fromRGB(220, 50, 50),
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
local fixCamEnabled = false
local shaderState = { enabled = false, brightness = 2.2, shadows = false, shadowQuality = 1.0, blur = 0, dof = false, bloom = 0, realistic = false, maxQuality = false, sky = "Padrao", skyboxId = "" }
local shaderInstances = {}
local originalLighting = {}
local hudState = {
	arrowsEnabled = true,
	btnSize = 80,
	transparency = 0,
}
local motorFrame, steerFrame
local tpMobileBtn
local tpLockBtn
local mobileButtons, lockButtons = {}, {}
local uiState = {
	scale = 0.75,
	locked = false,
}
local tpState = {
	savedCFrame = nil,
	keybind = Enum.KeyCode.T,
	waitingKey = false,
	mobileEnabled = false,
	btnSize = 60,
	transparency = 0,
}
--------------------------------------------------------------------
-- Utils (GLOBAIS pra liberar limite de 200 locais)
--------------------------------------------------------------------
function parseNum(str)
	return tonumber((tostring(str):gsub(",", ".")))
end
function uiCorner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = parent
end
function uiStroke(parent, color, thick)
	local s = Instance.new("UIStroke")
	s.Color = color or C.border
	s.Thickness = thick or 1
	s.Parent = parent
	return s
end
function makeDraggable(frame, handle)
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
-- POPUP DE CRÉDITOS (global)
--------------------------------------------------------------------
function criarPopupCreditos()
	local pg = Instance.new("ScreenGui")
	pg.Name = "DriftX_PopupCreditos"
	pg.ResetOnSpawn = false
	pg.IgnoreGuiInset = true
	pg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pg.DisplayOrder = 999
	pg.Parent = playerGui
	local popup = Instance.new("Frame")
	popup.Size = UDim2.new(0, 380, 0, 280)
	popup.Position = UDim2.new(0.5, -190, 0.5, -140)
	popup.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
	popup.BorderSizePixel = 0
	popup.Parent = pg
	uiCorner(popup, 12)
	uiStroke(popup, Color3.fromRGB(60, 60, 60), 1.5)
	local titulo = Instance.new("TextLabel")
	titulo.Size = UDim2.new(1, -20, 0, 30)
	titulo.Position = UDim2.new(0, 10, 0, 10)
	titulo.BackgroundTransparency = 1
	titulo.Text = "Drift X"
	titulo.Font = Enum.Font.GothamBold
	titulo.TextSize = 20
	titulo.TextColor3 = Color3.fromRGB(255, 255, 255)
	titulo.Parent = popup
	local msg = Instance.new("TextLabel")
	msg.Size = UDim2.new(1, -24, 0, 100)
	msg.Position = UDim2.new(0, 12, 0, 45)
	msg.BackgroundTransparency = 1
	msg.Text = "Olá! Este script é baseado em outros scripts, então não é 100% de um único criador. Ele foi montado para ser uma versão mais completa e mais objetiva para os seus propósitos."
	msg.Font = Enum.Font.Gotham
	msg.TextSize = 12
	msg.TextColor3 = Color3.fromRGB(210, 210, 210)
	msg.TextWrapped = true
	msg.TextYAlignment = Enum.TextYAlignment.Top
	msg.TextXAlignment = Enum.TextXAlignment.Left
	msg.Parent = popup
	local lblCria = Instance.new("TextLabel")
	lblCria.Size = UDim2.new(1, -24, 0, 18)
	lblCria.Position = UDim2.new(0, 12, 0, 152)
	lblCria.BackgroundTransparency = 1
	lblCria.Text = "Criadores principais:"
	lblCria.Font = Enum.Font.GothamBold
	lblCria.TextSize = 12
	lblCria.TextColor3 = Color3.fromRGB(180, 180, 180)
	lblCria.TextXAlignment = Enum.TextXAlignment.Left
	lblCria.Parent = popup
	local nomesFrame = Instance.new("Frame")
	nomesFrame.Size = UDim2.new(1, -24, 0, 26)
	nomesFrame.Position = UDim2.new(0, 12, 0, 172)
	nomesFrame.BackgroundTransparency = 1
	nomesFrame.Parent = popup
	local nl = Instance.new("UIListLayout")
	nl.FillDirection = Enum.FillDirection.Horizontal
	nl.Padding = UDim.new(0, 12)
	nl.VerticalAlignment = Enum.VerticalAlignment.Center
	nl.Parent = nomesFrame
	local function addNome(nome, cor)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(0, 110, 1, 0)
		l.Text = nome
		l.Font = Enum.Font.GothamBold
		l.TextSize = 14
		l.TextColor3 = Color3.fromRGB(255, 255, 255)
		l.Parent = nomesFrame
		local s = Instance.new("UIStroke")
		s.Color = cor
		s.Thickness = 2
		s.Parent = l
	end
	addNome("Maxx54", CRIADOR_CORES.Maxx54)
	addNome("Dzin", CRIADOR_CORES.Dzin)
	addNome("Antipathicox", CRIADOR_CORES.Antipathicox)
	local ok = Instance.new("TextButton")
	ok.Size = UDim2.new(0, 110, 0, 32)
	ok.Position = UDim2.new(0.5, -55, 1, -48)
	ok.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	ok.Text = "Ok"
	ok.Font = Enum.Font.GothamBold
	ok.TextSize = 14
	ok.TextColor3 = Color3.fromRGB(255, 255, 255)
	ok.AutoButtonColor = false
	ok.Parent = popup
	uiCorner(ok, 8)
	uiStroke(ok, Color3.fromRGB(80, 80, 80), 1)
	ok.MouseEnter:Connect(function()
		TweenService:Create(ok, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(55, 55, 55) }):Play()
	end)
	ok.MouseLeave:Connect(function()
		TweenService:Create(ok, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(35, 35, 35) }):Play()
	end)
	ok.MouseButton1Click:Connect(function()
		pg:Destroy()
	end)
end
criarPopupCreditos()
--------------------------------------------------------------------
-- CARRO (globais)
--------------------------------------------------------------------
function findPlayerCar()
	local carsFolder = workspace:FindFirstChild("Cars")
	if not carsFolder then return nil end
	local myName = player.Name
	for _, car in pairs(carsFolder:GetChildren()) do
		if car:IsA("Model") then
			if car.Name:lower():find(myName:lower()) then
				return car
			end
			local stats = car:FindFirstChild("Stats")
			if stats then
				local owner = stats:FindFirstChild("Owner")
				if owner and tostring(owner.Value):lower() == myName:lower() then
					return car
				end
			end
			local owner = car:FindFirstChild("Owner") or car:FindFirstChild("Player") or car:FindFirstChild("OwnerName")
			if owner and tostring(owner.Value):lower() == myName:lower() then
				return car
			end
			local seat = car:FindFirstChildWhichIsA("VehicleSeat", true) or car:FindFirstChildWhichIsA("Seat", true)
			if seat and seat.Occupant and seat.Occupant.Parent == player.Character then
				return car
			end
		end
	end
	return nil
end
function isPlayerInCar(car)
	if not car or not player.Character then return false end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not humanoid.SeatPart then return false end
	return humanoid.SeatPart:IsDescendantOf(car)
end
local WHEEL_PREFIXES = { front = { "FL", "FR" }, rear = { "RL", "RR" } }
function getWheels(car, group)
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
function readPhysics(wheel)
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
function applyDrift(group, friction, frictionWeight)
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
function revertDrift(group)
	if not currentCar or not driftOriginals[group] then return end
	local wheels = getWheels(currentCar, group)
	local o = driftOriginals[group]
	for _, w in ipairs(wheels) do
		w.CustomPhysicalProperties = PhysicalProperties.new(
			o.density, o.friction, o.elasticity, o.frictionWeight, o.elasticityWeight
		)
	end
end
function obterConstraints()
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
function aplicarMotor(direcao)
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
function applySteerAngle(angle)
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
function resetSteerOnExit()
	steerState.isA = false
	steerState.isD = false
	steerState.currentSteer = 0
	applySteerAngle(0)
end
--------------------------------------------------------------------
-- TELEPORTE (globais)
--------------------------------------------------------------------
function SavePosition()
	local car = findPlayerCar() or currentCar
	if car then
		tpState.savedCFrame = car:GetPivot()
		print("✅ Posição do carro salva!")
	else
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			tpState.savedCFrame = hrp.CFrame
			print("✅ Posição do personagem salva (carro não encontrado)")
		end
	end
end
function TeleportToSaved()
	if not tpState.savedCFrame then
		warn("Nenhuma posição salva!")
		return
	end
	local car = findPlayerCar()
	if not car then
		warn("Não encontrei seu carro em Workspace.Cars")
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.CFrame = tpState.savedCFrame end
		return
	end
	for _, part in pairs(car:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	local primary = car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart")
	if not primary then
		car:PivotTo(tpState.savedCFrame)
		return
	end
	car:PivotTo(tpState.savedCFrame)
	local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(primary, tweenInfo, { CFrame = tpState.savedCFrame })
	tween:Play()
	tween.Completed:Wait()
	pcall(function() car:PivotTo(tpState.savedCFrame) end)
end
--------------------------------------------------------------------
-- HUD (global)
--------------------------------------------------------------------
function applyHudSettings()
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
	if tpLockBtn then
		tpLockBtn.TextTransparency = tpState.transparency
		tpLockBtn.BackgroundTransparency = math.clamp(0.35 + tpState.transparency * 0.65, 0, 1)
		local st = tpLockBtn:FindFirstChildOfClass("UIStroke")
		if st then st.Transparency = tpState.transparency end
	end
	if tpMobileBtn then
		tpMobileBtn.BackgroundTransparency = math.clamp(0.35 + tpState.transparency * 0.65, 0, 1)
		tpMobileBtn.TextTransparency = tpState.transparency
		local st = tpMobileBtn:FindFirstChildOfClass("UIStroke")
		if st then st.Transparency = tpState.transparency end
	end
end
--------------------------------------------------------------------
-- JOGADOR (globais)
--------------------------------------------------------------------
function applySpeed(val)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = val end
end
function applyJump(val)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.JumpPower = val
		pcall(function() hum.JumpHeight = val / 2.5 end)
	end
end
--------------------------------------------------------------------
-- CAMBER (globais)
--------------------------------------------------------------------
local wheelNames = { "FL", "FR", "RL", "RR" }
function getWheelAttachments(car)
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
function applyStance()
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
function resetStance()
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
-- SPECTATE (globais)
--------------------------------------------------------------------
function getPlayerList(includeSelf)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if (includeSelf or p ~= player) and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			table.insert(list, p)
		end
	end
	return list
end
function restoreNormalCam()
	camera.CameraType = Enum.CameraType.Custom
	if player.Character then
		local h = player.Character:FindFirstChildOfClass("Humanoid")
		if h then camera.CameraSubject = h end
	end
end
function stopSpectate()
	camState.spectating = false
	camState.spectateTarget = nil
	restoreNormalCam()
end
function startSpectate(target)
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
function cycleSpectate(dir)
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
-- SHADERS (globais)
--------------------------------------------------------------------
function saveLighting()
	originalLighting = {
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		FogColor = Lighting.FogColor,
		GlobalShadows = Lighting.GlobalShadows,
		Technology = Lighting.Technology,
		ShadowSoftness = Lighting.ShadowSoftness,
		ExposureCompensation = Lighting.ExposureCompensation,
		EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
	}
end
function clearShaderInstances()
	for _, inst in ipairs(shaderInstances) do
		pcall(function() inst:Destroy() end)
	end
	shaderInstances = {}
	local oldSky = Lighting:FindFirstChild("CDT_Sky")
	if oldSky then oldSky:Destroy() end
	local oldAtmo = Lighting:FindFirstChild("CDT_Atmosphere")
	if oldAtmo then oldAtmo:Destroy() end
end
function createEffects()
	clearShaderInstances()
	local function add(cls, props)
		local inst = Instance.new(cls)
		for k, v in pairs(props) do inst[k] = v end
		inst.Parent = Lighting
		table.insert(shaderInstances, inst)
	end
	if (shaderState.blur or 0) > 0 then
		add("BlurEffect", { Size = shaderState.blur * 24 })
	end
	if shaderState.dof then
		add("DepthOfFieldEffect", { FarIntensity = 0.6, FocusDistance = 60, InFocusRadius = 40, NearIntensity = 0.2 })
	end
	if (shaderState.bloom or 0) > 0 then
		add("BloomEffect", { Intensity = shaderState.bloom, Size = 32, Threshold = 0.9 })
	end
	if shaderState.realistic then
		add("SunRaysEffect", { Intensity = 0.2, Spread = 1 })
		add("ColorCorrectionEffect", { Contrast = 0.08, Saturation = 0.06, TintColor = Color3.fromRGB(255, 250, 242) })
	end
	if shaderState.sky == "Custom" and shaderState.skyboxId ~= "" then
		local sky = Instance.new("Sky")
		local id = "rbxassetid://" .. tostring(shaderState.skyboxId)
		sky.SkyboxBk, sky.SkyboxDn, sky.SkyboxFt = id, id, id
		sky.SkyboxLf, sky.SkyboxRt, sky.SkyboxUp = id, id, id
		sky.CelestialBodiesShown = true
		sky.StarCount = 3000
		sky.Name = "CDT_Sky"
		sky.Parent = Lighting
	elseif shaderState.sky ~= "Padrao" then
		local atmo = Instance.new("Atmosphere")
		if shaderState.sky == "Limpo" then
			atmo.Density = 0.25
			atmo.Offset = 0.4
			atmo.Color = Color3.fromRGB(199, 217, 255)
			atmo.Decay = Color3.fromRGB(106, 132, 190)
			atmo.Glare = 0.2
			atmo.Haze = 0.4
		else
			atmo.Density = 0.35
			atmo.Offset = 0.6
			atmo.Color = Color3.fromRGB(220, 225, 235)
			atmo.Decay = Color3.fromRGB(140, 150, 170)
			atmo.Glare = 0.35
			atmo.Haze = 1.2
		end
		atmo.Name = "CDT_Atmosphere"
		atmo.Parent = Lighting
	end
end
function applyShaders(state)
	shaderState.enabled = state
	if state then
		if not next(originalLighting) then saveLighting() end
		Lighting.Brightness = shaderState.brightness
		Lighting.Ambient = Color3.fromRGB(90, 90, 90)
		Lighting.OutdoorAmbient = Color3.fromRGB(110, 110, 110)
		Lighting.FogEnd = 100000
		Lighting.FogStart = 0
		Lighting.GlobalShadows = shaderState.shadows
		pcall(function()
			Lighting.ShadowSoftness = math.clamp(shaderState.shadowQuality, 0, 1)
			Lighting.EnvironmentDiffuseScale = shaderState.shadowQuality
			Lighting.EnvironmentSpecularScale = shaderState.shadowQuality
			if shaderState.maxQuality then
				Lighting.Technology = Enum.Technology.Future
			elseif shaderState.realistic then
				Lighting.Technology = Enum.Technology.ShadowMap
			else
				Lighting.Technology = Enum.Technology.Compatibility
			end
			if shaderState.realistic then
				Lighting.ExposureCompensation = 0.15
			end
		end)
		createEffects()
	elseif next(originalLighting) then
		clearShaderInstances()
		local o = originalLighting
		Lighting.Brightness = o.Brightness
		Lighting.Ambient = o.Ambient
		Lighting.OutdoorAmbient = o.OutdoorAmbient
		Lighting.FogEnd = o.FogEnd
		Lighting.FogStart = o.FogStart
		Lighting.FogColor = o.FogColor
		Lighting.GlobalShadows = o.GlobalShadows
		pcall(function()
			Lighting.Technology = o.Technology
			Lighting.ShadowSoftness = o.ShadowSoftness
			Lighting.ExposureCompensation = o.ExposureCompensation
			Lighting.EnvironmentDiffuseScale = o.EnvironmentDiffuseScale
			Lighting.EnvironmentSpecularScale = o.EnvironmentSpecularScale
		end)
	end
end--------------------------------------------------------------------
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
toggleBtn.Text = "Drift X"
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 12
toggleBtn.TextColor3 = C.text
toggleBtn.Parent = sg
uiCorner(toggleBtn, 7)
local toggleStroke = uiStroke(toggleBtn, C.border, 1)
makeDraggable(toggleBtn)
local menu = Instance.new("Frame")
menu.Size = UDim2.new(0, 400, 0, 480)
menu.Position = UDim2.new(0.5, -200, 0.5, -240)
menu.BackgroundColor3 = C.bg
menu.Visible = false
menu.ClipsDescendants = true
menu.Parent = sg
uiCorner(menu, 10)
local menuStroke = uiStroke(menu, C.border, 1.5)
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
titleLabel.Text = "Drift X"
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
function createTab(name)
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
-- ORDEM: Carro, Teleporte(2º), ..., Créditos(último)
local pageCarro     = createTab("Carro")
local pageTeleporte = createTab("Teleporte")
local pagePlayer    = createTab("Jogador")
local pageCamber    = createTab("Camber")
local pageCamera    = createTab("Câmera")
local pageVisual    = createTab("Visual")
local pageHud       = createTab("HUD")
local pagePainel    = createTab("Painel")
local pageCreditos  = createTab("Créditos")
tabs["Carro"].BackgroundColor3 = C.tabActive
tabs["Carro"].TextColor3 = C.text
pages["Carro"].Visible = true
function createSection(parent, title, order)
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
local themedToggles, themedButtons = {}, {}
function makeToggle(parent, label, default, order, callback)
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
	local entry = { btn = btn, get = function() return state end }
	table.insert(themedToggles, entry)
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
function makeInput(parent, label, default, order)
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
function makeButton(parent, text, order, callback)
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
	table.insert(themedButtons, btn)
	btn.MouseButton1Click:Connect(callback)
	return btn
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
angleBox.FocusLost:Connect(function()
	local v = parseNum(angleBox.Text)
	if v then
		angleBox.Text = string.format("%.2f", v)
		steerState.maxAngle = math.abs(v)
		if steerState.enabled then
			steerState.currentSteer = math.clamp(steerState.currentSteer, -v, v)
		end
	else
		angleBox.Text = string.format("%.2f", steerState.maxAngle)
	end
end)
speedBox.FocusLost:Connect(function()
	local v = parseNum(speedBox.Text)
	if v then
		speedBox.Text = string.format("%.2f", v)
		steerState.speed = v
	else
		speedBox.Text = string.format("%.2f", steerState.speed)
	end
end)
local setSteerToggle = makeToggle(secSteer, "Ativar Direção", false, 3, function(val)
	steerState.enabled = val
	if not val then resetSteerOnExit() end
end)
makeToggle(secSteer, "Auto-Alinhar", false, 4, function(val)
	steerState.autoAlign = val
end)
sectionRefs.drift = { setToggle = setDriftToggle }
sectionRefs.motor = { setToggle = setMotorToggle }
sectionRefs.steer = { setToggle = setSteerToggle }
--------------------------------------------------------------------
-- ABA TELEPORTE
--------------------------------------------------------------------
local secTP = createSection(pageTeleporte, "Save + Teleporte", 1)
makeButton(secTP, "Salvar Posição", 1, function()
	SavePosition()
end)
makeButton(secTP, "Teleportar", 2, function()
	TeleportToSaved()
end)
local secKeybind = createSection(pageTeleporte, "Tecla de Atalho", 2)
local keybindBtn = Instance.new("TextButton")
keybindBtn.Size = UDim2.new(1, 0, 0, 28)
keybindBtn.BackgroundColor3 = C.apply
keybindBtn.Text = "Tecla: T"
keybindBtn.Font = Enum.Font.GothamBold
keybindBtn.TextSize = 12
keybindBtn.TextColor3 = C.text
keybindBtn.LayoutOrder = 1
keybindBtn.Parent = secKeybind
uiCorner(keybindBtn, 6)
table.insert(themedButtons, keybindBtn)
keybindBtn.MouseButton1Click:Connect(function()
	tpState.waitingKey = true
	keybindBtn.Text = "Pressione uma tecla..."
	keybindBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 20)
end)
local secMobileTP = createSection(pageTeleporte, "Botão Mobile", 3)
local setMobileTPToggle = makeToggle(secMobileTP, "Ativar Botão Mobile", false, 1, function(val)
	tpState.mobileEnabled = val
	if tpMobileBtn then
		tpMobileBtn.Visible = val
	end
end)
local tpSizeBox = makeInput(secMobileTP, "Tamanho (40-140)", "60", 2)
local tpTransBox = makeInput(secMobileTP, "Transparência (0-1)", "0", 3)
makeButton(secMobileTP, "Aplicar Botão Mobile", 4, function()
	local s = parseNum(tpSizeBox.Text)
	local t = parseNum(tpTransBox.Text)
	if s then tpState.btnSize = math.clamp(s, 40, 140) end
	if t then tpState.transparency = math.clamp(t, 0, 1) end
	tpSizeBox.Text = tostring(tpState.btnSize)
	tpTransBox.Text = string.format("%.2f", tpState.transparency)
	if tpMobileBtn then
		tpMobileBtn.Size = UDim2.new(0, tpState.btnSize, 0, tpState.btnSize)
		tpMobileBtn.BackgroundTransparency = math.clamp(0.35 + tpState.transparency * 0.65, 0, 1)
		tpMobileBtn.TextTransparency = tpState.transparency
		tpMobileBtn.TextSize = math.floor(tpState.btnSize * 0.4)
		local stroke = tpMobileBtn:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Transparency = tpState.transparency end
	end
	if tpLockBtn then
		tpLockBtn.TextTransparency = tpState.transparency
		tpLockBtn.BackgroundTransparency = math.clamp(0.35 + tpState.transparency * 0.65, 0, 1)
		local st = tpLockBtn:FindFirstChildOfClass("UIStroke")
		if st then st.Transparency = tpState.transparency end
	end
end)
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
function getStanceConfig(key)
	return (stanceActiveTab == "TRAS" and RearConfig or FrontConfig)[key]
end
function setStanceConfig(key, val)
	if stanceActiveTab == "TRAS" then RearConfig[key] = val else FrontConfig[key] = val end
end
function refreshStanceBoxes()
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
function makeStanceRow(parent, label, configKey, order)
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
		setStanceConfig(configKey, v)
		box.Text = string.format("%.2f", v)
		applyStance()
	end
	dec.MouseButton1Click:Connect(function() updateValue(getStanceConfig(configKey) - 0.05) end)
	inc.MouseButton1Click:Connect(function() updateValue(getStanceConfig(configKey) + 0.05) end)
	box.FocusLost:Connect(function()
		local v = parseNum(box.Text)
		if v then updateValue(v) else box.Text = string.format("%.2f", getStanceConfig(configKey)) end
	end)
	return box
end
stanceBoxes.PositionX = makeStanceRow(secStance, "Largura (X)", "PositionX", 2)
stanceBoxes.PositionY = makeStanceRow(secStance, "Altura (Y)", "PositionY", 3)
stanceBoxes.PositionZ = makeStanceRow(secStance, "Frente/Trás (Z)", "PositionZ", 4)
stanceBoxes.Camber = makeStanceRow(secStance, "Cambagem", "Camber", 5)
refreshStanceBoxes()
makeButton(secStance, "RESTAURAR ORIGINAL", 6, function()
	resetStance()
	refreshStanceBoxes()
end)--------------------------------------------------------------------
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
function miniBtn(parent, text, x, color)
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
	table.insert(themedButtons, b)
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
makeToggle(secSpec, "Destravar Câmera", false, 4, function(val)
	fixCamEnabled = val
	if val and camState.spectating then
		stopSpectate()
		specLabel.Text = "Alvo: Nenhum"
	end
end)
--------------------------------------------------------------------
-- ABA VISUAL
--------------------------------------------------------------------
local secShader = createSection(pageVisual, "Shaders", 1)
makeToggle(secShader, "Ativar Shaders", false, 1, function(val)
	applyShaders(val)
end)
local brightBox = makeInput(secShader, "Brilho (0-5)", "2.2", 2)
brightBox.FocusLost:Connect(function()
	local v = parseNum(brightBox.Text)
	if v then
		shaderState.brightness = math.clamp(v, 0, 5)
		if shaderState.enabled then applyShaders(true) end
	end
end)
makeToggle(secShader, "Sombras", false, 3, function(val)
	shaderState.shadows = val
	if shaderState.enabled then applyShaders(true) end
end)
local shadowQBox = makeInput(secShader, "Qualidade Sombra (0-1)", "1.0", 4)
shadowQBox.FocusLost:Connect(function()
	local v = parseNum(shadowQBox.Text)
	if v then
		shaderState.shadowQuality = math.clamp(v, 0, 1)
		if shaderState.enabled then applyShaders(true) end
	end
end)
local blurBox = makeInput(secShader, "Blur (0-1)", "0", 5)
blurBox.FocusLost:Connect(function()
	local v = parseNum(blurBox.Text)
	if v then
		shaderState.blur = math.clamp(v, 0, 1)
		if shaderState.enabled then applyShaders(true) end
	end
end)
makeToggle(secShader, "Desfoque Distancial", false, 6, function(val)
	shaderState.dof = val
	if shaderState.enabled then applyShaders(true) end
end)
local bloomBox = makeInput(secShader, "Destaque Brilho (0-2)", "0", 7)
bloomBox.FocusLost:Connect(function()
	local v = parseNum(bloomBox.Text)
	if v then
		shaderState.bloom = math.clamp(v, 0, 2)
		if shaderState.enabled then applyShaders(true) end
	end
end)
makeToggle(secShader, "Shaders Realista", false, 8, function(val)
	shaderState.realistic = val
	if shaderState.enabled then applyShaders(true) end
end)
makeToggle(secShader, "Qualidade Máxima", false, 9, function(val)
	shaderState.maxQuality = val
	if shaderState.enabled then applyShaders(true) end
end)
local secSky = createSection(pageVisual, "Céu", 2)
local skyOptions = { "Padrao", "Limpo", "Suave", "Custom" }
local skyIndex = 1
local skyBtn = makeButton(secSky, "Céu: Padrão", 1, function()
	skyIndex = (skyIndex % #skyOptions) + 1
	shaderState.sky = skyOptions[skyIndex]
	local names = { Padrao = "Padrão", Limpo = "Limpo", Suave = "Suave", Custom = "Custom (ID)" }
	skyBtn.Text = "Céu: " .. names[shaderState.sky]
	if shaderState.enabled then applyShaders(true) end
end)
local skyBox = makeInput(secSky, "Skybox ID", "", 2)
skyBox.FocusLost:Connect(function()
	shaderState.skyboxId = skyBox.Text
	if shaderState.enabled and shaderState.sky == "Custom" then applyShaders(true) end
end)
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
function setUIScale(newScale, center)
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
function sizeBtn(text, scale, x)
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
	table.insert(themedButtons, b)
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
local THEMES = {
	{ name = "Preto",       accent = Color3.fromRGB(30, 30, 30) },
	{ name = "Azul Escuro", accent = Color3.fromRGB(0, 60, 160) },
	{ name = "Vermelho",    accent = Color3.fromRGB(180, 30, 30) },
	{ name = "Verde",       accent = Color3.fromRGB(0, 160, 60) },
	{ name = "Amarelo",     accent = Color3.fromRGB(220, 190, 0) },
	{ name = "Roxo",        accent = Color3.fromRGB(120, 40, 200) },
	{ name = "Laranja",     accent = Color3.fromRGB(230, 120, 0) },
	{ name = "Ciano",       accent = Color3.fromRGB(0, 170, 190) },
	{ name = "Rosa",        accent = Color3.fromRGB(220, 60, 140) },
	{ name = "Branco",      accent = Color3.fromRGB(200, 200, 200) },
}
local themeSwatches = {}
function applyTheme(theme)
	C.tabActive = theme.accent
	C.on = theme.accent
	C.apply = Color3.new(theme.accent.R * 0.35, theme.accent.G * 0.35, theme.accent.B * 0.35)
	for n, b in pairs(tabs) do
		if pages[n].Visible then b.BackgroundColor3 = theme.accent end
	end
	for _, t in ipairs(themedToggles) do
		if t.get() then t.btn.BackgroundColor3 = theme.accent end
	end
	for _, b in ipairs(themedButtons) do
		if b ~= stopBtn then b.BackgroundColor3 = C.apply end
	end
	btnFrenteTab.BackgroundColor3 = theme.accent
	for _, data in ipairs(mobileButtons) do
		data.btn.BackgroundColor3 = Color3.new(theme.accent.R * 0.55, theme.accent.G * 0.55, theme.accent.B * 0.55)
		local s = data.btn:FindFirstChildOfClass("UIStroke")
		if s then s.Color = C.apply end
	end
	for _, lock in ipairs(lockButtons) do
		lock.BackgroundColor3 = Color3.new(theme.accent.R * 0.55, theme.accent.G * 0.55, theme.accent.B * 0.55)
	end
	if tpMobileBtn then
		tpMobileBtn.BackgroundColor3 = Color3.new(theme.accent.R * 0.7, theme.accent.G * 0.7, theme.accent.B * 0.7)
		local s = tpMobileBtn:FindFirstChildOfClass("UIStroke")
		if s then s.Color = theme.accent end
	end
	menuStroke.Color = Color3.new(theme.accent.R * 0.6, theme.accent.G * 0.6, theme.accent.B * 0.6)
	toggleStroke.Color = menuStroke.Color
	for i, sw in ipairs(themeSwatches) do
		local s = sw:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = (THEMES[i] == theme) and C.text or C.border
			s.Thickness = (THEMES[i] == theme) and 2 or 1
		end
	end
end
local secTheme = createSection(pagePainel, "Tema / Cor do Painel", 4)
local themeGrid = Instance.new("Frame")
themeGrid.Size = UDim2.new(1, 0, 0, 0)
themeGrid.AutomaticSize = Enum.AutomaticSize.Y
themeGrid.BackgroundTransparency = 1
themeGrid.LayoutOrder = 1
themeGrid.Parent = secTheme
local themeGridLayout = Instance.new("UIGridLayout")
themeGridLayout.CellSize = UDim2.new(0, 56, 0, 30)
themeGridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
themeGridLayout.Parent = themeGrid
for i, theme in ipairs(THEMES) do
	local sw = Instance.new("TextButton")
	sw.BackgroundColor3 = theme.accent
	sw.Text = theme.name
	sw.Font = Enum.Font.GothamBold
	sw.TextSize = 9
	sw.TextColor3 = Color3.fromRGB(235, 235, 235)
	sw.Parent = themeGrid
	uiCorner(sw, 6)
	local s = Instance.new("UIStroke")
	s.Color = C.border
	s.Parent = sw
	table.insert(themeSwatches, sw)
	sw.MouseButton1Click:Connect(function()
		applyTheme(theme)
	end)
end
--------------------------------------------------------------------
-- ABA CRÉDITOS
--------------------------------------------------------------------
local secCreditosInfo = createSection(pageCreditos, "Sobre", 1)
local credDesc = Instance.new("TextLabel")
credDesc.BackgroundTransparency = 1
credDesc.Size = UDim2.new(1, 0, 0, 70)
credDesc.Text = "Este script é baseado em outros scripts, então não é 100% de um único criador. Ele foi montado para ser uma versão mais completa e mais objetiva para os seus propósitos."
credDesc.Font = Enum.Font.Gotham
credDesc.TextSize = 11
credDesc.TextColor3 = C.dim
credDesc.TextWrapped = true
credDesc.TextYAlignment = Enum.TextYAlignment.Top
credDesc.TextXAlignment = Enum.TextXAlignment.Left
credDesc.LayoutOrder = 1
credDesc.Parent = secCreditosInfo
local secCreditosLista = createSection(pageCreditos, "Criadores Principais", 2)
function makeCreditoRow(parent, handle, cor, order)
	local r = Instance.new("Frame")
	r.Size = UDim2.new(1, 0, 0, 30)
	r.BackgroundTransparency = 1
	r.LayoutOrder = order
	r.Parent = parent
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 1, 0)
	l.Text = "@" .. handle
	l.Font = Enum.Font.GothamBold
	l.TextSize = 16
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = r
	local s = Instance.new("UIStroke")
	s.Color = cor
	s.Thickness = 2
	s.Parent = l
	return r
end
makeCreditoRow(secCreditosLista, "Maxx54", CRIADOR_CORES.Maxx54, 1)
makeCreditoRow(secCreditosLista, "Dzin", CRIADOR_CORES.Dzin, 2)
makeCreditoRow(secCreditosLista, "Antipathicox", CRIADOR_CORES.Antipathicox, 3)
task.defer(function()
	task.wait(0.15)
	local vp = camera.ViewportSize
	local w = menu.AbsoluteSize.X
	local h = menu.AbsoluteSize.Y
	if w > 0 and h > 0 then
		menu.Position = UDim2.new(0, (vp.X - w) / 2, 0, (vp.Y - h) / 2)
	end
end)--------------------------------------------------------------------
-- MOBILE
--------------------------------------------------------------------
local isMobile = UserInputService.TouchEnabled
function createMobileBtn(parent, text, right)
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
function createLockBtn(parent)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 22, 0, 22)
	b.Position = UDim2.new(1, -11, 0, -11)
	b.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	b.BackgroundTransparency = 0.35 + hudState.transparency * 0.65
	b.Text = "🔓"
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
function bindHold(btn, onPress, onRelease)
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
	motorLockBtn.Text = motorLocked and "🔒" or "🔓"
end)
local btnRe = createMobileBtn(motorFrame, "v", false)
local btnFrente = createMobileBtn(motorFrame, "^", true)
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
	steerLockBtn.Text = steerLocked and "🔒" or "🔓"
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
tpMobileBtn = Instance.new("TextButton")
tpMobileBtn.Name = "TPMobileBtn"
tpMobileBtn.Size = UDim2.new(0, tpState.btnSize, 0, tpState.btnSize)
tpMobileBtn.Position = UDim2.new(1, -80, 0.5, -30)
tpMobileBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
tpMobileBtn.BackgroundTransparency = 0.35
tpMobileBtn.Text = "TP"
tpMobileBtn.Font = Enum.Font.GothamBold
tpMobileBtn.TextSize = math.floor(tpState.btnSize * 0.4)
tpMobileBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
tpMobileBtn.TextTransparency = tpState.transparency
tpMobileBtn.Visible = false
tpMobileBtn.ZIndex = 20
tpMobileBtn.Parent = sg
uiCorner(tpMobileBtn, 12)
local tpStroke = uiStroke(tpMobileBtn, Color3.fromRGB(90, 90, 90), 1.5)
tpMobileBtn.MouseButton1Click:Connect(TeleportToSaved)
local setTPLock, tpBeginDrag = makeDraggable(tpMobileBtn)
local tpLocked = false
tpLockBtn = Instance.new("TextButton")
tpLockBtn.Size = UDim2.new(0, 22, 0, 22)
tpLockBtn.Position = UDim2.new(1, -11, 0, -11)
tpLockBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
tpLockBtn.BackgroundTransparency = 0.35 + tpState.transparency * 0.65
tpLockBtn.Text = "🔓"
tpLockBtn.Font = Enum.Font.GothamBold
tpLockBtn.TextSize = 12
tpLockBtn.TextColor3 = C.text
tpLockBtn.TextTransparency = tpState.transparency
tpLockBtn.ZIndex = 25
tpLockBtn.Parent = tpMobileBtn
uiCorner(tpLockBtn, 6)
uiStroke(tpLockBtn, Color3.fromRGB(90, 90, 90), 1)
tpLockBtn.MouseButton1Click:Connect(function()
	tpLocked = not tpLocked
	setTPLock(tpLocked)
	tpLockBtn.Text = tpLocked and "🔒" or "🔓"
end)
applyHudSettings()
--------------------------------------------------------------------
-- Abrir / Fechar
--------------------------------------------------------------------
local menuOpen, animating = false, false
function openMenu()
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
function closeMenu()
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
		toggleBtn.Text = "Drift X"
		closeMenu()
	end
end)
--------------------------------------------------------------------
-- Teclado
--------------------------------------------------------------------
local conn1 = UserInputService.InputBegan:Connect(function(input, gp)
	if tpState.waitingKey and input.UserInputType == Enum.UserInputType.Keyboard then
		tpState.keybind = input.KeyCode
		keybindBtn.Text = "Tecla: " .. input.KeyCode.Name
		keybindBtn.BackgroundColor3 = C.apply
		tpState.waitingKey = false
		return
	end
	if not tpState.waitingKey and input.KeyCode == tpState.keybind and not gp then
		TeleportToSaved()
	end
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
			if sub then
				if camera.CameraType ~= Enum.CameraType.Custom then
					camera.CameraType = Enum.CameraType.Custom
				end
				if camera.CameraSubject ~= sub then
					camera.CameraSubject = sub
				end
			end
		else
			stopSpectate()
		end
	end
	if fixCamEnabled and not camState.spectating then
		if camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end
		local char = player.Character
		local h = char and char:FindFirstChildOfClass("Humanoid")
		if h and camera.CameraSubject ~= h then
			camera.CameraSubject = h
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
