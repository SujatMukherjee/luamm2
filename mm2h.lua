-- Delta Ultra-Reliable Collector (Continuous Coin Hunt + Robust Gun Aiming & Auto-Kill + God Mode + Role Adaptation + Fixed UI + Seeded Diversification)
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- Unique Seed Generator per client instance to ensure different devices take unique paths
local rng = Random.new(tick() + player.UserId + math.random(1, 100000))

local visualFolder = Workspace:FindFirstChild("DeltaNavVisuals")
if not visualFolder then
	visualFolder = Instance.new("Folder")
	visualFolder.Name = "DeltaNavVisuals"
	visualFolder.Parent = Workspace
else
	visualFolder:ClearAllChildren()
end

local espFolder = Workspace:FindFirstChild("DeltaESPVisuals")
if not espFolder then
	espFolder = Instance.new("Folder")
	espFolder.Name = "DeltaESPVisuals"
	espFolder.Parent = Workspace
else
	espFolder:ClearAllChildren()
end

local activeMoverConnection = nil
local activeMode = "Off" -- "Off", "CoinHunt", "RandomWander"
local targetPosition = nil
local statusMessage = "Idle"
local targetCoinName = "None"
local activeCoins = {}
local coinQueue = {}
local failedCoinBlacklist = {}

local loopToken = 0
local currentWaypoints = {}
local waypointIndex = 1

-- RUNTIME CONFIGURABLE THRESHOLDS & METRICS
local SAFE_SPEED = 24
local STUCK_THRESHOLD = 0.7
local ESP_ENABLED = true
local MAX_CAPACITY = 40
local TOGGLE_DELAY = 15
local collectedCount = 0
local totalCoinsInGame = 0
local autoRotateEnabled = false
local autoKillEnabled = false
local godModeEnabled = false
local currentPlayerRole = "Default"

-- Dynamic Role Detection Function
local function updatePlayerRole()
	local detectedRole = "Default"
	
	if player.Team then
		detectedRole = player.Team.Name
	end
	
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
	
	if string.find(roleLower, "speed") or string.find(roleLower, "runner") or string.find(roleLower, "scout") then
		SAFE_SPEED = 32
		MAX_CAPACITY = 50
	elseif string.find(roleLower, "tank") or string.find(roleLower, "heavy") or string.find(roleLower, "brute") then
		SAFE_SPEED = 18
		MAX_CAPACITY = 80
	elseif string.find(roleLower, "guard") or string.find(roleLower, "police") or string.find(roleLower, "defender") then
		SAFE_SPEED = 22
		MAX_CAPACITY = 30
	else
		SAFE_SPEED = 24
		MAX_CAPACITY = 40
	end
	
	return currentPlayerRole
end

-- UI Setup with Container Frame
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeltaNavUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 370, 0, 520)
mainFrame.Position = UDim2.new(0, 20, 0, 20)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
mainFrame.BackgroundTransparency = 0.15
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

-- Top Title Bar
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
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
titleLabel.Text = "Delta Ultra Collector"
titleLabel.Parent = topBar

-- Minimize Button (-)
local minBtn = Instance.new("TextButton")
minBtn.Name = "MinimizeButton"
minBtn.Size = UDim2.new(0, 28, 0, 28)
minBtn.Position = UDim2.new(1, -64, 0, 3)
minBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minBtn.TextSize = 14
minBtn.Font = Enum.Font.SourceSansBold
minBtn.Text = "-"
minBtn.Parent = topBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

-- Close Button (X)
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseButton"
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -32, 0, 3)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize = 12
closeBtn.Font = Enum.Font.SourceSansBold
closeBtn.Text = "X"
closeBtn.Parent = topBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- Dedicated Content Container Frame
local contentContainer = Instance.new("Frame")
contentContainer.Name = "ContentContainer"
contentContainer.Size = UDim2.new(1, 0, 1, -35)
contentContainer.Position = UDim2.new(0, 0, 0, 35)
contentContainer.BackgroundTransparency = 1
contentContainer.Parent = mainFrame

local coinBtn = Instance.new("TextButton")
coinBtn.Name = "CoinHuntButton"
coinBtn.Size = UDim2.new(0, 330, 0, 26)
coinBtn.Position = UDim2.new(0, 20, 0, 10)
coinBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
coinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
coinBtn.TextSize = 12
coinBtn.Font = Enum.Font.SourceSansBold
coinBtn.Text = "Coin Hunt: OFF"
coinBtn.Parent = contentContainer
Instance.new("UICorner", coinBtn).CornerRadius = UDim.new(0, 6)

