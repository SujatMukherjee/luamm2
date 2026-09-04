-- Delta Ultra-Reliable Collector & Automation Suite (v2.2: Full Feature Complete)
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

-- Anti-AFK Kick Prevention
player.Idled:Connect(function()
	VirtualUser:CaptureController()
	VirtualUser:ClickButton2(Vector2.new())
end)

local rng = Random.new(tick() + player.UserId + math.random(1, 100000))

local visualFolder = Workspace:FindFirstChild("DeltaNavVisuals") or Instance.new("Folder", Workspace)
visualFolder.Name = "DeltaNavVisuals"
visualFolder:ClearAllChildren()

local espFolder = Workspace:FindFirstChild("DeltaESPVisuals") or Instance.new("Folder", Workspace)
espFolder.Name = "DeltaESPVisuals"
espFolder:ClearAllChildren()

local activeMoverConnection = nil
local activeMode = "Off"
local targetPosition = nil
local statusMessage = "Idle"
local targetCoinName = "None"
local activeCoins = {}
local coinQueue = {}
local failedCoinBlacklist = {}

local loopToken = 0
local currentWaypoints = {}
local waypointIndex = 1
local consecutiveStuckCount = 0

-- CONFIGURABLE THRESHOLDS & STATES
local SAFE_SPEED = 24
local STUCK_THRESHOLD = 0.6
local ESP_ENABLED = true
local MAX_CAPACITY = 40
local collectedCount = 0
local totalCoinsInGame = 0
local autoRotateEnabled = false
local instantKillEnabled = false
local godModeEnabled = false
local teleportCoinsEnabled = false
local promptAutomationEnabled = true
local serverHopEnabled = false
local currentPlayerRole = "Default"

-- Optimized Object Caching to Eliminate Lag Spikes
local cachedCoinKeywords = {"coin", "ring", "cash", "token", "gold", "gem", "collect", "star", "point", "money", "crystal"}

local function extractPosition(obj)
	if not obj then return nil end
	if obj:IsA("BasePart") then
		return obj.Position
	elseif obj:IsA("Model") then
		if obj.PrimaryPart then
			return obj.PrimaryPart.Position
		else
			local part = obj:FindFirstChildWhichIsA("BasePart", true)
			if part then return part.Position end
		end
	end
	return nil
end

-- Role Detection for Murderer & Sheriff (MM2 Style Support)
local function findMurdererAndSheriff()
	local murderer, sheriff = nil, nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			local char = p.Character
			local backpack = p:FindFirstChildOfClass("Backpack")
			
			local hasKnife = char:FindFirstChild("Knife") or (backpack and backpack:FindFirstChild("Knife"))
			local hasGun = char:FindFirstChild("Gun") or char:FindFirstChild("Revolver") or (backpack and (backpack:FindFirstChild("Gun") or backpack:FindFirstChild("Revolver")))
			
			if hasKnife then murderer = p end
			if hasGun then sheriff = p end
		end
	end
	return murderer, sheriff
end

local function updatePlayerRole()
	local detectedRole = player.Team and player.Team.Name or "Default"
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local roleStat = leaderstats:FindFirstChild("Role") or leaderstats:FindFirstChild("Class") or leaderstats:FindFirstChild("Job")
		if roleStat and roleStat:IsA("ValueBase") then
			detectedRole = tostring(roleStat.Value)
		end
	end
	if player:GetAttribute("Role") then
		detectedRole = tostring(player:GetAttribute("Role"))
	end
	
	currentPlayerRole = detectedRole
	local roleLower = string.lower(currentPlayerRole)
	
	if string.find(roleLower, "speed") or string.find(roleLower, "runner") then
		SAFE_SPEED = 32
	elseif string.find(roleLower, "tank") or string.find(roleLower, "heavy") then
		SAFE_SPEED = 18
	else
		SAFE_SPEED = 24
	end
	return currentPlayerRole
end

