-- Delta Ultra-Reliable Collector (Continuous Coin Hunt + Teleport Coins + Role Teleports + Instant Kill + God Mode + Anti-Exploit Shield)
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer

-- Anti-AFK Kick Prevention (Handles Roblox's 20-minute idle timeout)
player.Idled:Connect(function()
	VirtualUser:CaptureController()
	VirtualUser:ClickButton2(Vector2.new())
end)

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
local consecutiveStuckCount = 0

-- RUNTIME CONFIGURABLE THRESHOLDS & METRICS
local SAFE_SPEED = 24
local STUCK_THRESHOLD = 0.7
local ESP_ENABLED = true
local MAX_CAPACITY = 40
local TOGGLE_DELAY = 15
local collectedCount = 0
local totalCoinsInGame = 0
local autoRotateEnabled = false
local instantKillEnabled = false
local godModeEnabled = false
local teleportCoinsEnabled = false
local antiExploitEnabled = true
local currentPlayerRole = "Default"

-- Role Detection for Murderer & Sheriff (MM2 / Combat Game Standard)
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
mainFrame.Size = UDim2.new(0, 370, 0, 625)
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
titleLabel.Text = "Delta Ultra Collector (Anti-Exploit Shield)"
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

local tpCoinsBtn = Instance.new("TextButton")
tpCoinsBtn.Name = "TpCoinsButton"
tpCoinsBtn.Size = UDim2.new(0, 330, 0, 26)
tpCoinsBtn.Position = UDim2.new(0, 20, 0, 70)
tpCoinsBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
tpCoinsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
tpCoinsBtn.TextSize = 12
tpCoinsBtn.Font = Enum.Font.SourceSansBold
tpCoinsBtn.Text = "Teleport Coins: OFF"
tpCoinsBtn.Parent = contentContainer
Instance.new("UICorner", tpCoinsBtn).CornerRadius = UDim.new(0, 6)

local instantKillBtn = Instance.new("TextButton")
instantKillBtn.Name = "InstantKillButton"
instantKillBtn.Size = UDim2.new(0, 330, 0, 26)
instantKillBtn.Position = UDim2.new(0, 20, 0, 100)
instantKillBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
instantKillBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
instantKillBtn.TextSize = 12
instantKillBtn.Font = Enum.Font.SourceSansBold
instantKillBtn.Text = "Instant Kill: OFF"
instantKillBtn.Parent = contentContainer
Instance.new("UICorner", instantKillBtn).CornerRadius = UDim.new(0, 6)

local tpMurdererBtn = Instance.new("TextButton")
tpMurdererBtn.Name = "TpMurdererButton"
tpMurdererBtn.Size = UDim2.new(0, 330, 0, 26)
tpMurdererBtn.Position = UDim2.new(0, 20, 0, 130)
tpMurdererBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
tpMurdererBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
tpMurdererBtn.TextSize = 12
tpMurdererBtn.Font = Enum.Font.SourceSansBold
tpMurdererBtn.Text = "Teleport to Murderer"
tpMurdererBtn.Parent = contentContainer
Instance.new("UICorner", tpMurdererBtn).CornerRadius = UDim.new(0, 6)

local tpSheriffBtn = Instance.new("TextButton")
tpSheriffBtn.Name = "TpSheriffButton"
tpSheriffBtn.Size = UDim2.new(0, 330, 0, 26)
tpSheriffBtn.Position = UDim2.new(0, 20, 0, 160)
tpSheriffBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 180)
tpSheriffBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
tpSheriffBtn.TextSize = 12
tpSheriffBtn.Font = Enum.Font.SourceSansBold
tpSheriffBtn.Text = "Teleport to Sheriff"
tpSheriffBtn.Parent = contentContainer
Instance.new("UICorner", tpSheriffBtn).CornerRadius = UDim.new(0, 6)

local godModeBtn = Instance.new("TextButton")
godModeBtn.Name = "GodModeButton"
godModeBtn.Size = UDim2.new(0, 330, 0, 26)
godModeBtn.Position = UDim2.new(0, 20, 0, 190)
godModeBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
godModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
godModeBtn.TextSize = 12
godModeBtn.Font = Enum.Font.SourceSansBold
godModeBtn.Text = "God Mode: OFF"
godModeBtn.Parent = contentContainer
Instance.new("UICorner", godModeBtn).CornerRadius = UDim.new(0, 6)

local antiExploitBtn = Instance.new("TextButton")
antiExploitBtn.Name = "AntiExploitButton"
antiExploitBtn.Size = UDim2.new(0, 330, 0, 26)
antiExploitBtn.Position = UDim2.new(0, 20, 0, 220)
antiExploitBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
antiExploitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
antiExploitBtn.TextSize = 12
antiExploitBtn.Font = Enum.Font.SourceSansBold
antiExploitBtn.Text = "Anti-Exploit Shield: ON"
antiExploitBtn.Parent = contentContainer
Instance.new("UICorner", antiExploitBtn).CornerRadius = UDim.new(0, 6)