local wanderBtn = Instance.new("TextButton")
wanderBtn.Name = "RandomWanderButton"
wanderBtn.Size = UDim2.new(0, 330, 0, 26)
wanderBtn.Position = UDim2.new(0, 20, 0, 40)
wanderBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
wanderBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
wanderBtn.TextSize = 12
wanderBtn.Font = Enum.Font.SourceSansBold
wanderBtn.Text = "Random Wander: OFF"
wanderBtn.Parent = contentContainer
Instance.new("UICorner", wanderBtn).CornerRadius = UDim.new(0, 6)

local autoKillBtn = Instance.new("TextButton")
autoKillBtn.Name = "AutoKillButton"
autoKillBtn.Size = UDim2.new(0, 330, 0, 26)
autoKillBtn.Position = UDim2.new(0, 20, 0, 70)
autoKillBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
autoKillBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoKillBtn.TextSize = 12
autoKillBtn.Font = Enum.Font.SourceSansBold
autoKillBtn.Text = "Auto-Kill / Aim: OFF"
autoKillBtn.Parent = contentContainer
Instance.new("UICorner", autoKillBtn).CornerRadius = UDim.new(0, 6)

local godModeBtn = Instance.new("TextButton")
godModeBtn.Name = "GodModeButton"
godModeBtn.Size = UDim2.new(0, 330, 0, 26)
godModeBtn.Position = UDim2.new(0, 20, 0, 100)
godModeBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
godModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
godModeBtn.TextSize = 12
godModeBtn.Font = Enum.Font.SourceSansBold
godModeBtn.Text = "God Mode: OFF"
godModeBtn.Parent = contentContainer
Instance.new("UICorner", godModeBtn).CornerRadius = UDim.new(0, 6)

local autoToggleBtn = Instance.new("TextButton")
autoToggleBtn.Name = "AutoToggleButton"
autoToggleBtn.Size = UDim2.new(0, 330, 0, 26)
autoToggleBtn.Position = UDim2.new(0, 20, 0, 130)
autoToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
autoToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoToggleBtn.TextSize = 12
autoToggleBtn.Font = Enum.Font.SourceSansBold
autoToggleBtn.Text = "Auto-Toggle: OFF"
autoToggleBtn.Parent = contentContainer
Instance.new("UICorner", autoToggleBtn).CornerRadius = UDim.new(0, 6)

local espBtn = Instance.new("TextButton")
espBtn.Name = "ESPButton"
espBtn.Size = UDim2.new(0, 330, 0, 26)
espBtn.Position = UDim2.new(0, 20, 0, 160)
espBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
espBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
espBtn.TextSize = 12
espBtn.Font = Enum.Font.SourceSansBold
espBtn.Text = "ESP (Player/Death): ON"
espBtn.Parent = contentContainer
Instance.new("UICorner", espBtn).CornerRadius = UDim.new(0, 6)

-- Threshold Manager UI Inputs
local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.new(0, 330, 0, 22)
speedBox.Position = UDim2.new(0, 20, 0, 192)
speedBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
speedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBox.TextSize = 11
speedBox.Font = Enum.Font.SourceSansBold
speedBox.Text = "Speed Limit: 24"
speedBox.ClearTextOnFocus = false
speedBox.Parent = contentContainer
Instance.new("UICorner", speedBox).CornerRadius = UDim.new(0, 6)

local stuckBox = Instance.new("TextBox")
stuckBox.Size = UDim2.new(0, 330, 0, 22)
stuckBox.Position = UDim2.new(0, 20, 0, 218)
stuckBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
stuckBox.TextColor3 = Color3.fromRGB(255, 255, 255)
stuckBox.TextSize = 11
stuckBox.Font = Enum.Font.SourceSansBold
stuckBox.Text = "Stuck Time (s): 0.7"
stuckBox.ClearTextOnFocus = false
stuckBox.Parent = contentContainer
Instance.new("UICorner", stuckBox).CornerRadius = UDim.new(0, 6)