-- UI Setup
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeltaNavUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 370, 0, 650)
mainFrame.Position = UDim2.new(0, 20, 0, 20)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
mainFrame.BackgroundTransparency = 0.15
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 35)
topBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
topBar.BorderSizePixel = 0
topBar.Parent = mainFrame
Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 8)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -70, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 13
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "Delta Ultra Collector v2.2 (Complete)"
titleLabel.Parent = topBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 28, 0, 28)
minBtn.Position = UDim2.new(1, -64, 0, 3)
minBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minBtn.TextSize = 14
minBtn.Font = Enum.Font.SourceSansBold
minBtn.Text = "-"
minBtn.Parent = topBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -32, 0, 3)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize = 12
closeBtn.Font = Enum.Font.SourceSansBold
closeBtn.Text = "X"
closeBtn.Parent = topBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local contentContainer = Instance.new("Frame")
contentContainer.Size = UDim2.new(1, 0, 1, -35)
contentContainer.Position = UDim2.new(0, 0, 0, 35)
contentContainer.BackgroundTransparency = 1
contentContainer.Parent = mainFrame

local function createButton(name, posY, color, text)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0, 330, 0, 25)
	btn.Position = UDim2.new(0, 20, 0, posY)
	btn.BackgroundColor3 = color
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 12
	btn.Font = Enum.Font.SourceSansBold
	btn.Text = text
	btn.Parent = contentContainer
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	return btn
end

local coinBtn = createButton("CoinHuntButton", 10, Color3.fromRGB(40, 40, 40), "Coin Hunt: OFF")
local wanderBtn = createButton("RandomWanderButton", 38, Color3.fromRGB(40, 40, 40), "Random Wander: OFF")
local tpCoinsBtn = createButton("TpCoinsButton", 66, Color3.fromRGB(60, 60, 60), "Teleport Coins: OFF")
local instantKillBtn = createButton("InstantKillButton", 94, Color3.fromRGB(60, 60, 60), "Instant Kill: OFF")
local tpMurdererBtn = createButton("TpMurdererButton", 122, Color3.fromRGB(160, 40, 40), "Teleport to Murderer")
local tpSheriffBtn = createButton("TpSheriffButton", 150, Color3.fromRGB(40, 100, 180), "Teleport to Sheriff")
local promptBtn = createButton("PromptButton", 178, Color3.fromRGB(0, 170, 0), "Instant Prompts: ON")
local godModeBtn = createButton("GodModeButton", 206, Color3.fromRGB(60, 60, 60), "God Mode: OFF")
local serverHopBtn = createButton("ServerHopButton", 234, Color3.fromRGB(60, 60, 60), "Auto Server Hop: OFF")
local espBtn = createButton("ESPButton", 262, Color3.fromRGB(0, 120, 200), "ESP (Role/Death): ON")

local logBox = Instance.new("TextLabel")
logBox.Size = UDim2.new(0, 330, 0, 210)
logBox.Position = UDim2.new(0, 20, 0, 292)
logBox.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
logBox.BackgroundTransparency = 0.2
logBox.TextColor3 = Color3.fromRGB(0, 255, 128)
logBox.TextSize = 11
logBox.Font = Enum.Font.Code
logBox.TextXAlignment = Enum.TextXAlignment.Left
logBox.TextYAlignment = Enum.TextYAlignment.Top
logBox.TextWrapped = true
logBox.Text = "=== OPTIMIZED METRICS v2.2 ===\nInitializing Complete Suite..."
logBox.Parent = contentContainer
Instance.new("UICorner", logBox).CornerRadius = UDim.new(0, 6)

-- UI Interactions
local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	if isMinimized then
		minBtn.Text = "+"
		mainFrame.Size = UDim2.new(0, 370, 0, 35)
		contentContainer.Visible = false
	else
		minBtn.Text = "-"
		mainFrame.Size = UDim2.new(0, 370, 0, 650)
		contentContainer.Visible = true
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	activeMode = "Off"
	instantKillEnabled = false
	godModeEnabled = false
	teleportCoinsEnabled = false
	if activeMoverConnection then activeMoverConnection:Disconnect() end
	visualFolder:ClearAllChildren()
	espFolder:ClearAllChildren()
	screenGui:Destroy()