local autoToggleBtn = Instance.new("TextButton")
autoToggleBtn.Name = "AutoToggleButton"
autoToggleBtn.Size = UDim2.new(0, 330, 0, 26)
autoToggleBtn.Position = UDim2.new(0, 20, 0, 250)
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
espBtn.Position = UDim2.new(0, 20, 0, 280)
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
speedBox.Position = UDim2.new(0, 20, 0, 312)
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
stuckBox.Position = UDim2.new(0, 20, 0, 338)
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
capBox.Position = UDim2.new(0, 20, 0, 364)
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
toggleDelayBox.Position = UDim2.new(0, 20, 0, 390)
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
logBox.Size = UDim2.new(0, 330, 0, 160)
logBox.Position = UDim2.new(0, 20, 0, 418)
logBox.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
logBox.BackgroundTransparency = 0.2
logBox.TextColor3 = Color3.fromRGB(0, 255, 128)
logBox.TextSize = 11
logBox.Font = Enum.Font.Code
logBox.TextXAlignment = Enum.TextXAlignment.Left
logBox.TextYAlignment = Enum.TextYAlignment.Top
logBox.TextWrapped = true
logBox.Text = "=== METRICS ===\nRole: Default\nMode: Off | Anti-Exploit: ON\nStatus: Idle\nCoins in Game: 0 | Session: 0\nInventory: 0 / 40\nPlayer: X:0 Y:0 Z:0"
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
		mainFrame.Size = UDim2.new(0, 370, 0, 625)
		contentContainer.Visible = true
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	activeMode = "Off"
	instantKillEnabled = false
	godModeEnabled = false
	teleportCoinsEnabled = false
	antiExploitEnabled = false
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

tpCoinsBtn.MouseButton1Click:Connect(function()
	teleportCoinsEnabled = not teleportCoinsEnabled
	if teleportCoinsEnabled then
		tpCoinsBtn.Text = "Teleport Coins: ON"
		tpCoinsBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
	else
		tpCoinsBtn.Text = "Teleport Coins: OFF"
		tpCoinsBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	end
end)

instantKillBtn.MouseButton1Click:Connect(function()
	instantKillEnabled = not instantKillEnabled
	if instantKillEnabled then
		instantKillBtn.Text = "Instant Kill: ON"
		instantKillBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	else
		instantKillBtn.Text = "Instant Kill: OFF"
		instantKillBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	end
end)

antiExploitBtn.MouseButton1Click:Connect(function()
	antiExploitEnabled = not antiExploitEnabled
	if antiExploitEnabled then
		antiExploitBtn.Text = "Anti-Exploit Shield: ON"
		antiExploitBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
	else
		antiExploitBtn.Text = "Anti-Exploit Shield: OFF"
		antiExploitBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	end
end)

tpMurdererBtn.MouseButton1Click:Connect(function()
	local murderer, _ = findMurdererAndSheriff()
	if murderer and murderer.Character and murderer.Character:FindFirstChild("HumanoidRootPart") then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = murderer.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3)
			statusMessage = "Teleported to Murderer"
		end
	else
		statusMessage = "Murderer not found yet!"
	end
end)

tpSheriffBtn.MouseButton1Click:Connect(function()
	local _, sheriff = findMurdererAndSheriff()
	if sheriff and sheriff.Character and sheriff.Character:FindFirstChild("HumanoidRootPart") then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = sheriff.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3)
			statusMessage = "Teleported to Sheriff"
		end
	else
		statusMessage = "Sheriff not found yet!"
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

-- Comprehensive Anti-Exploit Shield Loop (Anti-Fling, Anti-Void, and Round-Start Proximity Evasion)
task.spawn(function()
	local lastSafeCFrame = CFrame.new(0, 50, 0)
	while true do
		task.wait(0.1)
		if antiExploitEnabled then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			
			if hrp and humanoid then
				-- 1. Anti-Fling Velocity Limiter (Blocks physics manipulation exploiters)
				if hrp.AssemblyLinearVelocity.Magnitude > 180 and not teleportCoinsEnabled then
					hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
					hrp.CFrame = lastSafeCFrame
					statusMessage = "Blocked Fling Exploit!"
				else
					if hrp.Position.Y > -100 and math.abs(hrp.Position.Y) < 10000 then
						lastSafeCFrame = hrp.CFrame
					end
				end
				
				-- 2. Anti-Void Protection (Teleports back up if thrown off the map)
				if hrp.Position.Y < -50 then
					hrp.CFrame = lastSafeCFrame + Vector3.new(0, 15, 0)
					hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
					statusMessage = "Protected against Void Exploit!"
				end
				
				-- 3. Round-Start Proximity Exploit Guard (Instantly evades players locking onto your spawn)
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
						local pDist = (hrp.Position - p.Character.HumanoidRootPart.Position).Magnitude
						if pDist < 7 then
							hrp.CFrame = hrp.CFrame + Vector3.new(math.random(-40, 40), 20, math.random(-40, 40))
							statusMessage = "Shield Evaded Nearby Threat!"
						end
					end
				end
			end
		end
	end
end)