local capBox = Instance.new("TextBox")
capBox.Size = UDim2.new(0, 330, 0, 22)
capBox.Position = UDim2.new(0, 20, 0, 244)
capBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
capBox.TextColor3 = Color3.fromRGB(255, 255, 255)
capBox.TextSize = 11
capBox.Font = Enum.Font.SourceSansBold
capBox.Text = "Max Inventory: 40"
capBox.ClearTextOnFocus = false
capBox.Parent = contentContainer
Instance.new("UICorner", capBox).CornerRadius = UDim.new(0, 6)

local toggleDelayBox = Instance.new("TextBox")
toggleDelayBox.Size = UDim2.new(0, 330, 0, 22)
toggleDelayBox.Position = UDim2.new(0, 20, 0, 270)
toggleDelayBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
toggleDelayBox.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleDelayBox.TextSize = 11
toggleDelayBox.Font = Enum.Font.SourceSansBold
toggleDelayBox.Text = "Toggle Delay (s): 15"
toggleDelayBox.ClearTextOnFocus = false
toggleDelayBox.Parent = contentContainer
Instance.new("UICorner", toggleDelayBox).CornerRadius = UDim.new(0, 6)

local logBox = Instance.new("TextLabel")
logBox.Name = "CoordinateLogBox"
logBox.Size = UDim2.new(0, 330, 0, 185)
logBox.Position = UDim2.new(0, 20, 0, 298)
logBox.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
logBox.BackgroundTransparency = 0.2
logBox.TextColor3 = Color3.fromRGB(0, 255, 128)
logBox.TextSize = 11
logBox.Font = Enum.Font.Code
logBox.TextXAlignment = Enum.TextXAlignment.Left
logBox.TextYAlignment = Enum.TextYAlignment.Top
logBox.TextWrapped = true
logBox.Text = "=== METRICS ===\nRole: Default\nMode: Off | Auto-Kill/Aim: OFF | God Mode: OFF\nStatus: Idle\nCoins in Game: 0 | Session: 0\nInventory: 0 / 40\nPlayer: X:0 Y:0 Z:0"
logBox.Parent = contentContainer
Instance.new("UICorner", logBox).CornerRadius = UDim.new(0, 6)

-- Minimize & Close Logic
local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	if isMinimized then
		minBtn.Text = "+"
		mainFrame.Size = UDim2.new(0, 370, 0, 35)
		contentContainer.Visible = false
	else
		minBtn.Text = "-"
		mainFrame.Size = UDim2.new(0, 370, 0, 520)
		contentContainer.Visible = true
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	activeMode = "Off"
	autoKillEnabled = false
	godModeEnabled = false
	if activeMoverConnection then activeMoverConnection:Disconnect() end
	visualFolder:ClearAllChildren()
	espFolder:ClearAllChildren()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then 
		humanoid.WalkSpeed = 16 
		pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true) end)
	end
	screenGui:Destroy()
end)

speedBox.FocusLost:Connect(function()
	local num = tonumber(speedBox.Text:match("%d+"))
	if num then SAFE_SPEED = math.clamp(num, 5, 100) end
	speedBox.Text = "Speed Limit: " .. SAFE_SPEED
end)

stuckBox.FocusLost:Connect(function()
	local num = tonumber(stuckBox.Text:match("%d+%.?%d*"))
	if num then STUCK_THRESHOLD = math.clamp(num, 0.2, 5.0) end
	stuckBox.Text = "Stuck Time (s): " .. STUCK_THRESHOLD
end)

capBox.FocusLost:Connect(function()
	local num = tonumber(capBox.Text:match("%d+"))
	if num then MAX_CAPACITY = math.clamp(num, 1, 500) end
	capBox.Text = "Max Inventory: " .. MAX_CAPACITY
end)

toggleDelayBox.FocusLost:Connect(function()
	local num = tonumber(toggleDelayBox.Text:match("%d+%.?%d*"))
	if num then TOGGLE_DELAY = math.clamp(num, 1, 300) end
	toggleDelayBox.Text = "Toggle Delay (s): " .. TOGGLE_DELAY
end)

espBtn.MouseButton1Click:Connect(function()
	ESP_ENABLED = not ESP_ENABLED
	if ESP_ENABLED then
		espBtn.Text = "ESP (Player/Death): ON"
		espBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
	else
		espBtn.Text = "ESP (Player/Death): OFF"
		espBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		espFolder:ClearAllChildren()
	end
end)