end)

espBtn.MouseButton1Click:Connect(function()
	ESP_ENABLED = not ESP_ENABLED
	espBtn.Text = ESP_ENABLED and "ESP (Role/Death): ON" or "ESP (Role/Death): OFF"
	espBtn.BackgroundColor3 = ESP_ENABLED and Color3.fromRGB(0, 120, 200) or Color3.fromRGB(60, 60, 60)
	if not ESP_ENABLED then espFolder:ClearAllChildren() end
end)

tpCoinsBtn.MouseButton1Click:Connect(function()
	teleportCoinsEnabled = not teleportCoinsEnabled
	tpCoinsBtn.Text = teleportCoinsEnabled and "Teleport Coins: ON" or "Teleport Coins: OFF"
	tpCoinsBtn.BackgroundColor3 = teleportCoinsEnabled and Color3.fromRGB(0, 170, 0) or Color3.fromRGB(60, 60, 60)
end)

instantKillBtn.MouseButton1Click:Connect(function()
	instantKillEnabled = not instantKillEnabled
	instantKillBtn.Text = instantKillEnabled and "Instant Kill: ON" or "Instant Kill: OFF"
	instantKillBtn.BackgroundColor3 = instantKillEnabled and Color3.fromRGB(180, 40, 40) or Color3.fromRGB(60, 60, 60)
end)

promptBtn.MouseButton1Click:Connect(function()
	promptAutomationEnabled = not promptAutomationEnabled
	promptBtn.Text = promptAutomationEnabled and "Instant Prompts: ON" or "Instant Prompts: OFF"
	promptBtn.BackgroundColor3 = promptAutomationEnabled and Color3.fromRGB(0, 170, 0) or Color3.fromRGB(60, 60, 60)
end)

godModeBtn.MouseButton1Click:Connect(function()
	godModeEnabled = not godModeEnabled
	godModeBtn.Text = godModeEnabled and "God Mode: ON" or "God Mode: OFF"
	godModeBtn.BackgroundColor3 = godModeEnabled and Color3.fromRGB(0, 170, 0) or Color3.fromRGB(60, 60, 60)
end)

serverHopBtn.MouseButton1Click:Connect(function()
	serverHopEnabled = not serverHopEnabled
	serverHopBtn.Text = serverHopEnabled and "Auto Server Hop: ON" or "Auto Server Hop: OFF"
	serverHopBtn.BackgroundColor3 = serverHopEnabled and Color3.fromRGB(180, 40, 40) or Color3.fromRGB(60, 60, 60)
end)

tpMurdererBtn.MouseButton1Click:Connect(function()
	local murderer = findMurdererAndSheriff()
	if murderer and murderer.Character and murderer.Character:FindFirstChild("HumanoidRootPart") then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.CFrame = murderer.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3) end
	end
end)

tpSheriffBtn.MouseButton1Click:Connect(function()
	local _, sheriff = findMurdererAndSheriff()
	if sheriff and sheriff.Character and sheriff.Character:FindFirstChild("HumanoidRootPart") then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.CFrame = sheriff.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3) end
	end
end)

-- God Mode Loop
task.spawn(function()
	while true do
		task.wait(0.1)
		if godModeEnabled then
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				pcall(function()
					humanoid.Health = humanoid.MaxHealth
					humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
				end)
			end
		end
	end
end)

-- Proximity Prompt Automation Loop
task.spawn(function()
	while true do
		task.wait(0.2)
		if promptAutomationEnabled then
			pcall(function()
				for _, obj in ipairs(Workspace:GetDescendants()) do
					if obj:IsA("ProximityPrompt") then
						obj.HoldDuration = 0
						local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						if hrp and obj.Parent and obj.Parent:IsA("BasePart") then
							if (hrp.Position - obj.Parent.Position).Magnitude <= (obj.MaxActivationDistance or 32) then
								fireproximityprompt(obj)
							end
						end
					end
				end
			end)
		end
	end
end)