-- Standalone God Mode Background Loop
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
			if pos and (rootPos - pos).Magnitude < 400 then
				local safeFromHazard = true
				for _, hPos in ipairs(hazardPositions) do
					if (pos - hPos).Magnitude < 8 then
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

-- Teleport to Coins Background Loop
task.spawn(function()
	while true do
		task.wait(0.15)
		if teleportCoinsEnabled then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				if collectedCount >= MAX_CAPACITY then
					collectedCount = 0
				end
				local coins = scanAllCoins(hrp.Position)
				if #coins > 0 then
					local nearestCoin = coins[1]
					local minDst = (hrp.Position - nearestCoin.pos).Magnitude
					for _, c in ipairs(coins) do
						local dst = (hrp.Position - c.pos).Magnitude
						if dst < minDst then
							minDst = dst
							nearestCoin = c
						end
					end
					if nearestCoin then
						statusMessage = "Teleporting to: " .. nearestCoin.name
						hrp.CFrame = CFrame.new(nearestCoin.pos + Vector3.new(0, 0.5, 0))
						collectedCount = collectedCount + 1
						task.wait(0.08)
					end
				else
					statusMessage = "Scanning Coins for TP..."
				end
			end
		end
	end
end)

-- Instant Kill & Target Teleport Background Loop
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
								if dst < minDst then
									minDst = dst
									targetChar = p.Character
								end
							end
						end
					end
				end
				
				if targetChar and targetChar:FindFirstChild("HumanoidRootPart") then
					local tHrp = targetChar.HumanoidRootPart
					hrp.CFrame = tHrp.CFrame * CFrame.new(0, 0, 2)
					
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

local function buildCoinRoute(startPos, rawCoins)
	local route = {}
	local pool = {}
	for _, c in ipairs(rawCoins) do
		table.insert(pool, c)
	end
	
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
		consecutiveStuckCount = consecutiveStuckCount + 1
		statusMessage = "Blocked/Stuck (" .. consecutiveStuckCount .. ") - Repathing"
		humanoid.Jump = true
		
		if consecutiveStuckCount >= 3 then
			consecutiveStuckCount = 0
			coinQueue = {}
			activeCoins = {}
			targetPosition = rootPart.Position + Vector3.new(rng:NextInteger(-25, 25), 0, rng:NextInteger(-25, 25))
		end

		local evadePos = rootPart.Position + Vector3.new(rng:NextInteger(-15, 15), 0, rng:NextInteger(-15, 15))
		humanoid:MoveTo(evadePos)
		task.wait(0.4)
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
			consecutiveStuckCount = 0
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

-- Periodic Coin Hunter Refresh Task (Every 15 seconds)
task.spawn(function()
	while true do
		task.wait(15)
		if activeMode == "CoinHunt" then
			loopToken = loopToken + 1
			coinQueue = {}
			activeCoins = {}
			statusMessage = "Refreshing Coin Hunt..."
			if activeMoverConnection then activeMoverConnection:Disconnect() end
			executeMovementLoop()
		end
	end
end)

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

-- Automatically start Coin Hunter after map and character load
task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	
	local char = player.Character or player.CharacterAdded:Wait()
	task.wait(3)
	
	if activeMode == "Off" then
		collectedCount = 0
		activeMode = "CoinHunt"
		coinBtn.Text = "Coin Hunt: ON"
		coinBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
		
		wanderBtn.Text = "Random Wander: OFF"
		wanderBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		
		coinQueue = {}
		statusMessage = "Auto-started Coin Hunt..."
		if activeMoverConnection then activeMoverConnection:Disconnect() end
		executeMovementLoop()
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
			"=== METRICS ===\nRole: %s\nMode: %s | Anti-Exploit: %s\nStatus: %s\nCoins in Game: %d | Session: %d\nInventory: %d / %d\nFound: %d | Queued: %d\nTarget: %s\nPlayer: %s",
			currentPlayerRole, activeMode, (antiExploitEnabled and "ON" or "OFF"), statusMessage, totalCoinsInGame, collectedCount, collectedCount, MAX_CAPACITY, #activeCoins, #coinQueue, targetCoinName, playerPosStr
		)
	end
end)