autoKillBtn.MouseButton1Click:Connect(function()
	autoKillEnabled = not autoKillEnabled
	if autoKillEnabled then
		autoKillBtn.Text = "Auto-Kill / Aim: ON"
		autoKillBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	else
		autoKillBtn.Text = "Auto-Kill / Aim: OFF"
		autoKillBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	end
end)

godModeBtn.MouseButton1Click:Connect(function()
	godModeEnabled = not godModeEnabled
	if godModeEnabled then
		godModeBtn.Text = "God Mode: ON"
		godModeBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
	else
		godModeBtn.Text = "God Mode: OFF"
		godModeBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			pcall(function()
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
			end)
		end
	end
end)

autoToggleBtn.MouseButton1Click:Connect(function()
	autoRotateEnabled = not autoRotateEnabled
	if autoRotateEnabled then
		autoToggleBtn.Text = "Auto-Toggle: ON"
		autoToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
	else
		autoToggleBtn.Text = "Auto-Toggle: OFF"
		autoToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	end
end)

-- Standalone God Mode Background Loop (Runs concurrently with any mode)
task.spawn(function()
	while true do
		task.wait(0.1)
		if godModeEnabled then
			local char = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				pcall(function()
					humanoid.Health = humanoid.MaxHealth
					humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
				end)
			end
		end
	end
end)

-- Standalone Robust Gun Aiming & Auto-Attack Background Loop
task.spawn(function()
	while true do
		task.wait(0.1) -- Fast polling to lock aim and fire rapidly
		if autoKillEnabled then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			
			if hrp and humanoid and humanoid.Health > 0 then
				local target = nil
				local minDst = 120 -- Expanded range suitable for guns/ranged weapons
				
				-- Scan for hostile players within range
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
						local pHum = p.Character:FindFirstChildOfClass("Humanoid")
						if pHum and pHum.Health > 0 then
							local dst = (hrp.Position - p.Character.HumanoidRootPart.Position).Magnitude
							if dst < minDst then
								minDst = dst
								target = p.Character
							end
						end
					end
				end
				
				-- Scan for hostile NPCs / mobs / zombies within range
				for _, obj in ipairs(Workspace:GetDescendants()) do
					if obj:IsA("Model") and obj ~= char and obj:FindFirstChild("Humanoid") and obj:FindFirstChild("HumanoidRootPart") then
						local hum = obj.Humanoid
						if hum.Health > 0 and not Players:GetPlayerFromCharacter(obj) then
							local nameLower = string.lower(obj.Name)
							if string.find(nameLower, "zombie") or string.find(nameLower, "mob") or string.find(nameLower, "enemy") or string.find(nameLower, "boss") or string.find(nameLower, "dummy") then
								local dst = (hrp.Position - obj.HumanoidRootPart.Position).Magnitude
								if dst < minDst then
									minDst = dst
									target = obj
								end
							end
						end
					end
				end
				
				if target and target:FindFirstChild("HumanoidRootPart") then
					local targetHrp = target.HumanoidRootPart
					
					-- ROBUST AIMING: Force character to face the target instantly (locking Y axis rotation to prevent tilting)
					local targetPos = targetHrp.Position
					local lookAtPos = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
					hrp.CFrame = CFrame.new(hrp.Position, lookAtPos)
					
					-- Ensure tool (gun) is equipped
					local tool = char:FindFirstChildOfClass("Tool")
					if not tool then
						local backpack = player:FindFirstChildOfClass("Backpack")
						if backpack then
							local foundTool = backpack:FindFirstChildOfClass("Tool")
							if foundTool then
								humanoid:EquipTool(foundTool)
								tool = foundTool
							end
						end
					end
					
					-- Fire the weapon/gun robustly
					if tool then
						pcall(function()
							tool:Activate()
						end)
					end
				end
			end
		end
	end
end)

local function clearVisuals()
	visualFolder:ClearAllChildren()
end

local function drawWaypoints(waypoints, targetPos)
	clearVisuals()
	if targetPos then
		local tPart = Instance.new("Part")
		tPart.Size = Vector3.new(0.9, 0.9, 0.9)
		tPart.Shape = Enum.PartType.Ball
		tPart.Anchored = true
		tPart.CanCollide = false
		tPart.Position = targetPos + Vector3.new(0, 0.5, 0)
		tPart.BrickColor = BrickColor.new("Bright yellow")
		tPart.Material = Enum.Material.Neon
		tPart.Parent = visualFolder
	end

	if waypoints then
		for _, wp in ipairs(waypoints) do
			local part = Instance.new("Part")
			part.Size = Vector3.new(0.4, 0.4, 0.4)
			part.Shape = Enum.PartType.Ball
			part.Anchored = true
			part.CanCollide = false
			part.Position = wp.Position + Vector3.new(0, 0.3, 0)
			part.BrickColor = BrickColor.new("Cyan")
			part.Material = Enum.Material.Neon
			part.Parent = visualFolder
		end
	end