-- Optimized Scan Logic
local function scanAllCoins(rootPos)
	local coins = {}
	local char = player.Character
	local currentTime = tick()

	for id, timeAdded in pairs(failedCoinBlacklist) do
		if currentTime - timeAdded > 20 then failedCoinBlacklist[id] = nil end
	end

	for _, obj in ipairs(Workspace:GetDescendants()) do
		if char and (obj == char or obj:IsDescendantOf(char)) then continue end
		if failedCoinBlacklist[obj] then continue end

		local nameLower = string.lower(obj.Name)
		local matched = false
		for _, kw in ipairs(cachedCoinKeywords) do
			if string.find(nameLower, kw, 1, true) then
				matched = true
				break
			end
		end

		if matched then
			local pos = extractPosition(obj)
			if pos and (rootPos - pos).Magnitude < 350 then
				table.insert(coins, {pos = pos, name = obj.Name, instance = obj})
			end
		end
	end
	return coins
end

local function countTotalGameCoins()
	local count = 0
	for _, obj in ipairs(Workspace:GetDescendants()) do
		local nameLower = string.lower(obj.Name)
		for _, kw in ipairs(cachedCoinKeywords) do
			if string.find(nameLower, kw, 1, true) and extractPosition(obj) then
				count = count + 1
				break
			end
		end
	end
	return count
end

-- Teleport Coins Loop
task.spawn(function()
	while true do
		task.wait(0.12)
		if teleportCoinsEnabled then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				if collectedCount >= MAX_CAPACITY then collectedCount = 0 end
				local coins = scanAllCoins(hrp.Position)
				if #coins > 0 then
					local nearest = coins[1]
					local minDst = (hrp.Position - nearest.pos).Magnitude
					for _, c in ipairs(coins) do
						local dst = (hrp.Position - c.pos).Magnitude
						if dst < minDst then minDst = dst; nearest = c end
					end
					if nearest then
						statusMessage = "TP Coin: " .. nearest.name
						hrp.CFrame = CFrame.new(nearest.pos + Vector3.new(0, 0.5, 0))
						collectedCount = collectedCount + 1
						task.wait(0.05)
					end
				else
					statusMessage = "Scanning TP Coins..."
				end
			end
		end
	end
end)

-- Instant Kill Loop
task.spawn(function()
	while true do
		task.wait(0.1)
		if instantKillEnabled then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			
			if hrp and humanoid and humanoid.Health > 0 then
				local murderer, _ = findMurdererAndSheriff()
				local targetChar = nil
				
				if murderer and murderer.Character and murderer.Character ~= char then
					targetChar = murderer.Character
				else
					local minDst = 250
					for _, p in ipairs(Players:GetPlayers()) do
						if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
							local pHum = p.Character:FindFirstChildOfClass("Humanoid")
							if pHum and pHum.Health > 0 then
								local dst = (hrp.Position - p.Character.HumanoidRootPart.Position).Magnitude
								if dst < minDst then minDst = dst; targetChar = p.Character end
							end
						end
					end
				end
				
				if targetChar and targetChar:FindFirstChild("HumanoidRootPart") then
					hrp.CFrame = targetChar.HumanoidRootPart.CFrame * CFrame.new(0, 0, 2)
					local tool = char:FindFirstChildOfClass("Tool") or (player:FindFirstChildOfClass("Backpack") and player.Backpack:FindFirstChildOfClass("Tool"))
					if tool then
						if tool.Parent ~= char then humanoid:EquipTool(tool) end
						pcall(function() tool:Activate() end)
					end
				end
			end
		end
	end
end)

