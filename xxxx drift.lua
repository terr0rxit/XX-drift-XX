-- ╔══════════════════════════════════════════════════════════════╗
-- ║                    Drift X  Controller                        ║
-- ║              Carro | HUD | Painel | Jogadores                 ║
-- ╚══════════════════════════════════════════════════════════════╝
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local HttpService      = game:GetService("HttpService")

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
	sliderBg = Color3.fromRGB(30, 30, 30),
	sliderFill = Color3.fromRGB(0, 160, 65),
	sliderKnob = Color3.fromRGB(240, 240, 240),
}

local connections = {}
local currentCar = nil
local driftOriginals = { front = nil, rear = nil }
local motorState = { enabled = false, maxVel = 100, maxTorque = 50000, currentDir = "Parar" }
local steerState = { enabled = false, autoAlign = false, maxAngle = 0.4, speed = 0.5, currentSteer = 0, isA = false, isD = false }
local hudState = { arrowsEnabled = true, btnSize = 80, transparency = 0 }
local motorFrame, steerFrame
local mobileButtons, lockButtons = {}, {}
local uiState = { scale = 0.75, locked = false }
local customCarName = ""

--------------------------------------------------------------------
-- Firebase Online (mesmo método do Car Customizer)
-- Usa request do executor (syn.request / http_request / request)
--------------------------------------------------------------------
local FIREBASE_LIVE = "https://online-5f25a-default-rtdb.firebaseio.com/driftx/live"
local ONLINE_TIMEOUT = 240 -- segundos sem update = offline

local lastHttpError = ""
local function hasHttpRequest()
	return (syn and syn.request) or (http and http.request) or http_request or request
end

local function httpRequest(opts)
	local req = hasHttpRequest()
	if not req then
		lastHttpError = "sem request — ative HttpRequest no executor"
		return { StatusCode = 0, Body = "", Error = lastHttpError, Success = false }
	end
	local ok, r = pcall(req, opts)
	if not ok then
		lastHttpError = tostring(r)
		return { StatusCode = 0, Body = "", Error = lastHttpError, Success = false }
	end
	if type(r) ~= "table" then
		lastHttpError = "resposta invalida do request"
		return { StatusCode = 0, Body = "", Error = lastHttpError, Success = false }
	end
	local code = r.StatusCode or r.Status or r.status_code or r.status or 0
	local body = r.Body or r.body or ""
	local success = r.Success == true or tonumber(code) == 200 or tonumber(code) == 201
	if not success then
		lastHttpError = "HTTP " .. tostring(code) .. " " .. tostring(body):sub(1, 80)
	else
		lastHttpError = ""
	end
	return {
		StatusCode = tonumber(code) or 0,
		Body = tostring(body),
		Success = success,
		Error = lastHttpError,
	}
end


local sharedConfig = {
	friction = 0.30,
	weight = 1.00,
	maxVel = 100,
	maxTorque = 50000,
	maxAngle = 0.40,
	steerSpeed = 0.50,
	driftOn = false,
	motorOn = false,
	steerOn = false,
	autoAlign = false,
	carDisplayName = "",
}

--------------------------------------------------------------------
-- Utils
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
-- Broadcast config (Firebase)
--------------------------------------------------------------------
local lastPublishOk = false
local lastPublishMsg = "ainda não publicou"