end

local function getNearestThreatPos(rootPos)
	local hazardKeywords = {"kill", "lava", "hazard", "death", "acid", "spike", "danger", "fire", "trap"}
	local nearestThreat = nil
	local minDst = 18

	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			local pPos = p.Character.HumanoidRootPart.Position
			local dst = (rootPos - pPos).Magnitude
			if dst < minDst then
				minDst = dst
				nearestThreat = pPos
			end
		end
	end

	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			local nameLower = string.lower(obj.Name)
			local isHazard = false
			for _, kw in ipairs(hazardKeywords) do
				if string.find(nameLower, kw, 1, true) then
					isHazard = true
					break
				end
			end
			if isHazard then
				local dst = (rootPos - obj.Position).Magnitude
				if dst < minDst then
					minDst = dst
					nearestThreat = obj.Position
				end
			end
		end
	end
	return nearestThreat
end

task.spawn(function()
	local hazardKeywords = {"kill", "lava", "hazard", "death", "acid", "spike", "danger", "fire", "trap"}
	while true do
		task.wait(1.5)
		if ESP_ENABLED then
			espFolder:ClearAllChildren()
			local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
					local pChar = p.Character
					local hl = Instance.new("Highlight")
					hl.Adornee = pChar
					hl.FillColor = Color3.fromRGB(255, 50, 50)
					hl.OutlineColor = Color3.fromRGB(255, 255, 255)
					hl.FillTransparency = 0.5
					hl.Parent = espFolder
				end
			end

			for _, obj in ipairs(Workspace:GetDescendants()) do
				if obj:IsA("BasePart") then
					local nameLower = string.lower(obj.Name)
					local isHazard = false
					for _, kw in ipairs(hazardKeywords) do
						if string.find(nameLower, kw, 1, true) then
							isHazard = true
							break
						end
					end

					if isHazard and rootPart and (rootPart.Position - obj.Position).Magnitude < 300 then
						local hl = Instance.new("Highlight")
						hl.Adornee = obj
						hl.FillColor = Color3.fromRGB(255, 140, 0)
						hl.OutlineColor = Color3.fromRGB(255, 0, 0)
						hl.FillTransparency = 0.4
						hl.Parent = espFolder
					end
				end
			end
		end
	end
end)

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

local function countTotalGameCoins()
	local count = 0
	local keywords = {"coin", "ring", "cash", "token", "gold", "gem", "collect", "star", "point", "money", "crystal"}
	local char = player.Character

	for _, obj in ipairs(Workspace:GetDescendants()) do
		if char and (obj == char or obj:IsDescendantOf(char)) then
			continue
		end

		local nameLower = string.lower(obj.Name)
		local matched = false
		for _, kw in ipairs(keywords) do
			if string.find(nameLower, kw, 1, true) then
				matched = true
				break
			end
		end

		if matched then
			if extractPosition(obj) then
				count = count + 1
			end
		end
	end
	return count
end

local function scanAllCoins(rootPos)
	local coins = {}
	local keywords = {"coin", "ring", "cash", "token", "gold", "gem", "collect", "star", "point", "money", "crystal"}
	local hazardKeywords = {"kill", "lava", "hazard", "death", "acid", "spike", "danger", "fire", "trap"}
	local char = player.Character

	local currentTime = tick()
	for id, timeAdded in pairs(failedCoinBlacklist) do
		if currentTime - timeAdded > 30 then
			failedCoinBlacklist[id] = nil
		end
	end

	local hazardPositions = {}
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			local nameLower = string.lower(obj.Name)
			for _, kw in ipairs(hazardKeywords) do
				if string.find(nameLower, kw, 1, true) then
					table.insert(hazardPositions, obj.Position)
					break
				end
			end
		end
	end

	for _, obj in ipairs(Workspace:GetDescendants()) do
		if char and (obj == char or obj:IsDescendantOf(char)) then
			continue
		end

		if failedCoinBlacklist[obj] then
			continue
		end

		local nameLower = string.lower(obj.Name)
		local matched = false
		for _, kw in ipairs(keywords) do
			if string.find(nameLower, kw, 1, true) then
				matched = true
				break
			end
		end

		if matched then
			local pos = extractPosition(obj)
			if pos and (rootPos - pos).Magnitude < 350 then
				local safeFromHazard = true
				for _, hPos in ipairs(hazardPositions) do
					if (pos - hPos).Magnitude < 10 then
						safeFromHazard = false
						break
					end
				end

				if safeFromHazard then
					local exists = false
					for _, c in ipairs(coins) do
						if (c.pos - pos).Magnitude < 1.5 then
							exists = true
							break
						end
					end
					if not exists then
						table.insert(coins, {pos = pos, name = obj.Name, instance = obj})
					end
				end
			end
		end
	end

	return coins