-- Enhanced ESP Background Worker with Role Coloring
task.spawn(function()
	while true do
		task.wait(1)
		if ESP_ENABLED then
			espFolder:ClearAllChildren()
			local murderer, sheriff = findMurdererAndSheriff()
			
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
					local hl = Instance.new("Highlight")
					hl.Adornee = p.Character
					
					if p == murderer then
						hl.FillColor = Color3.fromRGB(255, 30, 30) -- Red for Murderer
					elseif p == sheriff then
						hl.FillColor = Color3.fromRGB(30, 144, 255) -- Blue for Sheriff
					else
						hl.FillColor = Color3.fromRGB(46, 204, 113) -- Green for Innocents
					end
					
					hl.OutlineColor = Color3.fromRGB(255, 255, 255)
					hl.FillTransparency = 0.4
					hl.Parent = espFolder
				end
			end
		end
	end
end)

-- Auto Server Hopping (Low Player or Yield Drop Check)
task.spawn(function()
	while true do
		task.wait(10)
		if serverHopEnabled then
			if #Players:GetPlayers() <= 2 then
				statusMessage = "Hopping Servers..."
				pcall(function()
					local servers = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
					if servers and servers.data then
						for _, s in ipairs(servers.data) do
							if s.playing < s.maxPlayers and s.id ~= game.JobId then
								TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, player)
								break
							end
						end
					end
				end)
			end
		end
	end
end)

-- Route & Navigation Engine with Fallback Re-pathing
local function buildCoinRoute(startPos, rawCoins)
	local route, pool = {}, {}
	for _, c in ipairs(rawCoins) do table.insert(pool, c) end
	
	local currentPos = startPos
	while #pool > 0 do
		local bestIdx = 1
		local bestScore = math.huge
		for i, c in ipairs(pool) do
			local score = (currentPos - c.pos).Magnitude
			if score < bestScore then bestScore = score; bestIdx = i end
		end
		local chosen = table.remove(pool, bestIdx)
		table.insert(route, chosen)
		currentPos = chosen.pos
	end
	return route
end

local function computePathTo(startPos, endPos)
	local path = PathfindingService:CreatePath({AgentRadius = 2, AgentHeight = 5, AgentCanJump = true})
	local success = pcall(function() path:ComputeAsync(startPos, endPos) end)
	if success and path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints()
	else
		-- Fallback linear/raycast interpolation waypoints if Pathfinding fails
		local backupWaypoints = {}
		table.insert(backupWaypoints, {Position = startPos, Action = Enum.PathWaypointAction.Walk})
		table.insert(backupWaypoints, {Position = endPos, Action = Enum.PathWaypointAction.Walk})
		return backupWaypoints
	end
end

local executeMovementLoop
local function startNavigation()
	if activeMode == "Off" then return end
	if collectedCount >= MAX_CAPACITY then collectedCount = 0 end
	
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local rootPart = char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return end

	if activeMode == "CoinHunt" then
		if #coinQueue == 0 then
			activeCoins = scanAllCoins(rootPart.Position)
			coinQueue = buildCoinRoute(rootPart.Position, activeCoins)
		end

		local validPathFound = false
		while #coinQueue > 0 and not validPathFound do
			local nextCoin = table.remove(coinQueue, 1)
			targetPosition = nextCoin.pos
			targetCoinName = nextCoin.name
			currentWaypoints = computePathTo(rootPart.Position, targetPosition)
			if currentWaypoints and #currentWaypoints > 0 then
				validPathFound = true
				statusMessage = "Hunting: " .. targetCoinName
			else
				if nextCoin.instance then failedCoinBlacklist[nextCoin.instance] = tick() end
			end
		end

		if not validPathFound then
			statusMessage = "Rescanning Area..."
			task.wait(0.3)
			coinQueue = {}
			if activeMoverConnection then activeMoverConnection:Disconnect() end
			task.spawn(executeMovementLoop)
			return
		end
	elseif activeMode == "RandomWander" then
		targetCoinName = "N/A"
		statusMessage = "Wandering..."
		local ang = rng:NextNumber() * math.pi * 2
		local candidatePos = rootPart.Position + Vector3.new(math.cos(ang) * 25, 0, math.sin(ang) * 25)
		currentWaypoints = computePathTo(rootPart.Position, candidatePos)
		if not currentWaypoints then
			task.wait(0.3)
			if activeMoverConnection then activeMoverConnection:Disconnect() end
			task.spawn(executeMovementLoop)
			return
		end
		targetPosition = candidatePos
	end

	waypointIndex = 1
	local currentToken = loopToken
	if activeMoverConnection then activeMoverConnection:Disconnect() end

	local stuckTimer = 0
	local lastPosCheck = rootPart.Position

	activeMoverConnection = RunService.Heartbeat:Connect(function(dt)
		if activeMode == "Off" or loopToken ~= currentToken or not char.Parent then
			if activeMoverConnection then activeMoverConnection:Disconnect() end
			return
		end

		humanoid.WalkSpeed = SAFE_SPEED
		local wp = currentWaypoints[waypointIndex]
		if not wp then
			activeMoverConnection:Disconnect()
			if activeMode == "CoinHunt" then collectedCount = collectedCount + 1 end
			task.spawn(executeMovementLoop)
			return
		end

		humanoid:MoveTo(wp.Position)
		if wp.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end

		if (rootPart.Position - lastPosCheck).Magnitude < 0.2 then
			stuckTimer = stuckTimer + dt
			if stuckTimer > STUCK_THRESHOLD then
				humanoid.Jump = true
				stuckTimer = 0
				humanoid:MoveTo(rootPart.Position + Vector3.new(rng:NextInteger(-12, 12), 0, rng:NextInteger(-12, 12)))
			end
		else
			stuckTimer = 0
			lastPosCheck = rootPart.Position
		end

		if (rootPart.Position - wp.Position).Magnitude < 3.5 then
			waypointIndex = waypointIndex + 1
		end
	end)