function publishConfig()
	local car = currentCar or findPlayerCar()
	local displayName = customCarName
	if displayName == "" and car then
		displayName = car.Name
	elseif displayName == "" then
		displayName = "Sem carro"
	end
	sharedConfig.carDisplayName = displayName

	local data = {
		name = player.Name,
		userId = player.UserId,
		carName = displayName,
		config = {
			friction = sharedConfig.friction,
			weight = sharedConfig.weight,
			maxVel = sharedConfig.maxVel,
			maxTorque = sharedConfig.maxTorque,
			maxAngle = sharedConfig.maxAngle,
			steerSpeed = sharedConfig.steerSpeed,
			driftOn = sharedConfig.driftOn,
			motorOn = sharedConfig.motorOn,
			steerOn = sharedConfig.steerOn,
			autoAlign = sharedConfig.autoAlign,
			carDisplayName = displayName,
		},
		jobId = game.JobId,
		timestamp = os.time(),
	}

	task.spawn(function()
		local ok, res = pcall(function()
			return httpRequest({
				Url = FIREBASE_LIVE .. "/" .. tostring(player.UserId) .. ".json",
				Method = "PUT",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode(data),
			})
		end)
		if ok and res and res.Success then
			lastPublishOk = true
			lastPublishMsg = "online ✓ (" .. os.date("%H:%M:%S") .. ")"
		else
			lastPublishOk = false
			lastPublishMsg = "falha: " .. (lastHttpError ~= "" and lastHttpError or "desconhecida")
			warn("[DriftX Online] " .. lastPublishMsg)
		end
	end)
end

function clearPublishedConfig()
	task.spawn(function()
		pcall(function()
			httpRequest({
				Url = FIREBASE_LIVE .. "/" .. tostring(player.UserId) .. ".json",
				Method = "DELETE",
			})
		end)
	end)
end

function fetchLiveConfigs()
	if not hasHttpRequest() then
		lastHttpError = "sem request — ative HttpRequest no executor"
		return {}, lastHttpError
	end
	local r = httpRequest({
		Url = FIREBASE_LIVE .. ".json",
		Method = "GET",
		Headers = { ["Content-Type"] = "application/json" },
	})
	if not r or not r.Success then
		return {}, (r and r.Error) or lastHttpError or "GET falhou"
	end
	local body = r.Body or ""
	if body == "" or body == "null" then return {}, nil end
	local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
	if not ok or type(data) ~= "table" then
		return {}, "JSON inválido"
	end
	return data, nil
end

function scanOnlineUsers()
	local list = {}
	local lives, err = fetchLiveConfigs()
	local now = os.time()
	local playersInServer = {}
	for _, p in ipairs(Players:GetPlayers()) do
		playersInServer[p.UserId] = p
		playersInServer[tostring(p.UserId)] = p
	end

	if type(lives) ~= "table" then
		return list, err or "sem dados"
	end

	for _, live in pairs(lives) do
		if type(live) == "table" and live.userId then
			local age = now - (tonumber(live.timestamp) or 0)
			if age <= ONLINE_TIMEOUT then
				local uid = live.userId
				local p = playersInServer[uid] or playersInServer[tostring(uid)] or playersInServer[tonumber(uid)]
				if p or tonumber(uid) == player.UserId or tostring(uid) == tostring(player.UserId) then
					local cfg = live.config
					if type(cfg) ~= "table" then cfg = {} end
					table.insert(list, {
						playerName = tostring(live.name or (p and p.Name) or "?"),
						userId = uid,
						carName = tostring(live.carName or cfg.carDisplayName or "—"),
						config = cfg,
						age = age,
						isSelf = (tonumber(uid) == player.UserId),
					})
				end
			end
		end
	end

	table.sort(list, function(a, b)
		if a.isSelf ~= b.isSelf then return a.isSelf end
		return (a.playerName or "") < (b.playerName or "")
	end)
	return list, err
end