end

local function buildCoinRoute(startPos, rawCoins)
	local route = {}
	local pool = {}
	for _, c in ipairs(rawCoins) do
		table.insert(pool, c)
	end
	
	-- Shuffle pool slightly using client's seeded rng to diversify routes across different instances
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	
	local currentPos = startPos
	while #pool > 0 do
		local bestIdx = 1
		local bestScore = math.huge
		for i, c in ipairs(pool) do
			local dst = (currentPos - c.pos).Magnitude
			-- Apply a unique seed-based weight so multiple devices prioritize coins differently
			local score = dst + (rng:NextNumber() * 6)
			if score < bestScore then
				bestScore = score
				bestIdx = i
			end
		end
		local chosen = table.remove(pool, bestIdx)
		table.insert(route, chosen)
		currentPos = chosen.pos
	end
	return route
end

local function computePathTo(startPos, endPos)
	local char = player.Character
	local agentRadius = 2
	local agentHeight = 5
	if char and char:FindFirstChild("HumanoidRootPart") then
		local hrp = char.HumanoidRootPart
		agentRadius = math.clamp(hrp.Size.X * 0.75, 1, 3)
		agentHeight = math.clamp(hrp.Size.Y * 1.1, 3, 7)
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = agentRadius,
		AgentHeight = agentHeight,
		AgentCanJump = true,
		WaypointSpacing = 3
	})
	
	local success = pcall(function()
		path:ComputeAsync(startPos, endPos)
	end)
	
	if success and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		if waypoints and #waypoints > 0 then
			return waypoints
		end
	end
	
	return nil
end

local executeMovementLoop