end

executeMovementLoop = function()
	task.spawn(startNavigation)
end

coinBtn.MouseButton1Click:Connect(function()
	loopToken = loopToken + 1
	activeMode = (activeMode == "CoinHunt") and "Off" or "CoinHunt"
	coinBtn.Text = activeMode == "CoinHunt" and "Coin Hunt: ON" or "Coin Hunt: OFF"
	coinBtn.BackgroundColor3 = activeMode == "CoinHunt" and Color3.fromRGB(0, 170, 0) or Color3.fromRGB(40, 40, 40)
	wanderBtn.Text = "Random Wander: OFF"
	wanderBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	coinQueue = {}
	if activeMode == "CoinHunt" then executeMovementLoop() else if activeMoverConnection then activeMoverConnection:Disconnect() end end
end)

wanderBtn.MouseButton1Click:Connect(function()
	loopToken = loopToken + 1
	activeMode = (activeMode == "RandomWander") and "Off" or "RandomWander"
	wanderBtn.Text = activeMode == "RandomWander" and "Random Wander: ON" or "Random Wander: OFF"
	wanderBtn.BackgroundColor3 = activeMode == "RandomWander" and Color3.fromRGB(0, 170, 0) or Color3.fromRGB(40, 40, 40)
	coinBtn.Text = "Coin Hunt: OFF"
	coinBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	coinQueue = {}
	if activeMode == "RandomWander" then executeMovementLoop() else if activeMoverConnection then activeMoverConnection:Disconnect() end end
end)

-- Metrics & HUD Loop
task.spawn(function()
	while true do
		updatePlayerRole()
		totalCoinsInGame = countTotalGameCoins()
		task.wait(1.5)
		local p = player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or Vector3.new(0,0,0)
		logBox.Text = string.format(
			"=== METRICS (v2.2) ===\nRole: %s\nMode: %s | TP Coins: %s\nInstant Kill: %s | Prompts: %s\nStatus: %s\nCoins in Game: %d | Collected: %d/%d\nActive Queue: %d\nPlayer Pos: %.1f, %.1f, %.1f",
			currentPlayerRole, activeMode, (teleportCoinsEnabled and "ON" or "OFF"), (instantKillEnabled and "ON" or "OFF"), (promptAutomationEnabled and "ON" or "OFF"), statusMessage, totalCoinsInGame, collectedCount, MAX_CAPACITY, #coinQueue, p.X, p.Y, p.Z
		)
	end
end)