--------------------------------------------------------------------
-- CARRO (core CDT)
--------------------------------------------------------------------
function findPlayerCar()
	if player.Character then
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart then
			local obj = hum.SeatPart
			while obj and obj ~= workspace do
				if obj.Parent and obj.Parent.Name == "Cars" then
					return obj
				end
				local stats = obj:FindFirstChild("Stats")
				if stats and stats:FindFirstChild("Owner") then
					return obj
				end
				obj = obj.Parent
			end
		end
	end
	local carsFolder = workspace:FindFirstChild("Cars")
	if not carsFolder then return nil end
	local myName = player.Name
	for _, car in ipairs(carsFolder:GetChildren()) do
		if car:IsA("Model") then
			local stats = car:FindFirstChild("Stats")
			if stats then
				local owner = stats:FindFirstChild("Owner")
				if owner then
					local v = owner.Value
					if v == myName or v == player or v == player.UserId or tostring(v):lower() == myName:lower() then
						return car
					end
				end
			end
			if car.Name:lower():find(myName:lower(), 1, true) then
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
	if not player.Character then return false end
	local hum = player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or not hum.SeatPart then return false end
	if car then
		return hum.SeatPart:IsDescendantOf(car)
	end
	local obj = hum.SeatPart
	while obj and obj ~= workspace do
		if obj.Parent and obj.Parent.Name == "Cars" then return true end
		if obj:FindFirstChild("Stats") then return true end
		obj = obj.Parent
	end
	return false
end

local WHEEL_PREFIXES = { front = { "FL", "FR" }, rear = { "RL", "RR" } }

function getWheels(car, group)
	local result = {}
	if not car then return result end
	for _, obj in ipairs(car:GetChildren()) do
		for _, pfx in ipairs(WHEEL_PREFIXES[group]) do
			if obj.Name == pfx or obj.Name:match("^" .. pfx .. "_%d+$") then
				local w = obj:FindFirstChild("Wheel")
				if w and w:IsA("BasePart") then
					table.insert(result, w)
				end
				local sw = obj:FindFirstChild("SecondaryWheel")
				if sw and sw:IsA("BasePart") then
					table.insert(result, sw)
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
-- HUD
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
		clearPublishedConfig()
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
local refreshPlayersList

function createTab(name)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 78, 0, 26)
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
		if name == "Jogadores" and refreshPlayersList then
			refreshPlayersList()
		end
	end)
	return page
end

local pageCarro     = createTab("Carro")
local pageHud       = createTab("HUD")
local pagePainel    = createTab("Painel")
local pageJogadores = createTab("Jogadores")

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

local themedButtons = {}

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
	box.ClearTextOnFocus = false
	box.Parent = row
	uiCorner(box, 5)
	uiStroke(box, C.border, 1)
	return box
end

-- Barra limitada + digitar SEM limite
function makeSliderWithInput(parent, label, minV, maxV, default, order, decimals)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 48)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local top = Instance.new("Frame")
	top.Size = UDim2.new(1, 0, 0, 22)
	top.BackgroundTransparency = 1
	top.Parent = row

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(0.45, 0, 1, 0)
	lbl.Text = label
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 11
	lbl.TextColor3 = C.dim
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = top

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0, 90, 0, 20)
	box.Position = UDim2.new(1, -90, 0.5, -10)
	box.BackgroundColor3 = C.inputBg
	box.Text = string.format("%." .. (decimals or 2) .. "f", default)
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 11
	box.TextColor3 = C.text
	box.ClearTextOnFocus = false
	box.Parent = top
	uiCorner(box, 5)
	uiStroke(box, C.border, 1)

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 10)
	track.Position = UDim2.new(0, 0, 0, 30)
	track.BackgroundColor3 = C.sliderBg
	track.BorderSizePixel = 0
	track.Parent = row
	uiCorner(track, 5)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = C.sliderFill
	fill.BorderSizePixel = 0
	fill.Parent = track
	uiCorner(fill, 5)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 16, 0, 16)
	knob.Position = UDim2.new(0, -8, 0.5, -8)
	knob.BackgroundColor3 = C.sliderKnob
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track
	uiCorner(knob, 8)
	uiStroke(knob, C.border, 1)

	local value = default
	local dragging = false
	local updating = false

	local function fmt(v)
		return string.format("%." .. (decimals or 2) .. "f", v)
	end

	local function setSliderVisual(v)
		local clamped = math.clamp(v, minV, maxV)
		local pct = (clamped - minV) / math.max(maxV - minV, 1e-9)
		fill.Size = UDim2.new(pct, 0, 1, 0)
		knob.Position = UDim2.new(pct, -8, 0.5, -8)
	end

	local function setValue(v, fromBox)
		value = v
		updating = true
		if not fromBox then
			box.Text = fmt(v)
		end
		setSliderVisual(v)
		updating = false
	end

	setValue(default, false)

	local function fromInputX(x)
		local absPos = track.AbsolutePosition.X
		local absSize = track.AbsoluteSize.X
		if absSize <= 0 then return end
		local pct = math.clamp((x - absPos) / absSize, 0, 1)
		local v = minV + pct * (maxV - minV)
		setValue(v, false)
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromInputX(input.Position.X)
		end
	end)
	knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)

	local conn = UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			fromInputX(input.Position.X)
		end
	end)
	table.insert(connections, conn)

	local conn2 = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	table.insert(connections, conn2)

	box.FocusLost:Connect(function()
		if updating then return end
		local v = parseNum(box.Text)
		if v then
			setValue(v, true)
			box.Text = fmt(v)
		else
			box.Text = fmt(value)
		end
	end)

	return {
		get = function() return value end,
		set = function(v) setValue(v, false) end,
		box = box,
	}