local function startNavigation()
	if activeMode == "Off" then return end
	
	if collectedCount >= MAX_CAPACITY then
		collectedCount = 0
	end
	
	local char = player.Character
	if not char or not char.Parent then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local rootPart = char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return end

	if activeMode == "CoinHunt" then
		if #coinQueue == 0 then
			activeCoins = scanAllCoins(rootPart.Position)
			coinQueue = buildCoinRoute(rootPart.Position, activeCoins)
		end

		local validPathFound = false
		local currentCoinInstance = nil

		while #coinQueue > 0 and not validPathFound do
			local nextCoin = table.remove(coinQueue, 1)
			targetPosition = nextCoin.pos
			targetCoinName = nextCoin.name
			currentCoinInstance = nextCoin.instance

			currentWaypoints = computePathTo(rootPart.Position, targetPosition)
			if currentWaypoints and #currentWaypoints > 0 then
				validPathFound = true
				statusMessage = "Hunting (" .. #coinQueue .. " left): " .. targetCoinName
			else
				if currentCoinInstance then
					failedCoinBlacklist[currentCoinInstance] = tick()
				end
			end
		end

		if not validPathFound then
			targetCoinName = "None"
			statusMessage = "Rescanning Area..."
			task.wait(0.3)
			activeCoins = {}
			coinQueue = {}
			if activeMoverConnection then activeMoverConnection:Disconnect() end
			task.spawn(executeMovementLoop)
			return
		end
	elseif activeMode == "RandomWander" then
		targetCoinName = "N/A"
		statusMessage = "Wandering..."
		local validWanderFound = false
		local attempts = 0
		
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {char, visualFolder, espFolder}

		while not validWanderFound and attempts < 12 do
			attempts = attempts + 1
			local ang = rng:NextNumber() * math.pi * 2
			local dst = rng:NextInteger(12, 28)
			local candidatePos = rootPart.Position + Vector3.new(math.cos(ang) * dst, 0, math.sin(ang) * dst)
			
			local groundHit = Workspace:Raycast(candidatePos + Vector3.new(0, 15, 0), Vector3.new(0, -35, 0), rayParams)
			if groundHit and groundHit.Instance then
				candidatePos = groundHit.Position + Vector3.new(0, 2.5, 0)
				currentWaypoints = computePathTo(rootPart.Position, candidatePos)
				if currentWaypoints and #currentWaypoints > 0 then
					targetPosition = candidatePos
					validWanderFound = true
				end
			end
		end

		if not validWanderFound then
			statusMessage = "Wander Repath Retry..."
			task.wait(0.3)
			if activeMoverConnection then activeMoverConnection:Disconnect() end
			task.spawn(executeMovementLoop)
			return
		end
	end

	waypointIndex = 1
	drawWaypoints(currentWaypoints, targetPosition)
	local currentToken = loopToken

	if activeMoverConnection then activeMoverConnection:Disconnect() end

	local stuckTimer = 0
	local lastPosCheck = rootPart.Position
	local moveRefreshTimer = 0

	local function forceEvadeAndChangeDirection()
		statusMessage = "Blocked/Stuck - Repathing"
		humanoid.Jump = true
		local evadePos = rootPart.Position + Vector3.new(rng:NextInteger(-12, 12), 0, rng:NextInteger(-12, 12))
		humanoid:MoveTo(evadePos)
		task.wait(0.3)
		if activeMoverConnection then activeMoverConnection:Disconnect() end
		task.spawn(executeMovementLoop)
	end

	local function moveToCurrentWaypoint()
		local wp = currentWaypoints[waypointIndex]
		if wp then
			if humanoid.Sit then
				humanoid.Sit = false
				task.wait(0.1)
			end
			humanoid:MoveTo(wp.Position)
			if wp.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
		end
	end

	moveToCurrentWaypoint()

	activeMoverConnection = RunService.Heartbeat:Connect(function(dt)
		if activeMode == "Off" or loopToken ~= currentToken or not char or not char.Parent or not rootPart.Parent then
			if activeMoverConnection then activeMoverConnection:Disconnect() end
			return
		end

		humanoid.WalkSpeed = SAFE_SPEED

		if humanoid.Sit then
			humanoid.Sit = false
			humanoid.Jump = true
			moveToCurrentWaypoint()
		end

		if not godModeEnabled then
			local threatPos = getNearestThreatPos(rootPart.Position)
			if threatPos then
				statusMessage = "EVADING THREAT - Repathing!"
				humanoid.Jump = true
				local escapeDir = (rootPart.Position - threatPos).Unit
				local escapePos = rootPart.Position + (escapeDir * 20) + Vector3.new(rng:NextInteger(-8, 8), 0, rng:NextInteger(-8, 8))
				humanoid:MoveTo(escapePos)
				task.wait(0.4)
				if activeMoverConnection then activeMoverConnection:Disconnect() end
				task.spawn(executeMovementLoop)
				return
			end
		end

		local currentWp = currentWaypoints[waypointIndex]
		if not currentWp then
			activeMoverConnection:Disconnect()
			clearVisuals()
			if activeMode == "CoinHunt" then
				collectedCount = collectedCount + 1
			end
			task.spawn(executeMovementLoop)
			return
		end

		local targetWpPos = currentWp.Position

		moveRefreshTimer = moveRefreshTimer + dt
		if moveRefreshTimer > 1.2 then
			moveRefreshTimer = 0
			moveToCurrentWaypoint()
		end

		if (rootPart.Position - lastPosCheck).Magnitude < 0.25 then
			stuckTimer = stuckTimer + dt
			if stuckTimer > STUCK_THRESHOLD then
				forceEvadeAndChangeDirection()
				return
			end
		else
			stuckTimer = 0
			lastPosCheck = rootPart.Position
		end

		local distance2D = Vector3.new(rootPart.Position.X - targetWpPos.X, 0, rootPart.Position.Z - targetWpPos.Z).Magnitude
		if distance2D < 3.2 or (rootPart.Position - targetWpPos).Magnitude < 3.8 then
			waypointIndex = waypointIndex + 1
			moveRefreshTimer = 0
			if waypointIndex > #currentWaypoints then
				activeMoverConnection:Disconnect()
				clearVisuals()
				if activeMode == "CoinHunt" then
					collectedCount = collectedCount + 1
				end
				task.delay(0.01, function()
					if activeMode ~= "Off" and loopToken == currentToken then executeMovementLoop() end
				end)
				return
			else
				moveToCurrentWaypoint()
			end
		end
	end)
