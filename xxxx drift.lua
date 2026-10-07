local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local HttpService      = game:GetService("HttpService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

local C = {
	bg = Color3.fromRGB(8, 8, 8), panel = Color3.fromRGB(16, 16, 16),
	border = Color3.fromRGB(45, 45, 45), title = Color3.fromRGB(230, 230, 230),
	text = Color3.fromRGB(220, 220, 220), dim = Color3.fromRGB(140, 140, 140),
	inputBg = Color3.fromRGB(12, 12, 12), divider = Color3.fromRGB(35, 35, 35),
	apply = Color3.fromRGB(35, 35, 35), green = Color3.fromRGB(0, 170, 60),
	red = Color3.fromRGB(170, 30, 30), yellow = Color3.fromRGB(200, 160, 0),
	pink = Color3.fromRGB(230, 80, 130),
	tabActive = Color3.fromRGB(0, 160, 65), tabInactive = Color3.fromRGB(28, 28, 28),
	sliderBg = Color3.fromRGB(30, 30, 30), sliderFill = Color3.fromRGB(0, 160, 65),
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

local publishCarName = ""
local currentProfileView = nil

local liveCounters = {}
local detailLabel
local selectedRemoteConfig
local selectedConfigEntry

local FIREBASE_LIVE = "https://drift-x-3edf5-default-rtdb.firebaseio.com/driftx/live"
local FIREBASE_LIKES = "https://drift-x-3edf5-default-rtdb.firebaseio.com/driftx/likes"
local ONLINE_TIMEOUT = 240
local FIXED_DURATION = 30 * 24 * 3600
local AUTO_REFRESH_INTERVAL = 4

local lastHttpError = ""
local function hasHttpRequest()
	return (syn and syn.request) or (http and http.request) or http_request or request
end

local function httpRequest(opts)
	local req = hasHttpRequest()
	if not req then
		lastHttpError = "sem request"
		return { StatusCode = 0, Body = "", Error = lastHttpError, Success = false }
	end
	local ok, r = pcall(req, opts)
	if not ok then
		lastHttpError = tostring(r)
		return { StatusCode = 0, Body = "", Error = lastHttpError, Success = false }
	end
	if type(r) ~= "table" then
		lastHttpError = "resposta invalida"
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
	return { StatusCode = tonumber(code) or 0, Body = tostring(body), Success = success, Error = lastHttpError }
end

local function randomId(len)
	local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	local s = ""
	for i = 1, (len or 8) do
		local n = math.random(1, #chars)
		s = s .. chars:sub(n, n)
	end
	return s
end

local sharedConfig = {
	friction = 0.30, weight = 1.00, maxVel = 100, maxTorque = 50000,
	maxAngle = 0.40, steerSpeed = 0.50, driftOn = false, motorOn = false,
	steerOn = false, autoAlign = false,
}

function parseNum(str) return tonumber((tostring(str):gsub(",", "."))) end

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

function formatDate(ts)
	if not ts or ts == 0 then return "-" end
	local ok, d = pcall(os.date, "%d/%m %H:%M", ts)
	return ok and d or "-"
end

function formatAgo(sec)
	if not sec or sec < 0 then return "agora" end
	if sec < 60 then return sec .. "s"
	elseif sec < 3600 then return math.floor(sec / 60) .. "min"
	elseif sec < 86400 then return math.floor(sec / 3600) .. "h"
	else return math.floor(sec / 86400) .. "d" end
end

function formatRemaining(sec)
	if not sec or sec <= 0 then return "expirado" end
	sec = math.floor(sec)
	local d = math.floor(sec / 86400)
	local h = math.floor((sec % 86400) / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	if d > 0 then return string.format("%dd %dh %dmin %ds", d, h, m, s)
	elseif h > 0 then return string.format("%dh %dmin %ds", h, m, s)
	elseif m > 0 then return string.format("%dmin %ds", m, s)
	else return string.format("%ds", s) end
end
function makeDraggable(frame, handle)
	local dragging, dragStart, startPos, locked = false, nil, nil, false
	handle = handle or frame
	local function beginDrag(input)
		if locked then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
		end
	end
	local function endDrag(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end
	handle.InputBegan:Connect(beginDrag)
	handle.InputEnded:Connect(endDrag)
	local conn = UserInputService.InputChanged:Connect(function(input)
		if locked or not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local d = input.Position - dragStart
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
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

local lastPublishOk = false
local lastPublishMsg = "ainda nao publicou"
local isFixedPublished = false
local publishedIds = {}
local fixedData = nil
local myLikes = {}

local sliderRefs = { friction = nil, weight = nil, maxVel = nil, maxTorque = nil, maxAngle = nil, steerSpeed = nil }

function captureConfigSnapshot()
	return {
		friction = sharedConfig.friction, weight = sharedConfig.weight,
		maxVel = sharedConfig.maxVel, maxTorque = sharedConfig.maxTorque,
		maxAngle = sharedConfig.maxAngle, steerSpeed = sharedConfig.steerSpeed,
		driftOn = sharedConfig.driftOn, motorOn = sharedConfig.motorOn,
		steerOn = sharedConfig.steerOn, autoAlign = sharedConfig.autoAlign,
	}
end

function applyConfigFromRemote(cfg)
	if not cfg then return end
	if cfg.friction and sliderRefs.friction then sliderRefs.friction.set(cfg.friction) end
	if cfg.weight and sliderRefs.weight then sliderRefs.weight.set(cfg.weight) end
	if cfg.maxVel and sliderRefs.maxVel then sliderRefs.maxVel.set(cfg.maxVel) end
	if cfg.maxTorque and sliderRefs.maxTorque then sliderRefs.maxTorque.set(cfg.maxTorque) end
	if cfg.maxAngle and sliderRefs.maxAngle then sliderRefs.maxAngle.set(cfg.maxAngle) end
	if cfg.steerSpeed and sliderRefs.steerSpeed then sliderRefs.steerSpeed.set(cfg.steerSpeed) end
	if cfg.friction then sharedConfig.friction = cfg.friction end
	if cfg.weight then sharedConfig.weight = cfg.weight end
	if cfg.maxVel then sharedConfig.maxVel = cfg.maxVel end
	if cfg.maxTorque then sharedConfig.maxTorque = cfg.maxTorque end
	if cfg.maxAngle then sharedConfig.maxAngle = cfg.maxAngle end
	if cfg.steerSpeed then sharedConfig.steerSpeed = cfg.steerSpeed end
	motorState.maxVel = sharedConfig.maxVel
	motorState.maxTorque = sharedConfig.maxTorque
	steerState.maxAngle = sharedConfig.maxAngle
	steerState.speed = sharedConfig.steerSpeed
end

function buildOnlineData()
	return {
		name = player.Name, displayName = player.DisplayName or player.Name,
		userId = player.UserId,
		config = captureConfigSnapshot(),
		jobId = game.JobId, serverPlace = game.PlaceId, timestamp = os.time(),
		isFixed = false, expiresAt = 0, description = "", carName = "",
	}
end

function buildFixedData(desc)
	local id = tostring(player.UserId) .. "_" .. randomId(8)
	return id, {
		name = player.Name, displayName = player.DisplayName or player.Name,
		userId = player.UserId, carName = publishCarName,
		description = desc or "", isFixed = true, expiresAt = os.time() + FIXED_DURATION,
		config = captureConfigSnapshot(),
		jobId = game.JobId, serverPlace = game.PlaceId, timestamp = os.time(),
		likes = 0, likeUserIds = {},
	}
end

function publishOnline()
	task.spawn(function()
		local r = httpRequest({ Url = FIREBASE_LIVE .. "/online_" .. tostring(player.UserId) .. ".json", Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
		-- só publica online temporário se não tiver NENHUMA publicação fixada ativa
		if isFixedPublished then
			local anyActive = false
			for _, pid in ipairs(publishedIds) do
				local pr = httpRequest({ Url = FIREBASE_LIVE .. "/" .. pid .. ".json", Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
				if pr and pr.Success and pr.Body and pr.Body ~= "null" then
					local ok, data = pcall(function() return HttpService:JSONDecode(pr.Body) end)
					if ok and type(data) == "table" and data.isFixed then
						local exp = tonumber(data.expiresAt) or 0
						if exp > os.time() then
							anyActive = true
							data.timestamp = os.time()
							data.jobId = game.JobId
							httpRequest({ Url = FIREBASE_LIVE .. "/" .. pid .. ".json", Method = "PUT", Headers = { ["Content-Type"] = "application/json" }, Body = HttpService:JSONEncode(data) })
						end
					end
				end
			end
			if anyActive then
				lastPublishOk = true
				lastPublishMsg = "online mantendo publicacoes (" .. os.date("%H:%M:%S") .. ")"
				return
			end
		end
		-- publica temporário pra aparecer em Jogadores
		local data = buildOnlineData()
		local ok, res = pcall(function()
			return httpRequest({ Url = FIREBASE_LIVE .. "/online_" .. tostring(player.UserId) .. ".json", Method = "PUT", Headers = { ["Content-Type"] = "application/json" }, Body = HttpService:JSONEncode(data) })
		end)
		if ok and res and res.Success then
			lastPublishOk = true
			lastPublishMsg = "online (" .. os.date("%H:%M:%S") .. ")"
		else
			lastPublishOk = false
			lastPublishMsg = "falha: " .. (lastHttpError ~= "" and lastHttpError or "desconhecida")
		end
	end)
end

function publishFixed(desc)
	local id, data = buildFixedData(desc)
	task.spawn(function()
		local ok, res = pcall(function()
			return httpRequest({ Url = FIREBASE_LIVE .. "/" .. id .. ".json", Method = "PUT", Headers = { ["Content-Type"] = "application/json" }, Body = HttpService:JSONEncode(data) })
		end)
		if ok and res and res.Success then
			lastPublishOk = true
			lastPublishMsg = "publicado (" .. os.date("%H:%M:%S") .. ")"
			isFixedPublished = true
			table.insert(publishedIds, id)
		else
			lastPublishOk = false
			lastPublishMsg = "falha: " .. (lastHttpError ~= "" and lastHttpError or "desconhecida")
			warn("[DriftX] " .. lastPublishMsg)
		end
	end)
end
function loadMyPublishedIds()
	task.spawn(function()
		local r = httpRequest({ Url = FIREBASE_LIVE .. ".json", Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
		if not r or not r.Success or not r.Body or r.Body == "null" then return end
		local ok, data = pcall(function() return HttpService:JSONDecode(r.Body) end)
		if not ok or type(data) ~= "table" then return end
		publishedIds = {}
		isFixedPublished = false
		for key, item in pairs(data) do
			if type(item) == "table" and item.userId == player.UserId and item.isFixed == true then
				local exp = tonumber(item.expiresAt) or 0
				if exp > os.time() then
					table.insert(publishedIds, key)
					isFixedPublished = true
				end
			end
		end
	end)
end

function cleanExpiredMyPosts()
	task.spawn(function()
		local r = httpRequest({ Url = FIREBASE_LIVE .. ".json", Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
		if not r or not r.Success or not r.Body or r.Body == "null" then return end
		local ok, data = pcall(function() return HttpService:JSONDecode(r.Body) end)
		if not ok or type(data) ~= "table" then return end
		local removed = 0
		for key, item in pairs(data) do
			if type(item) == "table" and item.userId == player.UserId and item.isFixed == true then
				local exp = tonumber(item.expiresAt) or 0
				if exp <= os.time() then
					httpRequest({ Url = FIREBASE_LIVE .. "/" .. key .. ".json", Method = "DELETE" })
					removed = removed + 1
				end
			end
		end
		if removed > 0 then
			print("[DriftX] " .. removed .. " publicacao(oes) expirada(s) removida(s)")
		end
	end)
end

function deletePublishedId(id)
	task.spawn(function()
		httpRequest({ Url = FIREBASE_LIVE .. "/" .. id .. ".json", Method = "DELETE" })
	end)
	for i, pid in ipairs(publishedIds) do
		if pid == id then
			table.remove(publishedIds, i)
			break
		end
	end
	if #publishedIds == 0 then
		isFixedPublished = false
	end
end

function fetchLiveConfigs()
	if not hasHttpRequest() then
		lastHttpError = "sem request"
		return {}, lastHttpError
	end
	local r = httpRequest({ Url = FIREBASE_LIVE .. ".json", Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
	if not r or not r.Success then return {}, (r and r.Error) or lastHttpError or "GET falhou" end
	local body = r.Body or ""
	if body == "" or body == "null" then return {}, nil end
	local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
	if not ok or type(data) ~= "table" then return {}, "JSON invalido" end
	return data, nil
end

function fetchLikes()
	local r = httpRequest({ Url = FIREBASE_LIKES .. ".json", Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
	if not r or not r.Success then return {} end
	local body = r.Body or ""
	if body == "" or body == "null" then return {} end
	local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
	if not ok or type(data) ~= "table" then return {} end
	return data
end

function toggleLike(postId, currentLikes)
	local myLikeKey = tostring(postId) .. "_" .. tostring(player.UserId)
	local allLikes = fetchLikes()
	if allLikes[myLikeKey] then
		httpRequest({ Url = FIREBASE_LIKES .. "/" .. myLikeKey .. ".json", Method = "DELETE" })
		local newCount = math.max(0, (tonumber(currentLikes) or 0) - 1)
		httpRequest({ Url = FIREBASE_LIVE .. "/" .. postId .. "/likes.json", Method = "PUT", Headers = { ["Content-Type"] = "application/json" }, Body = tostring(newCount) })
		return newCount, false
	else
		httpRequest({ Url = FIREBASE_LIKES .. "/" .. myLikeKey .. ".json", Method = "PUT", Headers = { ["Content-Type"] = "application/json" }, Body = tostring(os.time()) })
		local newCount = (tonumber(currentLikes) or 0) + 1
		httpRequest({ Url = FIREBASE_LIVE .. "/" .. postId .. "/likes.json", Method = "PUT", Headers = { ["Content-Type"] = "application/json" }, Body = tostring(newCount) })
		return newCount, true
	end
end

function hasLiked(postId)
	local myLikeKey = tostring(postId) .. "_" .. tostring(player.UserId)
	local allLikes = fetchLikes()
	return allLikes[myLikeKey] ~= nil
end

function scanOnlineUsers()
	local list = {}
	local lives, err = fetchLiveConfigs()
	local now = os.time()
	if type(lives) ~= "table" then return list, err or "sem dados" end
	for key, live in pairs(lives) do
		if type(live) == "table" and live.userId and live.isFixed ~= true then
			local ts = tonumber(live.timestamp) or 0
			local age = now - ts
			if age <= ONLINE_TIMEOUT then
				local cfg = live.config
				if type(cfg) ~= "table" then cfg = {} end
				local isSelf = (tonumber(live.userId) == tonumber(player.UserId))
				table.insert(list, {
					id = key,
					playerName = tostring(live.name or "?"),
					displayName = tostring(live.displayName or live.name or "?"),
					userId = live.userId,
					config = cfg,
					timestamp = ts,
					age = age,
					isSelf = isSelf,
					sameServer = (tostring(live.jobId) == tostring(game.JobId)),
				})
			end
		end
	end
	table.sort(list, function(a, b)
		if a.isSelf ~= b.isSelf then return a.isSelf end
		if a.sameServer ~= b.sameServer then return a.sameServer end
		return (a.playerName or "") < (b.playerName or "")
	end)
	return list, err
end

function scanFixedUsers()
	local list = {}
	local lives, err = fetchLiveConfigs()
	local now = os.time()
	if type(lives) ~= "table" then return list, err or "sem dados" end
	for key, live in pairs(lives) do
		if type(live) == "table" and live.userId and live.isFixed == true then
			local expiresAt = tonumber(live.expiresAt) or 0
			local remaining = expiresAt - now
			if remaining > 0 then
				local cfg = live.config
				if type(cfg) ~= "table" then cfg = {} end
				local ts = tonumber(live.timestamp) or 0
				local isSelf = (tonumber(live.userId) == tonumber(player.UserId))
				local isOnline = (now - ts) <= ONLINE_TIMEOUT
				table.insert(list, {
					id = key,
					playerName = tostring(live.name or "?"),
					displayName = tostring(live.displayName or live.name or "?"),
					userId = live.userId,
					carName = tostring(live.carName or "-"),
					description = tostring(live.description or ""),
					config = cfg,
					timestamp = ts,
					expiresAt = expiresAt,
					remaining = remaining,
					isSelf = isSelf,
					isOnline = isOnline,
					likes = tonumber(live.likes) or 0,
					sameServer = (tostring(live.jobId) == tostring(game.JobId)),
				})
			end
		end
	end
	table.sort(list, function(a, b)
		if a.isSelf ~= b.isSelf then return a.isSelf end
		if a.isOnline ~= b.isOnline then return a.isOnline end
		return (a.timestamp or 0) > (b.timestamp or 0)
	end)
	return list, err
end

function groupByAuthor(list)
	local authors = {}
	for _, entry in ipairs(list) do
		local uid = entry.userId
		if not authors[uid] then
			authors[uid] = {
				userId = uid,
				playerName = entry.playerName,
				displayName = entry.displayName,
				isSelf = entry.isSelf,
				isOnline = entry.isOnline,
				totalLikes = 0,
				posts = {},
			}
		end
		authors[uid].totalLikes = authors[uid].totalLikes + (entry.likes or 0)
		if entry.isOnline then authors[uid].isOnline = true end
		table.insert(authors[uid].posts, entry)
	end
	local result = {}
	for _, a in pairs(authors) do
		table.sort(a.posts, function(x, y) return (x.timestamp or 0) > (y.timestamp or 0) end)
		table.insert(result, a)
	end
	table.sort(result, function(a, b)
		if a.isSelf ~= b.isSelf then return a.isSelf end
		return a.totalLikes > b.totalLikes
	end)
	return result
end
function findPlayerCar()
	if player.Character then
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart then
			local obj = hum.SeatPart
			while obj and obj ~= workspace do
				if obj.Parent and obj.Parent.Name == "Cars" then return obj end
				local stats = obj:FindFirstChild("Stats")
				if stats and stats:FindFirstChild("Owner") then return obj end
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
					if v == myName or v == player or v == player.UserId or tostring(v):lower() == myName:lower() then return car end
				end
			end
			if car.Name:lower():find(myName:lower(), 1, true) then return car end
			local seat = car:FindFirstChildWhichIsA("VehicleSeat", true) or car:FindFirstChildWhichIsA("Seat", true)
			if seat and seat.Occupant and seat.Occupant.Parent == player.Character then return car end
		end
	end
	return nil
end

function isPlayerInCar(car)
	if not player.Character then return false end
	local hum = player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or not hum.SeatPart then return false end
	if car then return hum.SeatPart:IsDescendantOf(car) end
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
				if w and w:IsA("BasePart") then table.insert(result, w) end
				local sw = obj:FindFirstChild("SecondaryWheel")
				if sw and sw:IsA("BasePart") then table.insert(result, sw) end
			end
		end
	end
	return result
end

function readPhysics(wheel)
	local p = wheel.CustomPhysicalProperties
	if typeof(p) == "PhysicalProperties" then
		return { density = p.Density, friction = p.Friction, elasticity = p.Elasticity, frictionWeight = p.FrictionWeight, elasticityWeight = p.ElasticityWeight }
	end
	return { density = 0.7, friction = 0.3, elasticity = 0.5, frictionWeight = 1.0, elasticityWeight = 1.0 }
end

function applyDrift(group, friction, frictionWeight)
	if not currentCar then return false end
	local wheels = getWheels(currentCar, group)
	if #wheels == 0 then return false end
	if not driftOriginals[group] then driftOriginals[group] = readPhysics(wheels[1]) end
	local base = driftOriginals[group]
	for _, w in ipairs(wheels) do
		w.CustomPhysicalProperties = PhysicalProperties.new(base.density, friction, base.elasticity, frictionWeight, base.elasticityWeight)
	end
	return true
end

function obterConstraints()
	if not currentCar then return nil end
	local constraints = currentCar:FindFirstChild("Constraints")
	if not constraints then return nil end
	for _, item in pairs(constraints:GetChildren()) do
		if item.Name == "Front" or item.Name == "Rear" then item.Name = "Rodas" end
	end
	return constraints
end

function aplicarMotor(direcao)
	if not motorState.enabled then return end
	local constraints = obterConstraints()
	if not constraints then return end
	local velocidadeAlvo = 0
	if direcao == "Frente" then velocidadeAlvo = -math.abs(motorState.maxVel)
	elseif direcao == "Re" then velocidadeAlvo = math.abs(motorState.maxVel) end
	if direcao ~= "Parar" and not isPlayerInCar(currentCar) then velocidadeAlvo = 0 end
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

function applyHudSettings()
	local size = math.clamp(hudState.btnSize or 80, 40, 140)
	local gap = 12
	local frameW = size * 2 + gap
	local frameH = size
	local trans = math.clamp(hudState.transparency or 0, 0, 1)
	local show = hudState.arrowsEnabled and UserInputService.TouchEnabled
	if motorFrame then motorFrame.Size = UDim2.new(0, frameW, 0, frameH); motorFrame.Visible = show end
	if steerFrame then steerFrame.Size = UDim2.new(0, frameW, 0, frameH); steerFrame.Visible = show end
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
menu.Size = UDim2.new(0, 460, 0, 540)
menu.Position = UDim2.new(0.5, -230, 0.5, -270)
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
titleLabel.Text = "Drift X v6.0"
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
local refreshConfigList
local refreshPublishList
local showProfileView

function createTab(name)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 68, 0, 26)
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
		if name == "Jogadores" and refreshPlayersList then refreshPlayersList() end
		if name == "Config" and refreshConfigList then refreshConfigList() end
		if name == "Publicar" and refreshPublishList then refreshPublishList() end
	end)
	return page
end

local pageCarro     = createTab("Carro")
local pageHud       = createTab("HUD")
local pagePainel    = createTab("Painel")
local pageJogadores = createTab("Jogadores")
local pagePublicar  = createTab("Publicar")
local pageConfig    = createTab("Config")
local pagePerfil    = createTab("Perfil")

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
	local function fmt(v) return string.format("%." .. (decimals or 2) .. "f", v) end
	local function setSliderVisual(v)
		local clamped = math.clamp(v, minV, maxV)
		local pct = (clamped - minV) / math.max(maxV - minV, 1e-9)
		fill.Size = UDim2.new(pct, 0, 1, 0)
		knob.Position = UDim2.new(pct, -8, 0.5, -8)
	end
	local function setValue(v, fromBox)
		value = v
		updating = true
		if not fromBox then box.Text = fmt(v) end
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
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromInputX(input.Position.X)
		end
	end)
	knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	local conn = UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			fromInputX(input.Position.X)
		end
	end)
	table.insert(connections, conn)
	local conn2 = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
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
	return { get = function() return value end, set = function(v) setValue(v, false) end, box = box }
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

-- ABA CARRO
local secDrift = createSection(pageCarro, "Drift", 1)
local frictionCtrl = makeSliderWithInput(secDrift, "Friction", 0.01, 10, 0.30, 1, 2)
local weightCtrl   = makeSliderWithInput(secDrift, "Weight", 0.10, 50, 1.00, 2, 2)
sliderRefs.friction = frictionCtrl
sliderRefs.weight = weightCtrl

makeButton(secDrift, "Inserir Config Drift", 3, function()
	if not currentCar then currentCar = findPlayerCar() end
	local f = frictionCtrl.get()
	local fw = weightCtrl.get()
	sharedConfig.friction = f
	sharedConfig.weight = fw
	sharedConfig.driftOn = true
	applyDrift("front", f, fw)
	applyDrift("rear", f, fw)
	publishOnline()
	print("Drift aplicado")
end)

local secMotor = createSection(pageCarro, "Motor", 2)
local velCtrl    = makeSliderWithInput(secMotor, "Velocidade", 10, 1000, 100, 1, 0)
local torqueCtrl = makeSliderWithInput(secMotor, "Torque", 1000, 200000, 50000, 2, 0)
sliderRefs.maxVel = velCtrl
sliderRefs.maxTorque = torqueCtrl

makeButton(secMotor, "Inserir Config Motor", 3, function()
	if not currentCar then currentCar = findPlayerCar() end
	motorState.maxVel = velCtrl.get()
	motorState.maxTorque = torqueCtrl.get()
	motorState.enabled = true
	sharedConfig.maxVel = motorState.maxVel
	sharedConfig.maxTorque = motorState.maxTorque
	sharedConfig.motorOn = true
	publishOnline()
	print("Motor configurado")
end)

local secSteer = createSection(pageCarro, "Direcao", 3)
local angleCtrl = makeValueInput(secSteer, "Max Angle", 0.40, 1, 2)
local speedCtrl = makeSliderWithInput(secSteer, "Speed", 0.05, 3.00, 0.50, 2, 2)
sliderRefs.maxAngle = angleCtrl
sliderRefs.steerSpeed = speedCtrl

makeButton(secSteer, "Inserir Config Direcao", 3, function()
	if not currentCar then currentCar = findPlayerCar() end
	steerState.maxAngle = math.abs(angleCtrl.get())
	steerState.speed = speedCtrl.get()
	steerState.enabled = true
	sharedConfig.maxAngle = steerState.maxAngle
	sharedConfig.steerSpeed = steerState.speed
	sharedConfig.steerOn = true
	publishOnline()
	print("Direcao configurada")
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
	publishOnline()
	print("Config completa inserida")
end)
-- ABA HUD
local secHud = createSection(pageHud, "Setas Mobile", 1)
local arrowsOn = true
local arrowsBtn = makeButton(secHud, "Mostrar Setas: ON", 1, function()
	arrowsOn = not arrowsOn
	hudState.arrowsEnabled = arrowsOn
	arrowsBtn.Text = "Mostrar Setas: " .. (arrowsOn and "ON" or "OFF")
	applyHudSettings()
end)
local sizeBox = makeInput(secHud, "Tamanho (40-140)", "80", 2)
local transBox = makeInput(secHud, "Transparencia (0-1)", "0", 3)
makeButton(secHud, "Aplicar HUD", 4, function()
	local s = parseNum(sizeBox.Text)
	local t = parseNum(transBox.Text)
	if s then hudState.btnSize = math.clamp(s, 40, 140) end
	if t then hudState.transparency = math.clamp(t, 0, 1) end
	sizeBox.Text = tostring(hudState.btnSize)
	transBox.Text = string.format("%.2f", hudState.transparency)
	applyHudSettings()
end)

-- ABA PAINEL
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
			TweenService:Create(menu, TweenInfo.new(0.18), { Position = UDim2.new(0, (vp.X - w) / 2, 0, (vp.Y - h) / 2) }):Play()
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

local secActions = createSection(pagePainel, "Acoes", 3)
makeButton(secActions, "Centralizar na Tela", 1, function()
	local vp = camera.ViewportSize
	local w = menu.AbsoluteSize.X
	local h = menu.AbsoluteSize.Y
	TweenService:Create(menu, TweenInfo.new(0.2), { Position = UDim2.new(0, (vp.X - w) / 2, 0, (vp.Y - h) / 2) }):Play()
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
	{ name = "Azul",        accent = Color3.fromRGB(0, 60, 160) },
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
	sw.MouseButton1Click:Connect(function() applyTheme(theme) end)
end

function addLiveCounter(lbl, expiresAt)
	table.insert(liveCounters, { label = lbl, expiresAt = expiresAt })
end

task.spawn(function()
	while true do
		task.wait(1)
		local now = os.time()
		for i = #liveCounters, 1, -1 do
			local c = liveCounters[i]
			if c.label and c.label.Parent then
				local remaining = c.expiresAt - now
				if remaining > 0 then
					c.label.Text = "Expira em: " .. formatRemaining(remaining)
				else
					c.label.Text = "Expirado"
					c.label.TextColor3 = C.red
				end
			else
				table.remove(liveCounters, i)
			end
		end
	end
end)
-- ABA PUBLICAR
local secHowTo = createSection(pagePublicar, "Como Funciona", 1)
local howToLbl = Instance.new("TextLabel")
howToLbl.BackgroundTransparency = 1
howToLbl.Size = UDim2.new(1, 0, 0, 90)
howToLbl.Text = "- Cada clique em Publicar cria uma PUBLICACAO NOVA\n- Voce pode ter quantas quiser (sem limite)\n- Cada uma dura 30 dias e depois expira\n- Outros jogadores veem e podem curtir (coracao)\n- So voce pode remover as suas publicacoes"
howToLbl.TextWrapped = true
howToLbl.Font = Enum.Font.Gotham
howToLbl.TextSize = 11
howToLbl.TextColor3 = C.dim
howToLbl.TextXAlignment = Enum.TextXAlignment.Left
howToLbl.TextYAlignment = Enum.TextYAlignment.Top
howToLbl.LayoutOrder = 1
howToLbl.Parent = secHowTo

local secForm = createSection(pagePublicar, "Publicar Nova Config (30 dias)", 2)

local pubNameRow = Instance.new("Frame")
pubNameRow.Size = UDim2.new(1, 0, 0, 44)
pubNameRow.BackgroundTransparency = 1
pubNameRow.LayoutOrder = 1
pubNameRow.Parent = secForm

local pubNameLbl = Instance.new("TextLabel")
pubNameLbl.BackgroundTransparency = 1
pubNameLbl.Size = UDim2.new(1, 0, 0, 14)
pubNameLbl.Text = "Nome do carro"
pubNameLbl.Font = Enum.Font.Gotham
pubNameLbl.TextSize = 10
pubNameLbl.TextColor3 = C.dim
pubNameLbl.TextXAlignment = Enum.TextXAlignment.Left
pubNameLbl.Parent = pubNameRow

local pubNameBox = Instance.new("TextBox")
pubNameBox.Size = UDim2.new(1, 0, 0, 26)
pubNameBox.Position = UDim2.new(0, 0, 0, 16)
pubNameBox.BackgroundColor3 = C.inputBg
pubNameBox.PlaceholderText = "Ex: Skyline do Rick"
pubNameBox.PlaceholderColor3 = Color3.fromRGB(90, 90, 90)
pubNameBox.Text = ""
pubNameBox.Font = Enum.Font.GothamMedium
pubNameBox.TextSize = 12
pubNameBox.TextColor3 = C.text
pubNameBox.ClearTextOnFocus = false
pubNameBox.TextXAlignment = Enum.TextXAlignment.Left
pubNameBox.Parent = pubNameRow
uiCorner(pubNameBox, 6)
uiStroke(pubNameBox, C.border, 1)
local padPub = Instance.new("UIPadding")
padPub.PaddingLeft = UDim.new(0, 8)
padPub.PaddingRight = UDim.new(0, 8)
padPub.Parent = pubNameBox

local descRow = Instance.new("Frame")
descRow.Size = UDim2.new(1, 0, 0, 60)
descRow.BackgroundTransparency = 1
descRow.LayoutOrder = 2
descRow.Parent = secForm

local descLbl = Instance.new("TextLabel")
descLbl.BackgroundTransparency = 1
descLbl.Size = UDim2.new(1, 0, 0, 14)
descLbl.Text = "Descricao (opcional)"
descLbl.Font = Enum.Font.Gotham
descLbl.TextSize = 10
descLbl.TextColor3 = C.dim
descLbl.TextXAlignment = Enum.TextXAlignment.Left
descLbl.Parent = descRow

local descBox = Instance.new("TextBox")
descBox.Size = UDim2.new(1, 0, 0, 44)
descBox.Position = UDim2.new(0, 0, 0, 16)
descBox.BackgroundColor3 = C.inputBg
descBox.PlaceholderText = "Ex: Config de drift suave..."
descBox.PlaceholderColor3 = Color3.fromRGB(90, 90, 90)
descBox.Text = ""
descBox.Font = Enum.Font.GothamMedium
descBox.TextSize = 11
descBox.TextColor3 = C.text
descBox.ClearTextOnFocus = false
descBox.TextWrapped = true
descBox.TextXAlignment = Enum.TextXAlignment.Left
descBox.TextYAlignment = Enum.TextYAlignment.Top
descBox.Parent = descRow
uiCorner(descBox, 6)
uiStroke(descBox, C.border, 1)
local padDesc = Instance.new("UIPadding")
padDesc.PaddingLeft = UDim.new(0, 8)
padDesc.PaddingRight = UDim.new(0, 8)
padDesc.PaddingTop = UDim.new(0, 6)
padDesc.Parent = descBox

local pubCounterLbl = Instance.new("TextLabel")
pubCounterLbl.BackgroundTransparency = 1
pubCounterLbl.Size = UDim2.new(1, 0, 0, 16)
pubCounterLbl.Text = "Voce tem 0 publicacoes ativas"
pubCounterLbl.Font = Enum.Font.Gotham
pubCounterLbl.TextSize = 10
pubCounterLbl.TextColor3 = C.dim
pubCounterLbl.TextXAlignment = Enum.TextXAlignment.Left
pubCounterLbl.LayoutOrder = 3
pubCounterLbl.Parent = secForm

local publishBtn = makeButton(secForm, "Publicar Nova (30 dias)", 4, function()
	local nomeDigitado = pubNameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if nomeDigitado == "" then
		nomeDigitado = "Config de " .. player.Name
	end
	publishCarName = nomeDigitado
	publishFixed(descBox.Text)
	task.wait(0.5)
	task.defer(function()
		if refreshPublishList then refreshPublishList() end
		if refreshConfigList then refreshConfigList() end
	end)
	publishBtn.Text = "Publicado!"
	task.delay(2, function()
		publishBtn.Text = "Publicar Nova (30 dias)"
	end)
end)

local secMyFixed = createSection(pagePublicar, "Minhas Publicacoes Ativas", 3)
local myFixedFrame = Instance.new("Frame")
myFixedFrame.Size = UDim2.new(1, 0, 0, 0)
myFixedFrame.AutomaticSize = Enum.AutomaticSize.Y
myFixedFrame.BackgroundTransparency = 1
myFixedFrame.LayoutOrder = 1
myFixedFrame.Parent = secMyFixed

local myFixedLayout = Instance.new("UIListLayout")
myFixedLayout.SortOrder = Enum.SortOrder.LayoutOrder
myFixedLayout.Padding = UDim.new(0, 6)
myFixedLayout.Parent = myFixedFrame

local myFixedStatus = Instance.new("TextLabel")
myFixedStatus.BackgroundTransparency = 1
myFixedStatus.Size = UDim2.new(1, 0, 0, 18)
myFixedStatus.Text = "Nenhuma publicacao"
myFixedStatus.Font = Enum.Font.Gotham
myFixedStatus.TextSize = 11
myFixedStatus.TextColor3 = C.dim
myFixedStatus.TextXAlignment = Enum.TextXAlignment.Left
myFixedStatus.LayoutOrder = 0
myFixedStatus.Parent = secMyFixed

function clearMyFixed()
	for _, child in ipairs(myFixedFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end
refreshPublishList = function()
	clearMyFixed()
	myFixedStatus.Text = "Buscando..."
	task.spawn(function()
		local all, err = scanFixedUsers()
		task.defer(function()
			clearMyFixed()
			local mine = {}
			for _, e in ipairs(all) do
				if e.isSelf then table.insert(mine, e) end
			end
			pubCounterLbl.Text = "Voce tem " .. #mine .. " publicacoes ativas"
			if #mine == 0 then
				myFixedStatus.Text = "Voce nao tem publicacoes ativas"
				return
			end
			myFixedStatus.Text = tostring(#mine) .. " publicacao(oes) ativa(s)"
			for i, entry in ipairs(mine) do
				local card = Instance.new("Frame")
				card.Size = UDim2.new(1, 0, 0, 130)
				card.BackgroundColor3 = Color3.fromRGB(20, 40, 20)
				card.LayoutOrder = i
				card.Parent = myFixedFrame
				uiCorner(card, 6)
				uiStroke(card, C.green, 1)

				local nameLbl = Instance.new("TextLabel")
				nameLbl.BackgroundTransparency = 1
				nameLbl.Size = UDim2.new(1, -140, 0, 18)
				nameLbl.Position = UDim2.new(0, 8, 0, 6)
				nameLbl.Text = entry.carName
				nameLbl.Font = Enum.Font.GothamBold
				nameLbl.TextSize = 12
				nameLbl.TextColor3 = C.text
				nameLbl.TextXAlignment = Enum.TextXAlignment.Left
				nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
				nameLbl.Parent = card

				local likeLbl = Instance.new("TextLabel")
				likeLbl.BackgroundTransparency = 1
				likeLbl.Size = UDim2.new(0, 120, 0, 18)
				likeLbl.Position = UDim2.new(1, -128, 0, 6)
				likeLbl.Text = "❤️ " .. (entry.likes or 0)
				likeLbl.Font = Enum.Font.GothamBold
				likeLbl.TextSize = 11
				likeLbl.TextColor3 = C.pink
				likeLbl.TextXAlignment = Enum.TextXAlignment.Right
				likeLbl.Parent = card

				local descLbl2 = Instance.new("TextLabel")
				descLbl2.BackgroundTransparency = 1
				descLbl2.Size = UDim2.new(1, -16, 0, 16)
				descLbl2.Position = UDim2.new(0, 8, 0, 24)
				descLbl2.Text = entry.description ~= "" and entry.description or "(sem descricao)"
				descLbl2.Font = Enum.Font.Gotham
				descLbl2.TextSize = 10
				descLbl2.TextColor3 = C.dim
				descLbl2.TextXAlignment = Enum.TextXAlignment.Left
				descLbl2.TextTruncate = Enum.TextTruncate.AtEnd
				descLbl2.Parent = card

				local cfgLbl = Instance.new("TextLabel")
				cfgLbl.BackgroundTransparency = 1
				cfgLbl.Size = UDim2.new(1, -16, 0, 14)
				cfgLbl.Position = UDim2.new(0, 8, 0, 42)
				cfgLbl.Text = string.format("F:%.3g W:%.3g Vel:%.4g T:%.5g A:%.3g S:%.3g",
					entry.config.friction or 0, entry.config.weight or 0,
					entry.config.maxVel or 0, entry.config.maxTorque or 0,
					entry.config.maxAngle or 0, entry.config.steerSpeed or 0)
				cfgLbl.Font = Enum.Font.Gotham
				cfgLbl.TextSize = 9
				cfgLbl.TextColor3 = Color3.fromRGB(160, 200, 160)
				cfgLbl.TextXAlignment = Enum.TextXAlignment.Left
				cfgLbl.Parent = card

				local remainLbl = Instance.new("TextLabel")
				remainLbl.BackgroundTransparency = 1
				remainLbl.Size = UDim2.new(1, -16, 0, 18)
				remainLbl.Position = UDim2.new(0, 8, 0, 60)
				remainLbl.Text = "Expira em: " .. formatRemaining(entry.remaining)
				remainLbl.Font = Enum.Font.GothamBold
				remainLbl.TextSize = 11
				remainLbl.TextColor3 = C.yellow
				remainLbl.TextXAlignment = Enum.TextXAlignment.Left
				remainLbl.Parent = card
				addLiveCounter(remainLbl, entry.expiresAt)

				local delBtn = Instance.new("TextButton")
				delBtn.Size = UDim2.new(0.48, 0, 0, 30)
				delBtn.Position = UDim2.new(0.02, 0, 0, 90)
				delBtn.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
				delBtn.Text = "Remover"
				delBtn.Font = Enum.Font.GothamBold
				delBtn.TextSize = 11
				delBtn.TextColor3 = C.text
				delBtn.Parent = card
				uiCorner(delBtn, 6)

				local copyBtn = Instance.new("TextButton")
				copyBtn.Size = UDim2.new(0.48, 0, 0, 30)
				copyBtn.Position = UDim2.new(0.5, 0, 0, 90)
				copyBtn.BackgroundColor3 = C.green
				copyBtn.Text = "Aplicar no Carro"
				copyBtn.Font = Enum.Font.GothamBold
				copyBtn.TextSize = 11
				copyBtn.TextColor3 = C.text
				copyBtn.Parent = card
				uiCorner(copyBtn, 6)

				delBtn.MouseButton1Click:Connect(function()
					deletePublishedId(entry.id)
					task.wait(0.4)
					if refreshPublishList then refreshPublishList() end
					if refreshConfigList then refreshConfigList() end
				end)

				copyBtn.MouseButton1Click:Connect(function()
					applyConfigFromRemote(entry.config)
					if not currentCar then currentCar = findPlayerCar() end
					if currentCar then
						applyDrift("front", sharedConfig.friction, sharedConfig.weight)
						applyDrift("rear", sharedConfig.friction, sharedConfig.weight)
					end
					copyBtn.Text = "Aplicado!"
					task.delay(1.5, function() copyBtn.Text = "Aplicar no Carro" end)
				end)
			end
		end)
	end)
end

-- ABA CONFIG
local secSearch = createSection(pageConfig, "Pesquisar Autores", 1)
local searchRow = Instance.new("Frame")
searchRow.Size = UDim2.new(1, 0, 0, 32)
searchRow.BackgroundTransparency = 1
searchRow.LayoutOrder = 1
searchRow.Parent = secSearch

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, 0, 1, 0)
searchBox.BackgroundColor3 = C.inputBg
searchBox.PlaceholderText = "Digite nick do autor..."
searchBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
searchBox.Text = ""
searchBox.Font = Enum.Font.GothamMedium
searchBox.TextSize = 12
searchBox.TextColor3 = C.text
searchBox.ClearTextOnFocus = false
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.Parent = searchRow
uiCorner(searchBox, 6)
uiStroke(searchBox, C.border, 1)
local padSearch = Instance.new("UIPadding")
padSearch.PaddingLeft = UDim.new(0, 10)
padSearch.PaddingRight = UDim.new(0, 10)
padSearch.Parent = searchBox

local configStatus = Instance.new("TextLabel")
configStatus.BackgroundTransparency = 1
configStatus.Size = UDim2.new(1, 0, 0, 18)
configStatus.Text = "Clique em Atualizar para carregar"
configStatus.Font = Enum.Font.Gotham
configStatus.TextSize = 11
configStatus.TextColor3 = C.dim
configStatus.TextXAlignment = Enum.TextXAlignment.Left
configStatus.LayoutOrder = 2
configStatus.Parent = secSearch

local actionRow = Instance.new("Frame")
actionRow.Size = UDim2.new(1, 0, 0, 28)
actionRow.BackgroundTransparency = 1
actionRow.LayoutOrder = 3
actionRow.Parent = secSearch

local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.new(1, 0, 1, 0)
refreshBtn.BackgroundColor3 = C.apply
refreshBtn.Text = "Atualizar Lista"
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.TextSize = 11
refreshBtn.TextColor3 = C.text
refreshBtn.Parent = actionRow
uiCorner(refreshBtn, 6)
table.insert(themedButtons, refreshBtn)

local configListSection = createSection(pageConfig, "Autores (clique para ver configs)", 2)
local configListFrame = Instance.new("Frame")
configListFrame.Size = UDim2.new(1, 0, 0, 0)
configListFrame.AutomaticSize = Enum.AutomaticSize.Y
configListFrame.BackgroundTransparency = 1
configListFrame.LayoutOrder = 1
configListFrame.Parent = configListSection

local configListLayout = Instance.new("UIListLayout")
configListLayout.SortOrder = Enum.SortOrder.LayoutOrder
configListLayout.Padding = UDim.new(0, 8)
configListLayout.Parent = configListFrame

local detailSection = createSection(pageConfig, "Detalhes", 3)
detailLabel = Instance.new("TextLabel")
detailLabel.BackgroundTransparency = 1
detailLabel.Size = UDim2.new(1, 0, 0, 160)
detailLabel.Text = "Clique num autor para ver as configs dele"
detailLabel.Font = Enum.Font.Gotham
detailLabel.TextSize = 11
detailLabel.TextColor3 = C.dim
detailLabel.TextWrapped = true
detailLabel.TextYAlignment = Enum.TextYAlignment.Top
detailLabel.TextXAlignment = Enum.TextXAlignment.Left
detailLabel.LayoutOrder = 1
detailLabel.Parent = detailSection

function clearConfigList()
	for _, child in ipairs(configListFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

local cachedFixed = {}
function renderConfigList()
	clearConfigList()
	local query = string.lower(searchBox.Text or "")
	local filtered = {}
	for _, entry in ipairs(cachedFixed) do
		if query == "" then
			table.insert(filtered, entry)
		else
			local nameMatch = string.find(string.lower(entry.playerName), query, 1, true) ~= nil
			local displayMatch = string.find(string.lower(entry.displayName or ""), query, 1, true) ~= nil
			if nameMatch or displayMatch then table.insert(filtered, entry) end
		end
	end

	local authors = groupByAuthor(filtered)
	configStatus.Text = string.format("%d autores - %d publicacoes", #authors, #filtered)

	if #authors == 0 then
		local emptyLbl = Instance.new("TextLabel")
		emptyLbl.Size = UDim2.new(1, 0, 0, 40)
		emptyLbl.BackgroundTransparency = 1
		emptyLbl.Text = "Nada encontrado"
		emptyLbl.Font = Enum.Font.Gotham
		emptyLbl.TextSize = 11
		emptyLbl.TextColor3 = C.dim
		emptyLbl.Parent = configListFrame
		return
	end

	for i, author in ipairs(authors) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 70)
		card.BackgroundColor3 = author.isSelf and Color3.fromRGB(20, 40, 20) or C.inputBg
		card.LayoutOrder = i
		card.Parent = configListFrame
		uiCorner(card, 6)
		local stroke = uiStroke(card, C.border, 1)
		if author.isSelf then stroke.Color = C.green
		elseif author.isOnline then stroke.Color = Color3.fromRGB(0, 130, 60) end

		local dot = Instance.new("Frame")
		dot.Size = UDim2.new(0, 8, 0, 8)
		dot.Position = UDim2.new(0, 8, 0, 10)
		dot.BackgroundColor3 = author.isOnline and Color3.fromRGB(0, 200, 80) or Color3.fromRGB(90, 90, 90)
		dot.BorderSizePixel = 0
		dot.Parent = card
		uiCorner(dot, 4)

		local nameLbl = Instance.new("TextLabel")
		nameLbl.BackgroundTransparency = 1
		nameLbl.Size = UDim2.new(1, -110, 0, 18)
		nameLbl.Position = UDim2.new(0, 22, 0, 8)
		local tag = ""
		if author.isSelf then tag = "  (voce)"
		elseif author.isOnline then tag = "  online" end
		nameLbl.Text = author.displayName .. "  @" .. author.playerName .. tag
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 12
		nameLbl.TextColor3 = C.text
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = card

		local infoLbl = Instance.new("TextLabel")
		infoLbl.BackgroundTransparency = 1
		infoLbl.Size = UDim2.new(1, -110, 0, 16)
		infoLbl.Position = UDim2.new(0, 22, 0, 28)
		infoLbl.Text = tostring(#author.posts) .. " publicacao(oes)"
		infoLbl.Font = Enum.Font.Gotham
		infoLbl.TextSize = 10
		infoLbl.TextColor3 = C.dim
		infoLbl.TextXAlignment = Enum.TextXAlignment.Left
		infoLbl.Parent = card

		local likesLbl = Instance.new("TextLabel")
		likesLbl.BackgroundTransparency = 1
		likesLbl.Size = UDim2.new(1, -110, 0, 16)
		likesLbl.Position = UDim2.new(0, 22, 0, 44)
		likesLbl.Text = "❤️ " .. author.totalLikes .. " curtidas no total"
		likesLbl.Font = Enum.Font.Gotham
		likesLbl.TextSize = 10
		likesLbl.TextColor3 = C.pink
		likesLbl.TextXAlignment = Enum.TextXAlignment.Left
		likesLbl.Parent = card

		local viewBtn = Instance.new("TextButton")
		viewBtn.Size = UDim2.new(0, 70, 0, 40)
		viewBtn.Position = UDim2.new(1, -78, 0.5, -20)
		viewBtn.BackgroundColor3 = C.apply
		viewBtn.Text = "Ver"
		viewBtn.Font = Enum.Font.GothamBold
		viewBtn.TextSize = 11
		viewBtn.TextColor3 = C.text
		viewBtn.Parent = card
		uiCorner(viewBtn, 6)
		table.insert(themedButtons, viewBtn)

		viewBtn.MouseButton1Click:Connect(function()
			if showProfileView then
				showProfileView(author)
			end
		end)
	end
end

function refreshConfigList()
	configStatus.Text = "Buscando..."
	task.spawn(function()
		local all, err = scanFixedUsers()
		task.defer(function()
			if err and #all == 0 then
				configStatus.Text = "Erro: " .. tostring(err)
				return
			end
			cachedFixed = all
			renderConfigList()
		end)
	end)
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	renderConfigList()
end)

refreshBtn.MouseButton1Click:Connect(function()
	refreshConfigList()
end)

-- ABA PERFIL (abre quando clica num autor)
local profileHeader = createSection(pagePerfil, "Autor", 1)
local profileNameLbl = Instance.new("TextLabel")
profileNameLbl.BackgroundTransparency = 1
profileNameLbl.Size = UDim2.new(1, 0, 0, 24)
profileNameLbl.Text = "Nenhum autor selecionado"
profileNameLbl.Font = Enum.Font.GothamBold
profileNameLbl.TextSize = 14
profileNameLbl.TextColor3 = C.title
profileNameLbl.TextXAlignment = Enum.TextXAlignment.Left
profileNameLbl.LayoutOrder = 1
profileNameLbl.Parent = profileHeader

local profileInfoLbl = Instance.new("TextLabel")
profileInfoLbl.BackgroundTransparency = 1
profileInfoLbl.Size = UDim2.new(1, 0, 0, 18)
profileInfoLbl.Text = ""
profileInfoLbl.Font = Enum.Font.Gotham
profileInfoLbl.TextSize = 11
profileInfoLbl.TextColor3 = C.dim
profileInfoLbl.TextXAlignment = Enum.TextXAlignment.Left
profileInfoLbl.LayoutOrder = 2
profileInfoLbl.Parent = profileHeader

makeButton(profileHeader, "Voltar para Config", 3, function()
	pages["Config"].Visible = true
	pages["Perfil"].Visible = false
	tabs["Config"].BackgroundColor3 = C.tabActive
	tabs["Config"].TextColor3 = C.text
	tabs["Perfil"].BackgroundColor3 = C.tabInactive
	tabs["Perfil"].TextColor3 = C.dim
end)

local profileListSection = createSection(pagePerfil, "Publicacoes (mais recente primeiro)", 2)
local profileListFrame = Instance.new("Frame")
profileListFrame.Size = UDim2.new(1, 0, 0, 0)
profileListFrame.AutomaticSize = Enum.AutomaticSize.Y
profileListFrame.BackgroundTransparency = 1
profileListFrame.LayoutOrder = 1
profileListFrame.Parent = profileListSection

local profileListLayout = Instance.new("UIListLayout")
profileListLayout.SortOrder = Enum.SortOrder.LayoutOrder
profileListLayout.Padding = UDim.new(0, 8)
profileListLayout.Parent = profileListFrame

function clearProfileList()
	for _, child in ipairs(profileListFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

showProfileView = function(author)
	for n, b in pairs(tabs) do
		b.BackgroundColor3 = (n == "Perfil") and C.tabActive or C.tabInactive
		b.TextColor3 = (n == "Perfil") and C.text or C.dim
		pages[n].Visible = (n == "Perfil")
	end
	profileNameLbl.Text = author.displayName .. "  @" .. author.playerName
	profileInfoLbl.Text = tostring(#author.posts) .. " publicacoes - " .. author.totalLikes .. " curtidas no total"
	clearProfileList()

	for i, entry in ipairs(author.posts) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 130)
		card.BackgroundColor3 = C.inputBg
		card.LayoutOrder = i
		card.Parent = profileListFrame
		uiCorner(card, 6)
		uiStroke(card, C.border, 1)

		local nameLbl = Instance.new("TextLabel")
		nameLbl.BackgroundTransparency = 1
		nameLbl.Size = UDim2.new(1, -80, 0, 18)
		nameLbl.Position = UDim2.new(0, 8, 0, 6)
		nameLbl.Text = "🚗 " .. entry.carName
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 12
		nameLbl.TextColor3 = C.text
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = card

		local descLbl = Instance.new("TextLabel")
		descLbl.BackgroundTransparency = 1
		descLbl.Size = UDim2.new(1, -16, 0, 16)
		descLbl.Position = UDim2.new(0, 8, 0, 24)
		descLbl.Text = entry.description ~= "" and entry.description or "(sem descricao)"
		descLbl.Font = Enum.Font.Gotham
		descLbl.TextSize = 10
		descLbl.TextColor3 = C.dim
		descLbl.TextXAlignment = Enum.TextXAlignment.Left
		descLbl.TextTruncate = Enum.TextTruncate.AtEnd
		descLbl.Parent = card

		local cfgLbl = Instance.new("TextLabel")
		cfgLbl.BackgroundTransparency = 1
		cfgLbl.Size = UDim2.new(1, -16, 0, 14)
		cfgLbl.Position = UDim2.new(0, 8, 0, 42)
		cfgLbl.Text = string.format("F:%.3g W:%.3g Vel:%.4g T:%.5g A:%.3g S:%.3g",
			entry.config.friction or 0, entry.config.weight or 0,
			entry.config.maxVel or 0, entry.config.maxTorque or 0,
			entry.config.maxAngle or 0, entry.config.steerSpeed or 0)
		cfgLbl.Font = Enum.Font.Gotham
		cfgLbl.TextSize = 9
		cfgLbl.TextColor3 = Color3.fromRGB(160, 200, 160)
		cfgLbl.TextXAlignment = Enum.TextXAlignment.Left
		cfgLbl.Parent = card

		local dateLbl = Instance.new("TextLabel")
		dateLbl.BackgroundTransparency = 1
		dateLbl.Size = UDim2.new(1, -16, 0, 14)
		dateLbl.Position = UDim2.new(0, 8, 0, 58)
		dateLbl.Text = formatDate(entry.timestamp) .. " - Expira em " .. formatRemaining(entry.remaining)
		dateLbl.Font = Enum.Font.Gotham
		dateLbl.TextSize = 9
		dateLbl.TextColor3 = C.dim
		dateLbl.TextXAlignment = Enum.TextXAlignment.Left
		dateLbl.Parent = card

		local likeBtn = Instance.new("TextButton")
		likeBtn.Size = UDim2.new(0.3, 0, 0, 30)
		likeBtn.Position = UDim2.new(0.02, 0, 0, 90)
		likeBtn.BackgroundColor3 = C.apply
		likeBtn.Text = "❤️ Curtir"
		likeBtn.Font = Enum.Font.GothamBold
		likeBtn.TextSize = 11
		likeBtn.TextColor3 = C.pink
		likeBtn.Parent = card
		uiCorner(likeBtn, 6)

		local likeCountLbl = Instance.new("TextLabel")
		likeCountLbl.BackgroundTransparency = 1
		likeCountLbl.Size = UDim2.new(0.3, 0, 0, 30)
		likeCountLbl.Position = UDim2.new(0.34, 0, 0, 90)
		likeCountLbl.Text = "❤️ " .. (entry.likes or 0)
		likeCountLbl.Font = Enum.Font.GothamBold
		likeCountLbl.TextSize = 12
		likeCountLbl.TextColor3 = C.pink
		likeCountLbl.Parent = card

		local copyBtn = Instance.new("TextButton")
		copyBtn.Size = UDim2.new(0.32, 0, 0, 30)
		copyBtn.Position = UDim2.new(0.66, 0, 0, 90)
		copyBtn.BackgroundColor3 = C.green
		copyBtn.Text = "Copiar"
		copyBtn.Font = Enum.Font.GothamBold
		copyBtn.TextSize = 11
		copyBtn.TextColor3 = C.text
		copyBtn.Parent = card
		uiCorner(copyBtn, 6)

		likeBtn.MouseButton1Click:Connect(function()
			local newCount = toggleLike(entry.id, entry.likes or 0)
			entry.likes = newCount
			likeCountLbl.Text = "❤️ " .. newCount
		end)

		copyBtn.MouseButton1Click:Connect(function()
			applyConfigFromRemote(entry.config)
			if not currentCar then currentCar = findPlayerCar() end
			if currentCar then
				applyDrift("front", sharedConfig.friction, sharedConfig.weight)
				applyDrift("rear", sharedConfig.friction, sharedConfig.weight)
			end
			copyBtn.Text = "Aplicado!"
			task.delay(1.5, function() copyBtn.Text = "Copiar" end)
		end)
	end
end
-- ABA JOGADORES
local secOnline = createSection(pageJogadores, "Jogadores Online Agora", 1)

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

function clearPlayersList()
	for _, child in ipairs(playersListFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

local isRefreshingPlayers = false

local function renderPlayersList(list, err)
	clearPlayersList()
	if err and #list == 0 then
		onlineStatus.Text = "Erro: " .. tostring(err)
	elseif #list == 0 then
		onlineStatus.Text = "Ninguem online agora | " .. lastPublishMsg
	else
		onlineStatus.Text = tostring(#list) .. " online - atualiza a cada " .. AUTO_REFRESH_INTERVAL .. "s"
	end

	for i, entry in ipairs(list) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 90)
		card.BackgroundColor3 = entry.isSelf and Color3.fromRGB(20, 40, 20) or C.inputBg
		card.LayoutOrder = i
		card.Parent = playersListFrame
		uiCorner(card, 6)
		local cardStroke = uiStroke(card, entry.isSelf and C.green or C.border, 1)
		if entry.sameServer and not entry.isSelf then
			cardStroke.Color = Color3.fromRGB(0, 130, 60)
		end

		local dot = Instance.new("Frame")
		dot.Size = UDim2.new(0, 8, 0, 8)
		dot.Position = UDim2.new(0, 8, 0, 10)
		dot.BackgroundColor3 = Color3.fromRGB(0, 200, 80)
		dot.BorderSizePixel = 0
		dot.Parent = card
		uiCorner(dot, 4)

		local nameLbl = Instance.new("TextLabel")
		nameLbl.BackgroundTransparency = 1
		nameLbl.Size = UDim2.new(1, -100, 0, 18)
		nameLbl.Position = UDim2.new(0, 22, 0, 4)
		local tag = ""
		if entry.isSelf then tag = "  (voce)"
		elseif entry.sameServer then tag = "  (mesmo servidor)"
		else tag = "  (outro servidor)" end
		nameLbl.Text = entry.displayName .. "  @" .. entry.playerName .. tag
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 11
		nameLbl.TextColor3 = C.text
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = card

		local cfgLbl = Instance.new("TextLabel")
		cfgLbl.BackgroundTransparency = 1
		cfgLbl.Size = UDim2.new(1, -100, 0, 14)
		cfgLbl.Position = UDim2.new(0, 22, 0, 26)
		cfgLbl.Text = string.format("F:%.3g W:%.3g Vel:%.4g T:%.5g A:%.3g S:%.3g",
			entry.config.friction or 0, entry.config.weight or 0,
			entry.config.maxVel or 0, entry.config.maxTorque or 0,
			entry.config.maxAngle or 0, entry.config.steerSpeed or 0)
		cfgLbl.Font = Enum.Font.Gotham
		cfgLbl.TextSize = 9
		cfgLbl.TextColor3 = Color3.fromRGB(160, 200, 160)
		cfgLbl.TextXAlignment = Enum.TextXAlignment.Left
		cfgLbl.Parent = card

		local timeLbl = Instance.new("TextLabel")
		timeLbl.BackgroundTransparency = 1
		timeLbl.Size = UDim2.new(1, -100, 0, 14)
		timeLbl.Position = UDim2.new(0, 22, 0, 46)
		timeLbl.Text = "Visto ha " .. formatAgo(entry.age)
		timeLbl.Font = Enum.Font.Gotham
		timeLbl.TextSize = 9
		timeLbl.TextColor3 = C.dim
		timeLbl.TextXAlignment = Enum.TextXAlignment.Left
		timeLbl.Parent = card

		local btnRow = Instance.new("Frame")
		btnRow.Size = UDim2.new(0, 60, 0, 80)
		btnRow.Position = UDim2.new(1, -66, 0.5, -40)
		btnRow.BackgroundTransparency = 1
		btnRow.Parent = card

		local btnLayout = Instance.new("UIListLayout")
		btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
		btnLayout.Padding = UDim.new(0, 4)
		btnLayout.Parent = btnRow

		local verBtn = Instance.new("TextButton")
		verBtn.Size = UDim2.new(1, 0, 0, 36)
		verBtn.BackgroundColor3 = C.apply
		verBtn.Text = "Ver"
		verBtn.Font = Enum.Font.GothamBold
		verBtn.TextSize = 10
		verBtn.TextColor3 = C.text
		verBtn.LayoutOrder = 1
		verBtn.Parent = btnRow
		uiCorner(verBtn, 6)
		table.insert(themedButtons, verBtn)

		local copyBtn = Instance.new("TextButton")
		copyBtn.Size = UDim2.new(1, 0, 0, 36)
		copyBtn.BackgroundColor3 = C.green
		copyBtn.Text = "Copiar"
		copyBtn.Font = Enum.Font.GothamBold
		copyBtn.TextSize = 10
		copyBtn.TextColor3 = C.text
		copyBtn.LayoutOrder = 2
		copyBtn.Parent = btnRow
		uiCorner(copyBtn, 6)

		verBtn.MouseButton1Click:Connect(function()
			selectedRemoteConfig = entry.config
			selectedConfigEntry = entry
			local lines = {
				entry.displayName .. "  (@" .. entry.playerName .. ")",
				"Visto ha " .. formatAgo(entry.age),
				"----------",
				string.format("Friction: %.4g", entry.config.friction or 0),
				string.format("Weight: %.4g", entry.config.weight or 0),
				string.format("Vel Motor: %.4g", entry.config.maxVel or 0),
				string.format("Torque: %.4g", entry.config.maxTorque or 0),
				string.format("Max Angle: %.4g", entry.config.maxAngle or 0),
				string.format("Steer Speed: %.4g", entry.config.steerSpeed or 0),
			}
			if detailLabel then detailLabel.Text = table.concat(lines, "\n") end
		end)

		copyBtn.MouseButton1Click:Connect(function()
			applyConfigFromRemote(entry.config)
			if not currentCar then currentCar = findPlayerCar() end
			if currentCar then
				applyDrift("front", sharedConfig.friction, sharedConfig.weight)
				applyDrift("rear", sharedConfig.friction, sharedConfig.weight)
			end
			copyBtn.Text = "Aplicado!"
			task.delay(1.5, function() copyBtn.Text = "Copiar" end)
		end)
	end
end

refreshPlayersList = function()
	if isRefreshingPlayers then return end
	isRefreshingPlayers = true
	task.spawn(function()
		publishOnline()
		task.wait(0.3)
		local list, err = scanOnlineUsers()
		task.defer(function()
			isRefreshingPlayers = false
			renderPlayersList(list, err)
		end)
	end)
end

makeButton(secOnline, "Atualizar Agora", 3, function()
	refreshPlayersList()
end)

task.spawn(function()
	task.wait(2)
	while true do
		task.wait(AUTO_REFRESH_INTERVAL)
		if pages["Jogadores"] and pages["Jogadores"].Visible then
			refreshPlayersList()
		end
	end
end)
-- MOBILE (setas)
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
	motorLockBtn.Text = motorLocked and "X" or "L"
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

-- Abrir/Fechar menu
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
		toggleBtn.Text = "X"
		openMenu()
	else
		toggleBtn.Text = "Drift X"
		closeMenu()
	end
end)
-- Teclado
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

-- Loop principal
local updateTick, wasInCar = 0, false
local publishTick = 0

local conn3 = RunService.RenderStepped:Connect(function(dt)
	updateTick += dt
	publishTick += dt

	if publishTick >= 25 then
		publishTick = 0
		if currentCar and isPlayerInCar(currentCar) then
			publishOnline()
		end
	end

	if updateTick >= 0.35 then
		updateTick = 0
		local found = findPlayerCar()
		if found ~= currentCar then
			currentCar = found
			driftOriginals = { front = nil, rear = nil }
			resetSteerOnExit()
			if found then publishOnline() end
		end
	end

	if not currentCar then
		currentCar = findPlayerCar()
	end

	local inCar = isPlayerInCar(currentCar)
	if wasInCar and not inCar then
		resetSteerOnExit()
		if motorState.enabled then aplicarMotor("Parar") end
		currentCar = nil
	end
	if (not wasInCar) and inCar then
		steerState.isA = false
		steerState.isD = false
		steerState.currentSteer = 0
		if steerState.enabled then applySteerAngle(0) end
		publishOnline()
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

task.defer(function()
	task.wait(0.15)
	local vp = camera.ViewportSize
	local w = menu.AbsoluteSize.X
	local h = menu.AbsoluteSize.Y
	if w > 0 and h > 0 then
		menu.Position = UDim2.new(0, (vp.X - w) / 2, 0, (vp.Y - h) / 2)
	end
end)

-- Inicialização
task.spawn(function()
	task.wait(0.5)
	loadMyPublishedIds()
	task.wait(1)
	cleanExpiredMyPosts()
	task.wait(1)
	if not isFixedPublished then
		publishOnline()
	end
end)
-- Ajustes finais e cleanup de publicações expiradas periodicamente
task.spawn(function()
	while true do
		task.wait(300) -- a cada 5 minutos
		if isFixedPublished then
			local all = scanFixedUsers()
			local mineCount = 0
			for _, e in ipairs(all) do
				if e.isSelf then mineCount = mineCount + 1 end
			end
			if mineCount == 0 then
				isFixedPublished = false
				publishedIds = {}
			end
		end
	end
end)

-- Publicar automático ao entrar no carro (mantém online na aba Jogadores)
player.CharacterAdded:Connect(function()
	task.wait(2)
	if not isFixedPublished then
		publishOnline()
	end
end)

print("[DriftX] v6.0 carregado!")
print("[DriftX] Abra o menu com o botao 'Drift X' no lado esquerdo da tela")
-- Comandos extras (opcional)
-- Se quiser adicionar algum atalho ou função extra depois, coloque aqui.

-- ✅ SCRIPT COMPLETO v6.0
-- Recursos:
-- - Aba Carro: Drift, Motor, Direcao
-- - Aba HUD: Setas mobile
-- - Aba Painel: Tamanho UI + temas
-- - Aba Jogadores: Quem ta online agora (auto-refresh 4s) + botao Copiar
-- - Aba Publicar: Criar quantas publicacoes quiser (sem limite), 30 dias cada
-- - Aba Config: Lista de autores agrupados - clique pra ver todas as configs dele
-- - Aba Perfil: Publicacoes do autor (mais recente primeiro) com coracao (curtida)
-- - Cada publicacao: pode curtir (1x por usuario) e copiar config
-- - Auto-limpeza de publicacoes expiradas
-- - Slots unicos com ID aleatorio (sem conflito entre usuarios)
-- - Firebase: drift-x-3edf5-default-rtdb.firebaseio.com