end

function makeValueInput(parent, label, default, order, decimals)
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
	box.Text = string.format("%." .. (decimals or 2) .. "f", default)
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 11
	box.TextColor3 = C.text
	box.ClearTextOnFocus = false
	box.Parent = row
	uiCorner(box, 5)
	uiStroke(box, C.border, 1)

	local value = default
	box.FocusLost:Connect(function()
		local v = parseNum(box.Text)
		if v then
			value = v
			box.Text = string.format("%." .. (decimals or 2) .. "f", v)
		else
			box.Text = string.format("%." .. (decimals or 2) .. "f", value)
		end
	end)

	return {
		get = function()
			local v = parseNum(box.Text)
			if v then value = v end
			return value
		end,
		set = function(v)
			value = v
			box.Text = string.format("%." .. (decimals or 2) .. "f", v)
		end,
		box = box,
	}
end

--------------------------------------------------------------------
-- ABA CARRO
--------------------------------------------------------------------
local secNome = createSection(pageCarro, "Nome do carro (online)", 0)
local carNameBox = makeInput(secNome, "Nome exibido", "", 1)
carNameBox.PlaceholderText = "Vazio = nome original"
carNameBox.FocusLost:Connect(function()
	customCarName = carNameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	sharedConfig.carDisplayName = customCarName
	publishConfig()
end)

local secDrift = createSection(pageCarro, "Drift", 1)
local frictionCtrl = makeSliderWithInput(secDrift, "Friction", 0.01, 10, 0.30, 1, 2)
local weightCtrl   = makeSliderWithInput(secDrift, "Weight", 0.10, 50, 1.00, 2, 2)

makeButton(secDrift, "Inserir Config Drift", 3, function()
	if not currentCar then currentCar = findPlayerCar() end
	local f = frictionCtrl.get()
	local fw = weightCtrl.get()
	sharedConfig.friction = f
	sharedConfig.weight = fw
	sharedConfig.driftOn = true
	local ok1 = applyDrift("front", f, fw)
	local ok2 = applyDrift("rear", f, fw)
	publishConfig()
	print(ok1 and ok2 and "✅ Drift aplicado" or "⚠️ Drift: carro/rodas não encontrados")
end)

local secMotor = createSection(pageCarro, "Motor", 2)
local velCtrl    = makeSliderWithInput(secMotor, "Velocidade", 10, 1000, 100, 1, 0)
local torqueCtrl = makeSliderWithInput(secMotor, "Torque", 1000, 200000, 50000, 2, 0)

makeButton(secMotor, "Inserir Config Motor", 3, function()
	if not currentCar then currentCar = findPlayerCar() end
	motorState.maxVel = velCtrl.get()
	motorState.maxTorque = torqueCtrl.get()
	motorState.enabled = true
	sharedConfig.maxVel = motorState.maxVel
	sharedConfig.maxTorque = motorState.maxTorque
	sharedConfig.motorOn = true
	publishConfig()
	print("✅ Motor configurado (W/S ou setas mobile)")
end)