end

executeMovementLoop = function()
	task.spawn(startNavigation)
end

task.spawn(function()
	local timeInMode = 0
	while true do
		task.wait(1)
		if autoRotateEnabled and activeMode ~= "Off" then
			timeInMode = timeInMode + 1
			if timeInMode >= TOGGLE_DELAY then
				timeInMode = 0
				loopToken = loopToken + 1
				if activeMode == "CoinHunt" then
					activeMode = "RandomWander"
					wanderBtn.Text = "Random Wander: ON"
					wanderBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
					coinBtn.Text = "Coin Hunt: OFF"
					coinBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
					coinQueue = {}
					statusMessage = "Auto-switched to Wander"
				else
					activeMode = "CoinHunt"
					coinBtn.Text = "Coin Hunt: ON"
					coinBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
					wanderBtn.Text = "Random Wander: OFF"
					wanderBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
					coinQueue = {}
					statusMessage = "Auto-switched to Hunt"
				end
				if activeMoverConnection then activeMoverConnection:Disconnect() end
				executeMovementLoop()
			end
		else
			timeInMode = 0
		end
	end
end)

coinBtn.MouseButton1Click:Connect(function()
	loopToken = loopToken + 1
	if activeMode == "CoinHunt" then
		activeMode = "Off"
		coinBtn.Text = "Coin Hunt: OFF"
		coinBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	else
		collectedCount = 0
		activeMode = "CoinHunt"
		coinBtn.Text = "Coin Hunt: ON"
		coinBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
		
		wanderBtn.Text = "Random Wander: OFF"
		wanderBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		
		coinQueue = {}
		statusMessage = "Starting Coin Hunt..."
		if activeMoverConnection then activeMoverConnection:Disconnect() end
		executeMovementLoop()
	end
	
	if activeMode == "Off" then
		statusMessage = "Turned OFF"
		clearVisuals()
		targetPosition = nil
		activeCoins = {}
		coinQueue = {}
		if activeMoverConnection then activeMoverConnection:Disconnect() end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.WalkSpeed = 16 end
	end
end)

wanderBtn.MouseButton1Click:Connect(function()
	loopToken = loopToken + 1
	if activeMode == "RandomWander" then
		activeMode = "Off"
		wanderBtn.Text = "Random Wander: OFF"
		wanderBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	else
		activeMode = "RandomWander"
		wanderBtn.Text = "Random Wander: ON"
		wanderBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
		
		coinBtn.Text = "Coin Hunt: OFF"
		coinBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		
		coinQueue = {}
		statusMessage = "Starting Random Wander..."
		if activeMoverConnection then activeMoverConnection:Disconnect() end
		executeMovementLoop()
	end
	
	if activeMode == "Off" then
		statusMessage = "Turned OFF"
		clearVisuals()
		targetPosition = nil
		activeCoins = {}
		coinQueue = {}
		if activeMoverConnection then activeMoverConnection:Disconnect() end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.WalkSpeed = 16 end
	end
end)

task.spawn(function()
	while true do
		updatePlayerRole()
		totalCoinsInGame = countTotalGameCoins()
		task.wait(2)
		local char = player.Character
		local playerPosStr = "X: 0.0, Y: 0.0, Z: 0.0"
		
		if char and char:FindFirstChild("HumanoidRootPart") then
			local p = char.HumanoidRootPart.Position
			playerPosStr = string.format("X: %.1f, Y: %.1f, Z: %.1f", p.X, p.Y, p.Z)
		end

		logBox.Text = string.format(
			"=== METRICS ===\nRole: %s\nMode: %s | Auto-Kill/Aim: %s | God Mode: %s\nStatus: %s\nCoins in Game: %d | Session: %d\nInventory: %d / %d\nFound: %d | Queued: %d\nTarget: %s\nPlayer: %s",
			currentPlayerRole, activeMode, (autoKillEnabled and "ON" or "OFF"), (godModeEnabled and "ON" or "OFF"), statusMessage, totalCoinsInGame, collectedCount, collectedCount, MAX_CAPACITY, #activeCoins, #coinQueue, targetCoinName, playerPosStr
		)
	end
end)