local secSteer = createSection(pageCarro, "Direção", 3)
local angleCtrl = makeValueInput(secSteer, "Max Angle", 0.40, 1, 2)
local speedCtrl = makeSliderWithInput(secSteer, "Speed", 0.05, 3.00, 0.50, 2, 2)

makeButton(secSteer, "Inserir Config Direção", 3, function()
	if not currentCar then currentCar = findPlayerCar() end
	steerState.maxAngle = math.abs(angleCtrl.get())
	steerState.speed = speedCtrl.get()
	steerState.enabled = true
	sharedConfig.maxAngle = steerState.maxAngle
	sharedConfig.steerSpeed = steerState.speed
	sharedConfig.steerOn = true
	publishConfig()
	print("✅ Direção configurada (A/D ou setas mobile)")
end)

makeButton(secSteer, "Inserir Config Completa", 4, function()
	if not currentCar then currentCar = findPlayerCar() end
	local f, fw = frictionCtrl.get(), weightCtrl.get()
	sharedConfig.friction, sharedConfig.weight = f, fw
	sharedConfig.driftOn = true
	applyDrift("front", f, fw)
	applyDrift("rear", f, fw)

	motorState.maxVel = velCtrl.get()
	motorState.maxTorque = torqueCtrl.get()
	motorState.enabled = true
	sharedConfig.maxVel = motorState.maxVel
	sharedConfig.maxTorque = motorState.maxTorque
	sharedConfig.motorOn = true

	steerState.maxAngle = math.abs(angleCtrl.get())
	steerState.speed = speedCtrl.get()
	steerState.enabled = true
	sharedConfig.maxAngle = steerState.maxAngle
	sharedConfig.steerSpeed = steerState.speed
	sharedConfig.steerOn = true
	publishConfig()
	print("✅ Config completa inserida")
end)

--------------------------------------------------------------------
-- ABA HUD
--------------------------------------------------------------------
local secHud = createSection(pageHud, "Setas Mobile", 1)
local arrowsOn = true
local arrowsBtn = makeButton(secHud, "Mostrar Setas: ON", 1, function()
	arrowsOn = not arrowsOn
	hudState.arrowsEnabled = arrowsOn
	arrowsBtn.Text = "Mostrar Setas: " .. (arrowsOn and "ON" or "OFF")
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

local lockDrag = false
local lockBtn = makeButton(secActions, "Travar Arraste: OFF", 2, function()
	lockDrag = not lockDrag
	uiState.locked = lockDrag
	if setMenuLock then setMenuLock(lockDrag) end
	lockBtn.Text = "Travar Arraste: " .. (lockDrag and "ON" or "OFF")
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
	C.sliderFill = theme.accent
	C.apply = Color3.new(theme.accent.R * 0.35, theme.accent.G * 0.35, theme.accent.B * 0.35)
	for n, b in pairs(tabs) do
		if pages[n].Visible then b.BackgroundColor3 = theme.accent end
	end
	for _, b in ipairs(themedButtons) do
		b.BackgroundColor3 = C.apply
	end
	for _, data in ipairs(mobileButtons) do
		data.btn.BackgroundColor3 = Color3.new(theme.accent.R * 0.55, theme.accent.G * 0.55, theme.accent.B * 0.55)
		local s = data.btn:FindFirstChildOfClass("UIStroke")
		if s then s.Color = C.apply end
	end
	for _, lock in ipairs(lockButtons) do
		lock.BackgroundColor3 = Color3.new(theme.accent.R * 0.55, theme.accent.G * 0.55, theme.accent.B * 0.55)
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
-- ABA JOGADORES
--------------------------------------------------------------------
local secOnline = createSection(pageJogadores, "Usuários Online (mesmo servidor)", 1)

local onlineStatus = Instance.new("TextLabel")
onlineStatus.BackgroundTransparency = 1
onlineStatus.Size = UDim2.new(1, 0, 0, 18)
onlineStatus.Text = "Atualizando..."
onlineStatus.Font = Enum.Font.Gotham
onlineStatus.TextSize = 11
onlineStatus.TextColor3 = C.dim
onlineStatus.TextXAlignment = Enum.TextXAlignment.Left
onlineStatus.LayoutOrder = 1
onlineStatus.Parent = secOnline

local playersListFrame = Instance.new("Frame")
playersListFrame.Size = UDim2.new(1, 0, 0, 0)
playersListFrame.AutomaticSize = Enum.AutomaticSize.Y
playersListFrame.BackgroundTransparency = 1
playersListFrame.LayoutOrder = 2
playersListFrame.Parent = secOnline

local playersListLayout = Instance.new("UIListLayout")
playersListLayout.SortOrder = Enum.SortOrder.LayoutOrder
playersListLayout.Padding = UDim.new(0, 6)
playersListLayout.Parent = playersListFrame

local secConfigView = createSection(pageJogadores, "Config Selecionada", 2)
local configPreview = Instance.new("TextLabel")
configPreview.BackgroundTransparency = 1
configPreview.Size = UDim2.new(1, 0, 0, 120)
configPreview.Text = "Selecione um jogador e clique em Ver Config"
configPreview.Font = Enum.Font.Gotham
configPreview.TextSize = 11
configPreview.TextColor3 = C.dim
configPreview.TextWrapped = true
configPreview.TextYAlignment = Enum.TextYAlignment.Top
configPreview.TextXAlignment = Enum.TextXAlignment.Left
configPreview.LayoutOrder = 1
configPreview.Parent = secConfigView

local selectedRemoteConfig = nil

makeButton(secConfigView, "Copiar Config para Mim", 2, function()
	if not selectedRemoteConfig then
		configPreview.Text = "Nenhuma config selecionada."
		return
	end
	local cfg = selectedRemoteConfig
	if cfg.friction then frictionCtrl.set(cfg.friction) end
	if cfg.weight then weightCtrl.set(cfg.weight) end
	if cfg.maxVel then velCtrl.set(cfg.maxVel) end
	if cfg.maxTorque then torqueCtrl.set(cfg.maxTorque) end
	if cfg.maxAngle then angleCtrl.set(cfg.maxAngle) end
	if cfg.steerSpeed then speedCtrl.set(cfg.steerSpeed) end

	sharedConfig.friction = frictionCtrl.get()
	sharedConfig.weight = weightCtrl.get()
	sharedConfig.maxVel = velCtrl.get()
	sharedConfig.maxTorque = torqueCtrl.get()
	sharedConfig.maxAngle = angleCtrl.get()
	sharedConfig.steerSpeed = speedCtrl.get()

	if not currentCar then currentCar = findPlayerCar() end
	applyDrift("front", sharedConfig.friction, sharedConfig.weight)
	applyDrift("rear", sharedConfig.friction, sharedConfig.weight)
	sharedConfig.driftOn = true

	motorState.maxVel = sharedConfig.maxVel
	motorState.maxTorque = sharedConfig.maxTorque
	motorState.enabled = true
	sharedConfig.motorOn = true

	steerState.maxAngle = math.abs(sharedConfig.maxAngle)
	steerState.speed = sharedConfig.steerSpeed
	steerState.enabled = true
	sharedConfig.steerOn = true

	publishConfig()
	configPreview.Text = configPreview.Text .. "\n\n✅ Config copiada e aplicada!"
end)

function clearPlayersList()
	for _, child in ipairs(playersListFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

function formatConfigText(cfg, playerName, carName)
	local lines = {
		"Jogador: " .. tostring(playerName),
		"Carro: " .. tostring(carName),
		"────────────",
		string.format("Friction: %.4g", cfg.friction or 0),
		string.format("Weight: %.4g", cfg.weight or 0),
		string.format("Vel Motor: %.4g", cfg.maxVel or 0),
		string.format("Torque: %.4g", cfg.maxTorque or 0),
		string.format("Max Angle: %.4g", cfg.maxAngle or 0),
		string.format("Steer Speed: %.4g", cfg.steerSpeed or 0),
	}
	return table.concat(lines, "\n")
end

refreshPlayersList = function()
	clearPlayersList()
	local reqOk = hasHttpRequest() ~= nil
	onlineStatus.Text = reqOk and ("Buscando... | " .. lastPublishMsg) or "⚠️ Ative HttpRequest no executor!"

	task.spawn(function()
		publishConfig()
		task.wait(0.4)
		local list, err = scanOnlineUsers()
		task.defer(function()
			clearPlayersList()
			if err and #list == 0 then
				onlineStatus.Text = "Erro: " .. tostring(err)
			elseif #list == 0 then
				onlineStatus.Text = "Nenhum Drift X online neste servidor | " .. lastPublishMsg
			else
				onlineStatus.Text = tostring(#list) .. " online | " .. lastPublishMsg
			end

			for i, entry in ipairs(list) do
				local card = Instance.new("Frame")
				card.Size = UDim2.new(1, 0, 0, 56)
				card.BackgroundColor3 = entry.isSelf and Color3.fromRGB(20, 40, 20) or C.inputBg
				card.LayoutOrder = i
				card.Parent = playersListFrame
				uiCorner(card, 6)
				uiStroke(card, entry.isSelf and C.green or C.border, 1)

				local nameLbl = Instance.new("TextLabel")
				nameLbl.BackgroundTransparency = 1
				nameLbl.Size = UDim2.new(1, -90, 0, 20)
				nameLbl.Position = UDim2.new(0, 8, 0, 6)
				nameLbl.Text = entry.playerName .. (entry.isSelf and "  (você)" or "")
				nameLbl.Font = Enum.Font.GothamBold
				nameLbl.TextSize = 12
				nameLbl.TextColor3 = C.text
				nameLbl.TextXAlignment = Enum.TextXAlignment.Left
				nameLbl.Parent = card

				local carLbl = Instance.new("TextLabel")
				carLbl.BackgroundTransparency = 1
				carLbl.Size = UDim2.new(1, -90, 0, 18)
				carLbl.Position = UDim2.new(0, 8, 0, 28)
				local ago = entry.age < 60 and (entry.age .. "s") or (math.floor(entry.age / 60) .. "min")
				carLbl.Text = "Carro: " .. tostring(entry.carName) .. " · " .. ago .. " atrás"
				carLbl.Font = Enum.Font.Gotham
				carLbl.TextSize = 10
				carLbl.TextColor3 = C.dim
				carLbl.TextXAlignment = Enum.TextXAlignment.Left
				carLbl.Parent = card

				local verBtn = Instance.new("TextButton")
				verBtn.Size = UDim2.new(0, 72, 0, 40)
				verBtn.Position = UDim2.new(1, -80, 0.5, -20)
				verBtn.BackgroundColor3 = C.apply
				verBtn.Text = "Ver Config"
				verBtn.Font = Enum.Font.GothamBold
				verBtn.TextSize = 10
				verBtn.TextColor3 = C.text
				verBtn.Parent = card
				uiCorner(verBtn, 6)
				table.insert(themedButtons, verBtn)

				verBtn.MouseButton1Click:Connect(function()
					selectedRemoteConfig = entry.config
					configPreview.Text = formatConfigText(entry.config, entry.playerName, entry.carName)
				end)
			end
		end)
	end)
end

makeButton(secOnline, "Atualizar Lista", 3, function()
	refreshPlayersList()
end)
makeButton(secOnline, "Publicar Minha Presença", 4, function()
	publishConfig()
	onlineStatus.Text = "Publicando... | " .. lastPublishMsg
	task.delay(0.6, function()
		onlineStatus.Text = lastPublishMsg
		refreshPlayersList()
	end)
end)

--------------------------------------------------------------------
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
	if not motorState.enabled then motorState.enabled = true end
	motorState.currentDir = "Frente"
	aplicarMotor("Frente")
end, function()
	motorState.currentDir = "Parar"
	aplicarMotor("Parar")
end)

bindHold(btnRe, function()
	if not currentCar then currentCar = findPlayerCar() end
	if not isPlayerInCar(currentCar) then return end
	if not motorState.enabled then motorState.enabled = true end
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
	if not steerState.enabled then steerState.enabled = true end
	steerState.isA = true
end, function()
	steerState.isA = false
end)

bindHold(btnDir, function()
	if not currentCar then currentCar = findPlayerCar() end
	if not isPlayerInCar(currentCar) then return end
	if not steerState.enabled then steerState.enabled = true end
	steerState.isD = true
end, function()
	steerState.isD = false
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
	if gp or not isPlayerInCar(currentCar) then return end
	if input.KeyCode == Enum.KeyCode.W then
		if not motorState.enabled then motorState.enabled = true end
		motorState.currentDir = "Frente"
		aplicarMotor("Frente")
	elseif input.KeyCode == Enum.KeyCode.S then
		if not motorState.enabled then motorState.enabled = true end
		motorState.currentDir = "Re"
		aplicarMotor("Re")
	elseif input.KeyCode == Enum.KeyCode.A then
		if not steerState.enabled then steerState.enabled = true end
		steerState.isA = true
	elseif input.KeyCode == Enum.KeyCode.D then
		if not steerState.enabled then steerState.enabled = true end
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
local publishTick = 0

local conn3 = RunService.RenderStepped:Connect(function(dt)
	updateTick += dt
	publishTick += dt

	if publishTick >= 25 then
		publishTick = 0
		if currentCar and isPlayerInCar(currentCar) then
			publishConfig()
		end
	end

	if updateTick >= 0.35 then
		updateTick = 0
		local found = findPlayerCar()
		if found ~= currentCar then
			if currentCar then clearPublishedConfig() end
			currentCar = found
			driftOriginals = { front = nil, rear = nil }
			resetSteerOnExit()
			if found then publishConfig() end
		end
	end

	if not currentCar then
		currentCar = findPlayerCar()
	end

	local inCar = isPlayerInCar(currentCar)
	if wasInCar and not inCar then
		resetSteerOnExit()
		if motorState.enabled then aplicarMotor("Parar") end
		clearPublishedConfig()
		currentCar = nil
	end
	if (not wasInCar) and inCar then
		steerState.isA = false
		steerState.isD = false
		steerState.currentSteer = 0
		if steerState.enabled then applySteerAngle(0) end
		publishConfig()
	end
	wasInCar = inCar

	if steerState.enabled and currentCar then
		local steerDirection = 0
		if inCar then
			if steerState.isA and not steerState.isD then
				steerDirection = -1
			elseif steerState.isD and not steerState.isA then
				steerDirection = 1
			end
		end
		local slipAngle = 0
		if steerState.autoAlign and inCar then
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
			local target = (steerState.autoAlign and inCar) and slipAngle or 0
			if steerState.currentSteer < target then
				steerState.currentSteer = math.min(target, steerState.currentSteer + (steerState.speed * dt))
			elseif steerState.currentSteer > target then
				steerState.currentSteer = math.max(target, steerState.currentSteer - (steerState.speed * dt))
			end
		end
		applySteerAngle(steerState.currentSteer)
	end
end)
table.insert(connections, conn3)

player.CharacterAdded:Connect(function()
	task.wait(0.4)
	resetSteerOnExit()
end)

-- presença online inicial + limpa ao sair
task.spawn(function()
	task.wait(1)
	publishConfig()
end)
game:GetService("Players").PlayerRemoving:Connect(function(p)
	if p == player then
		clearPublishedConfig()
	end
end)

