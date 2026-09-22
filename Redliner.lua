local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library, ThemeManager, SaveManager

task.spawn(function() Library = loadstring(game:HttpGet(repo .. "Library.lua"))() end)
task.spawn(function() ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))() end)
task.spawn(function() SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))() end)
repeat task.wait() until Library and ThemeManager and SaveManager

local Options = Library.Options
local Toggles = Library.Toggles

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local HitboxOriginals = {}
local HitboxConnections = {}
local triggerFiring = false
local autoClickConn = nil
local SpeedHackConn = nil
local KillCount = 0
local SilentAimHook = nil
local SilentAimIndexHook = nil
local SilentAimCache = nil
local SilentAimCacheTime = 0
local pulseActive = false
local pulseTimer = 0
local PULSE_DURATION = 0.3

local aimState = {
    lock = nil,
    uuid = nil,
    phase = "idle",
}

local velHistory = {}
local VEL_HISTORY_SIZE = 5
local visCache = {}
local visCacheTime = {}

local FOVCircle = Drawing.new("Circle")
FOVCircle.Filled = false
FOVCircle.Thickness = 1.2
FOVCircle.Transparency = 0.4
FOVCircle.NumSides = 64
FOVCircle.Visible = false
FOVCircle.Color = Color3.fromRGB(255, 255, 255)

local FOVPulse = Drawing.new("Circle")
FOVPulse.Filled = false
FOVPulse.Thickness = 0.8
FOVPulse.NumSides = 64
FOVPulse.Visible = false
FOVPulse.Color = Color3.fromRGB(255, 255, 255)

local LockLabelDraw = Drawing.new("Text")
LockLabelDraw.Size = 13
LockLabelDraw.Center = true
LockLabelDraw.Outline = true
LockLabelDraw.Color = Color3.fromRGB(255, 200, 0)
LockLabelDraw.Transparency = 1
LockLabelDraw.Visible = false

local function IsTeammate(player)
    local char = player.Character
    if not char then return false end
    return char:GetAttribute("is_teammate") == true
end

local function GetHRP()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function GetHum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function ScreenCenter()
    return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
end

local function CanSee(origin, target, ignore)
    rayParams.FilterDescendantsInstances = ignore
    return workspace:Raycast(origin, target - origin, rayParams) == nil
end

local function SafeColor(v, fallback)
    return typeof(v) == "Color3" and v or (fallback or Color3.fromRGB(255, 50, 50))
end

local function HPColor(pct)
    pct = math.clamp(pct, 0, 1)
    if pct >= 0.5 then
        local t = (pct - 0.5) / 0.5
        return Color3.new(1 - t, 1, 0)
    else
        local t = pct / 0.5
        return Color3.new(1, t * 0.8, 0)
    end
end

local function FireInput(method)
    if method == "UIS" then
        pcall(function()
            UIS:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            UIS:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
    else
        pcall(mouse1click)
    end
end

local function GetPing()
    local ping = 0
    pcall(function()
        ping = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    return ping
end

local playerCache = {}
local playerCacheTime = 0
local PLAYER_TTL = 0.15

local function FlushPlayerCache()
    playerCache = {}
    playerCacheTime = 0
end

local function GetPlayerEntities()
    local now = tick()
    if now - playerCacheTime < PLAYER_TTL then return playerCache end
    playerCacheTime = now
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local char = plr.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hum and hum.Health > 0 and hrp then
                    table.insert(list, { char = char, hum = hum, hrp = hrp, player = plr })
                end
            end
        end
    end
    playerCache = list
    return list
end

local function SetHitbox(multiplier, char)
    local target = char or LP.Character
    if not target then return end
    local hrp = target:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local key = tostring(target)
    if multiplier <= 1 then
        if HitboxOriginals[key] then hrp.Size = HitboxOriginals[key] end
        return
    end
    if not HitboxOriginals[key] then HitboxOriginals[key] = hrp.Size end
    hrp.Size = HitboxOriginals[key] * multiplier
end

local function ResetHitbox(char)
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local key = tostring(char)
    if hrp and HitboxOriginals[key] then hrp.Size = HitboxOriginals[key] end
    HitboxOriginals[key] = nil
    if HitboxConnections[key] then
        HitboxConnections[key]:Disconnect()
        HitboxConnections[key] = nil
    end
end

local function ResetAllHitboxes()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then ResetHitbox(plr.Character) end
    end
    HitboxOriginals = {}
    HitboxConnections = {}
end

local function ApplyHitboxToChar(char)
    if not (Toggles.HitboxEnabled and Toggles.HitboxEnabled.Value) then return end
    local size = Options.HitboxSize and Options.HitboxSize.Value or 3
    SetHitbox(size, char)
    local key = tostring(char)
    if not HitboxConnections[key] then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            HitboxConnections[key] = hum.Died:Connect(function() ResetHitbox(char) end)
        end
    end
end

local function SampleVelocity(hrp)
    local id = tostring(hrp)
    if not velHistory[id] then velHistory[id] = {} end
    local hist = velHistory[id]
    table.insert(hist, { vel = hrp.AssemblyLinearVelocity, t = tick() })
    if #hist > VEL_HISTORY_SIZE then table.remove(hist, 1) end
end

local function GetSmoothedVelocity(hrp)
    local id = tostring(hrp)
    local hist = velHistory[id]
    if not hist or #hist == 0 then return hrp.AssemblyLinearVelocity end
    local weighted = Vector3.zero
    local totalWeight = 0
    for i, entry in ipairs(hist) do
        local w = i
        weighted = weighted + entry.vel * w
        totalWeight = totalWeight + w
    end
    return weighted / totalWeight
end

local function PredictPosition(hrp)
    SampleVelocity(hrp)
    local lookahead = Options.VelocityLookahead and Options.VelocityLookahead.Value or 50
    local strength = Options.PredictionStrength and Options.PredictionStrength.Value or 100
    local vel = GetSmoothedVelocity(hrp)
    local pingComp = 0
    if Toggles.PingCompensation and Toggles.PingCompensation.Value then
        pingComp = GetPing() / 2
    end
    local totalLead = (pingComp + lookahead) / 1000 * (strength / 100)
    local vx = Toggles.StrafePrediction and Toggles.StrafePrediction.Value and vel.X or 0
    local vy = Toggles.VerticalPrediction and Toggles.VerticalPrediction.Value and vel.Y or 0
    local vz = Toggles.StrafePrediction and Toggles.StrafePrediction.Value and vel.Z or 0
    return hrp.Position + Vector3.new(vx, vy, vz) * totalLead
end

local function CleanVelHistory(char)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then velHistory[tostring(hrp)] = nil end
end

local function GetAntiAimPart(data)
    local hrp = data.hrp
    local angSpeed = hrp.AssemblyAngularVelocity.Magnitude
    local threshold = Options.AntiAimThreshold and Options.AntiAimThreshold.Value or 8
    if Toggles.AntiAimDetection and Toggles.AntiAimDetection.Value and angSpeed >= threshold then
        return hrp
    end
    local partName = Options.AimlockTargetPart and Options.AimlockTargetPart.Value or "Head"
    return data.char:FindFirstChild(partName) or data.char:FindFirstChild("Head") or hrp
end

local function UpdateFOVColor()
    if aimState.phase == "idle" then
        FOVCircle.Color = Color3.fromRGB(255, 255, 255)
        FOVPulse.Color = Color3.fromRGB(255, 255, 255)
    elseif aimState.phase == "acquiring" then
        FOVCircle.Color = Color3.fromRGB(255, 200, 0)
        FOVPulse.Color = Color3.fromRGB(255, 200, 0)
    else
        FOVCircle.Color = Color3.fromRGB(255, 50, 50)
        FOVPulse.Color = Color3.fromRGB(255, 50, 50)
    end
end

local function GetRageTarget()
    local lpChar = LP.Character
    local lpHRP = lpChar and lpChar:FindFirstChild("HumanoidRootPart")
    if not lpHRP then return nil, nil end
    local useTeam = Toggles.AimlockTeamCheck and Toggles.AimlockTeamCheck.Value
    local useVis = Toggles.AimlockVisCheck and Toggles.AimlockVisCheck.Value
    local fov = Options.AimlockFOV and Options.AimlockFOV.Value or 120
    local useNTD = Toggles.NearestToDeath and Toggles.NearestToDeath.Value
    local useUUID = Toggles.UUIDLock and Toggles.UUIDLock.Value
    local useSticky = Toggles.StickyAim and Toggles.StickyAim.Value
    local center = ScreenCenter()
    if aimState.lock then
        local hum = aimState.lock:FindFirstChildOfClass("Humanoid")
        local hrp = aimState.lock:FindFirstChild("HumanoidRootPart")
        if not aimState.lock.Parent or not hum or hum.Health <= 0 or not hrp then
            aimState.lock = nil aimState.uuid = nil aimState.phase = "idle"
        end
    end
    if useUUID and aimState.lock then
        local hrp = aimState.lock:FindFirstChild("HumanoidRootPart")
        local hum = aimState.lock:FindFirstChildOfClass("Humanoid")
        if hrp and hum then
            local part = GetAntiAimPart({ char = aimState.lock, hrp = hrp, hum = hum })
            aimState.phase = "tracking"
            return part, { char = aimState.lock, hrp = hrp, hum = hum }
        end
    end
    if useSticky and aimState.lock then
        local hrp = aimState.lock:FindFirstChild("HumanoidRootPart")
        local hum = aimState.lock:FindFirstChildOfClass("Humanoid")
        if hrp then
            local sp, on = Camera:WorldToViewportPoint(hrp.Position)
            if on and (Vector2.new(sp.X, sp.Y) - center).Magnitude <= fov then
                local part = GetAntiAimPart({ char = aimState.lock, hrp = hrp, hum = hum })
                aimState.phase = "tracking"
                return part, { char = aimState.lock, hrp = hrp, hum = hum }
            else
                aimState.lock = nil aimState.uuid = nil aimState.phase = "idle"
            end
        end
    end
    local bestScore = math.huge
    local bestData = nil
    local bestPart = nil
    for _, data in ipairs(GetPlayerEntities()) do
        local skip = useTeam and IsTeammate(data.player)
        if not skip then
            local part = GetAntiAimPart(data)
            if part then
                local sp, on = Camera:WorldToViewportPoint(part.Position)
                if on then
                    local sd = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if sd <= fov then
                        local canHit = true
                        if useVis then
                            canHit = CanSee(Camera.CFrame.Position, part.Position, { lpChar, data.char })
                        end
                        if canHit then
                            local score = useNTD and (data.hum.Health / data.hum.MaxHealth) or sd
                            if score < bestScore then
                                bestScore = score bestData = data bestPart = part
                            end
                        end
                    end
                end
            end
        end
    end
    if bestData then
        local uuid = tostring(bestData.player.UserId)
        if uuid ~= aimState.uuid then
            aimState.lock = bestData.char aimState.uuid = uuid
            aimState.phase = "acquiring"
            pulseActive = true pulseTimer = PULSE_DURATION
        else
            aimState.phase = "tracking"
        end
    end
    return bestPart, bestData
end

local function GetSilentTarget()
    local now = tick()
    if now - SilentAimCacheTime < 0.016 then return SilentAimCache end
    SilentAimCacheTime = now
    local fov = Options.AimlockFOV and Options.AimlockFOV.Value or 120
    local center = ScreenCenter()
    local best = fov
    local closest = nil
    for _, data in ipairs(GetPlayerEntities()) do
        if not IsTeammate(data.player) then
            local part = GetAntiAimPart(data)
            if part then
                local sp, on = Camera:WorldToViewportPoint(part.Position)
                if on then
                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if d < best then best = d closest = part end
                end
            end
        end
    end
    SilentAimCache = closest
    return closest
end

local function EnableSilentAim()
    if SilentAimHook then return end
    if not hookmetamethod then
        Library:Notify({ Title = "Silent Aim", Description = "hookmetamethod unavailable on this executor.", Time = 5 })
        return
    end
    local playerMouse = LP:GetMouse()
    local oldNC
    oldNC = hookmetamethod(game, "__namecall", function(...)
        local args = { ... }
        local method = getnamecallmethod()
        if Toggles.SilentAimEnabled and Toggles.SilentAimEnabled.Value and args[1] == workspace then
            local target = GetSilentTarget()
            if target then
                if method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRay" then
                    local ray = args[2]
                    if typeof(ray) == "Ray" then
                        args[2] = Ray.new(ray.Origin, (target.Position - ray.Origin).Unit * ray.Direction.Magnitude)
                        return oldNC(table.unpack(args))
                    end
                elseif method == "FindPartOnRayWithWhitelist" then
                    local ray = args[2]
                    if typeof(ray) == "Ray" then
                        args[2] = Ray.new(ray.Origin, (target.Position - ray.Origin).Unit * ray.Direction.Magnitude)
                        return oldNC(table.unpack(args))
                    end
                elseif method == "Raycast" then
                    if typeof(args[2]) == "Vector3" and typeof(args[3]) == "Vector3" then
                        args[3] = (target.Position - args[2]).Unit * args[3].Magnitude
                        return oldNC(table.unpack(args))
                    end
                end
            end
        end
        return oldNC(...)
    end)
    SilentAimHook = oldNC
    local oldIdx
    oldIdx = hookmetamethod(game, "__index", function(t, k)
        if Toggles.SilentAimEnabled and Toggles.SilentAimEnabled.Value and t == playerMouse then
            local target = GetSilentTarget()
            if target then
                if k == "Target" then return target end
                if k == "Hit" then return CFrame.new(target.Position) end
            end
        end
        return oldIdx(t, k)
    end)
    SilentAimIndexHook = oldIdx
end

local espPool = {}
local espSlots = {}
local chamObjects = {}
local ESP_POOL_SIZE = 40
local espFrameSkip = 0

local JOINTS_R15 = {
    { "Head", "UpperTorso", "upper" }, { "UpperTorso", "LowerTorso", "upper" },
    { "UpperTorso", "LeftUpperArm", "upper" }, { "LeftUpperArm", "LeftLowerArm", "upper" },
    { "LeftLowerArm", "LeftHand", "upper" }, { "UpperTorso", "RightUpperArm", "upper" },
    { "RightUpperArm", "RightLowerArm", "upper" }, { "RightLowerArm", "RightHand", "upper" },
    { "LowerTorso", "LeftUpperLeg", "lower" }, { "LeftUpperLeg", "LeftLowerLeg", "lower" },
    { "LeftLowerLeg", "LeftFoot", "lower" }, { "LowerTorso", "RightUpperLeg", "lower" },
    { "RightUpperLeg", "RightLowerLeg", "lower" }, { "RightLowerLeg", "RightFoot", "lower" },
}

local JOINTS_R6 = {
    { "Head", "Torso", "upper" }, { "Torso", "Left Arm", "upper" }, { "Torso", "Right Arm", "upper" },
    { "Torso", "Left Leg", "lower" }, { "Torso", "Right Leg", "lower" },
}

local function GetRigType(char)
    if char:FindFirstChild("UpperTorso") then return "R15" end
    if char:FindFirstChild("Torso") then return "R6" end
    return "R15"
end

local function NewLine()
    local l = Drawing.new("Line")
    l.Visible = false l.Transparency = 1
    return l
end

local function MakeSlot()
    local sk = {}
    for i = 1, #JOINTS_R15 do sk[i] = NewLine() end
    return {
        Box = Drawing.new("Square"), BoxFill = Drawing.new("Square"), Tracer = NewLine(),
        NameText = Drawing.new("Text"), HPBarBG = Drawing.new("Square"),
        HPBar = Drawing.new("Square"), HPText = Drawing.new("Text"),
        TargetCircle = Drawing.new("Circle"), SkelLines = sk,
        CTL1 = NewLine(), CTL2 = NewLine(), CTR1 = NewLine(), CTR2 = NewLine(),
        CBL1 = NewLine(), CBL2 = NewLine(), CBR1 = NewLine(), CBR2 = NewLine(),
        ArrowLines = { NewLine(), NewLine(), NewLine() },
        inUse = false, char = nil, rigType = "R15",
    }
end

for i = 1, ESP_POOL_SIZE do espPool[i] = MakeSlot() end

local function AcquireSlot(char)
    if espSlots[char] then return espSlots[char] end
    for _, slot in ipairs(espPool) do
        if not slot.inUse then
            slot.inUse = true slot.char = char slot.rigType = GetRigType(char)
            espSlots[char] = slot return slot
        end
    end
    return nil
end

local function HideSlot(slot)
    if not slot then return end
    local function h(o) if o and o.__OBJECT_EXISTS then o.Visible = false end end
    h(slot.Box) h(slot.BoxFill) h(slot.Tracer) h(slot.NameText)
    h(slot.HPBarBG) h(slot.HPBar) h(slot.HPText) h(slot.TargetCircle)
    for _, k in ipairs({ "CTL1", "CTL2", "CTR1", "CTR2", "CBL1", "CBL2", "CBR1", "CBR2" }) do h(slot[k]) end
    for _, l in ipairs(slot.SkelLines) do if l.__OBJECT_EXISTS then l.Visible = false end end
    for _, l in ipairs(slot.ArrowLines) do if l.__OBJECT_EXISTS then l.Visible = false end end
end

local function ReleaseSlot(char)
    local slot = espSlots[char]
    if not slot then return end
    HideSlot(slot) slot.inUse = false slot.char = nil espSlots[char] = nil
    if chamObjects[char] then pcall(function() chamObjects[char]:Destroy() end) chamObjects[char] = nil end
    visCache[char] = nil visCacheTime[char] = nil CleanVelHistory(char)
end

local function ReleaseAllSlots() for char in pairs(espSlots) do ReleaseSlot(char) end end
local function CleanupAllChams()
    for char, hl in pairs(chamObjects) do
        pcall(function() hl:Destroy() end) chamObjects[char] = nil
    end
end

local function HideCorner(slot)
    for _, k in ipairs({ "CTL1", "CTL2", "CTR1", "CTR2", "CBL1", "CBL2", "CBR1", "CBR2" }) do
        if slot[k] and slot[k].__OBJECT_EXISTS then slot[k].Visible = false end
    end
end

local function DrawCorner(slot, x, y, w, h, col, thick)
    local cL = math.floor(math.min(w, h) * 0.22)
    local pts = {
        { slot.CTL1, x, y, x + cL, y }, { slot.CTL2, x, y, x, y + cL },
        { slot.CTR1, x + w, y, x + w - cL, y }, { slot.CTR2, x + w, y, x + w, y + cL },
        { slot.CBL1, x, y + h, x + cL, y + h }, { slot.CBL2, x, y + h, x, y + h - cL },
        { slot.CBR1, x + w, y + h, x + w - cL, y + h }, { slot.CBR2, x + w, y + h, x + w, y + h - cL },
    }
    for _, p in ipairs(pts) do
        if p[1].__OBJECT_EXISTS then
            p[1].Visible = true p[1].From = Vector2.new(p[2], p[3]) p[1].To = Vector2.new(p[4], p[5])
            p[1].Color = col p[1].Thickness = thick p[1].Transparency = 1
        end
    end
end

Players.PlayerRemoving:Connect(function(plr)
    local char = plr.Character
    if char then
        task.defer(function() ReleaseSlot(char) ResetHitbox(char) CleanVelHistory(char) end)
        FlushPlayerCache()
    end
end)

local function HookDeath(char, plr)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum.Died:Connect(function()
        if aimState.lock == char then aimState.lock = nil aimState.uuid = nil aimState.phase = "idle" end
        KillCount += 1
        if Toggles.KillNotif and Toggles.KillNotif.Value then
            Library:Notify({
                Title = "Target Down",
                Description = (plr and plr.Name or "?") .. " eliminated.  Kills: " .. KillCount,
                Time = 4,
            })
        end
        FlushPlayerCache()
        task.delay(0.1, function() ReleaseSlot(char) ResetHitbox(char) CleanVelHistory(char) end)
    end)
    char.AncestryChanged:Connect(function()
        if not char.Parent then
            FlushPlayerCache()
            task.defer(function() ReleaseSlot(char) ResetHitbox(char) CleanVelHistory(char) end)
        end
    end)
end

if LP.Character then HookDeath(LP.Character, LP) end
LP.CharacterAdded:Connect(function(char)
    HookDeath(char, LP)
    aimState.lock = nil aimState.uuid = nil aimState.phase = "idle"
    FlushPlayerCache()
end)
Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function(char) HookDeath(char, plr) FlushPlayerCache() end)
end)

local function ApplySpeedHack()
    if SpeedHackConn then SpeedHackConn:Disconnect() SpeedHackConn = nil end
    if not (Toggles.SpeedHackEnabled and Toggles.SpeedHackEnabled.Value) then return end
    SpeedHackConn = RunService.Heartbeat:Connect(function()
        if not (Toggles.SpeedHackEnabled and Toggles.SpeedHackEnabled.Value) then
            SpeedHackConn:Disconnect() SpeedHackConn = nil return
        end
        local hum = GetHum()
        if hum then hum.WalkSpeed = Options.SpeedHackValue and Options.SpeedHackValue.Value or 50 end
    end)
end

Library:GiveSignal(RunService.RenderStepped:Connect(function(dt)
    if Library.Toggled then
        FOVCircle.Visible = false FOVPulse.Visible = false LockLabelDraw.Visible = false return
    end
    local center = ScreenCenter()
    UpdateFOVColor()
    if Toggles.ShowFOV and Toggles.ShowFOV.Value then
        local fovR = Options.AimlockFOV and Options.AimlockFOV.Value or 120
        FOVCircle.Visible = true FOVCircle.Radius = fovR FOVCircle.Position = center
        if pulseActive then
            pulseTimer = pulseTimer - dt
            local progress = 1 - (pulseTimer / PULSE_DURATION)
            FOVPulse.Visible = true FOVPulse.Radius = fovR * (1 + progress * 0.12)
            FOVPulse.Transparency = 0.6 + progress * 0.38 FOVPulse.Position = center
            if pulseTimer <= 0 then pulseActive = false FOVPulse.Visible = false end
        else FOVPulse.Visible = false end
    else FOVCircle.Visible = false FOVPulse.Visible = false end
    if Toggles.LockIndicator and Toggles.LockIndicator.Value and aimState.lock then
        local plr = Players:GetPlayerFromCharacter(aimState.lock)
        local name = plr and plr.Name or "Unknown"
        local modeStr = Toggles.UUIDLock and Toggles.UUIDLock.Value and "UUID"
            or Toggles.StickyAim and Toggles.StickyAim.Value and "Sticky" or "Normal"
        LockLabelDraw.Text = name .. " — " .. modeStr
        LockLabelDraw.Position = Vector2.new(center.X, center.Y + (Options.AimlockFOV and Options.AimlockFOV.Value or 120) + 14)
        LockLabelDraw.Visible = true
    else LockLabelDraw.Visible = false end
    if Toggles.AimlockEnabled and Toggles.AimlockEnabled.Value then
        local part, data = GetRageTarget()
        if part and data then
            local aimPos
            if Toggles.VelocityPrediction and Toggles.VelocityPrediction.Value then
                local predicted = PredictPosition(data.hrp)
                aimPos = predicted + (part.Position - data.hrp.Position)
            else aimPos = part.Position end
            Camera.CFrame = CFrame.new(Camera.CFrame.Position, aimPos)
        end
    end
    if Toggles.AutoShootEnabled and Toggles.AutoShootEnabled.Value and not triggerFiring then
        local mt = LP:GetMouse().Target
        if mt then
            local tc = Players:GetPlayerFromCharacter(mt.Parent)
            if tc and tc ~= LP and not IsTeammate(tc) then
                triggerFiring = true
                task.delay(math.random(0, 15) / 1000, function()
                    if Toggles.AutoShootEnabled.Value then FireInput("UIS") end
                    triggerFiring = false
                end)
            end
        end
    end
    if Toggles.HitboxEnabled and Toggles.HitboxEnabled.Value then
        for _, data in ipairs(GetPlayerEntities()) do
            if not IsTeammate(data.player) then ApplyHitboxToChar(data.char) end
        end
    end
end))

Library:GiveSignal(RunService.Heartbeat:Connect(function()
    if Library.Toggled then return end
    espFrameSkip = espFrameSkip + 1
    if espFrameSkip < 2 then return end
    espFrameSkip = 0
    local espOn = Toggles.ESPEnabled and Toggles.ESPEnabled.Value
    local chamsOn = Toggles.ChamsEnabled and Toggles.ChamsEnabled.Value
    if not espOn and not chamsOn then return end
    local lpChar = LP.Character
    local lpHRP = lpChar and lpChar:FindFirstChild("HumanoidRootPart")
    local vp = Camera.ViewportSize
    local now = tick()
    local seen = {}
    for _, data in ipairs(GetPlayerEntities()) do
        local char = data.char local hum = data.hum local hrp = data.hrp local plr = data.player
        seen[char] = true
        if not (char and char.Parent and hrp and hum and hum.Health > 0) then continue end
        local maxDist = Options.ESPMaxDistance and Options.ESPMaxDistance.Value or 1000
        if lpHRP and (lpHRP.Position - hrp.Position).Magnitude > maxDist then continue end
        local isFriend = IsTeammate(plr)
        local isLocked = aimState.lock == char
        if chamsOn then
            if not chamObjects[char] then
                local hl = Instance.new("Highlight")
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop hl.Parent = char chamObjects[char] = hl
            end
            local hl = chamObjects[char]
            if isLocked then
                hl.FillColor = Color3.fromRGB(255, 200, 0) hl.FillTransparency = 0.4
                hl.OutlineColor = Color3.fromRGB(255, 200, 0) hl.OutlineTransparency = 0
            elseif isFriend then
                hl.FillColor = Color3.fromRGB(80, 160, 255) hl.FillTransparency = 0.5
                hl.OutlineColor = Color3.fromRGB(80, 160, 255) hl.OutlineTransparency = 0
            else
                local ec = SafeColor(Options.ChamsEnemyColor and Options.ChamsEnemyColor.Value)
                hl.FillColor = ec hl.FillTransparency = 0.5 hl.OutlineColor = ec hl.OutlineTransparency = 0
            end
        else
            if chamObjects[char] then pcall(function() chamObjects[char]:Destroy() end) chamObjects[char] = nil end
        end
        if not espOn then continue end
        if isFriend and Toggles.ESPTeamCheck and Toggles.ESPTeamCheck.Value then continue end
        local hrpSP, onScreen = Camera:WorldToViewportPoint(hrp.Position)
        local slot = AcquireSlot(char) if not slot then continue end
        if not onScreen then HideSlot(slot) continue end
        if Toggles.ESPVisibleOnly and Toggles.ESPVisibleOnly.Value then
            if (now - (visCacheTime[char] or 0)) >= 0.2 then
                visCache[char] = CanSee(Camera.CFrame.Position, hrp.Position, { lpChar, char })
                visCacheTime[char] = now
            end
            if not visCache[char] then HideSlot(slot) continue end
        end
        local hpPct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
        if hpPct <= 0 then HideSlot(slot) continue end
        local rigH = slot.rigType == "R6" and 5.0 or 5.8
        local botSP = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
        local topSP = Camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, rigH - 3, 0))
        local midSP = Camera:WorldToViewportPoint(hrp.Position)
        local boxH = math.abs(topSP.Y - botSP.Y) local boxW = math.max(boxH / 2.2, 20)
        local boxX = midSP.X - boxW / 2 local boxY = math.min(topSP.Y, botSP.Y)
        local col = isLocked and Color3.fromRGB(255, 200, 0)
            or isFriend and Color3.fromRGB(100, 180, 255)
            or SafeColor(Options.ESPBoxColor and Options.ESPBoxColor.Value)
        local boxStyle = Options.ESPBoxStyle and Options.ESPBoxStyle.Value or "Corner"
        if Toggles.ESPBox and Toggles.ESPBox.Value then
            if boxStyle == "Corner" then
                if slot.Box.__OBJECT_EXISTS then slot.Box.Visible = false end
                DrawCorner(slot, boxX, boxY, boxW, boxH, col, 1.2)
            else
                HideCorner(slot)
                if slot.Box.__OBJECT_EXISTS then
                    slot.Box.Visible = true slot.Box.Size = Vector2.new(boxW, boxH)
                    slot.Box.Position = Vector2.new(boxX, boxY) slot.Box.Color = col
                    slot.Box.Thickness = isLocked and 1.8 or 1.2 slot.Box.Filled = false slot.Box.Transparency = 1
                end
            end
        else if slot.Box.__OBJECT_EXISTS then slot.Box.Visible = false end HideCorner(slot) end
        if Toggles.ESPName and Toggles.ESPName.Value and slot.NameText.__OBJECT_EXISTS then
            local nameStr = plr.Name
            if Toggles.ESPDistance and Toggles.ESPDistance.Value and lpHRP then
                nameStr = nameStr .. " " .. math.floor((lpHRP.Position - hrp.Position).Magnitude) .. "m"
            end
            slot.NameText.Visible = true slot.NameText.Text = nameStr
            slot.NameText.Position = Vector2.new(midSP.X, boxY - 13)
            slot.NameText.Color = isLocked and Color3.fromRGB(255, 200, 0) or Color3.fromRGB(255, 255, 255)
            slot.NameText.Size = 12 slot.NameText.Center = true slot.NameText.Outline = true slot.NameText.Transparency = 1
        elseif slot.NameText.__OBJECT_EXISTS then slot.NameText.Visible = false end
        if Toggles.ESPHealthBar and Toggles.ESPHealthBar.Value then
            local barThick = 3 local barX = boxX - barThick - 3 local fillH = boxH * hpPct
            if slot.HPBarBG.__OBJECT_EXISTS then
                slot.HPBarBG.Visible = true slot.HPBarBG.Size = Vector2.new(barThick, boxH)
                slot.HPBarBG.Position = Vector2.new(barX, boxY) slot.HPBarBG.Color = Color3.fromRGB(15, 15, 15)
                slot.HPBarBG.Filled = true slot.HPBarBG.Transparency = 1
            end
            if slot.HPBar.__OBJECT_EXISTS and fillH > 0 then
                slot.HPBar.Visible = true slot.HPBar.Size = Vector2.new(barThick - 2, math.max(1, fillH - 2))
                slot.HPBar.Position = Vector2.new(barX + 1, boxY + boxH - fillH + 1)
                slot.HPBar.Color = HPColor(hpPct) slot.HPBar.Filled = true slot.HPBar.Transparency = 1
            end
        else
            if slot.HPBarBG.__OBJECT_EXISTS then slot.HPBarBG.Visible = false end
            if slot.HPBar.__OBJECT_EXISTS then slot.HPBar.Visible = false end
        end
        if Toggles.ESPTracer and Toggles.ESPTracer.Value and slot.Tracer.__OBJECT_EXISTS then
            slot.Tracer.Visible = true slot.Tracer.From = Vector2.new(vp.X / 2, vp.Y)
            slot.Tracer.To = Vector2.new(midSP.X, botSP.Y) slot.Tracer.Color = col
            slot.Tracer.Thickness = 0.8 slot.Tracer.Transparency = 0.7
        elseif slot.Tracer.__OBJECT_EXISTS then slot.Tracer.Visible = false end
        if Toggles.ESPTargetCircle and Toggles.ESPTargetCircle.Value and isLocked and slot.TargetCircle.__OBJECT_EXISTS then
            local head = char:FindFirstChild("Head")
            local headPos = head and head.Position or hrp.Position + Vector3.new(0, 1.5, 0)
            local hSP, hOn = Camera:WorldToViewportPoint(headPos)
            if hOn then
                slot.TargetCircle.Visible = true slot.TargetCircle.Position = Vector2.new(hSP.X, hSP.Y)
                slot.TargetCircle.Radius = Options.ESPTargetCircleRadius and Options.ESPTargetCircleRadius.Value or 14
                slot.TargetCircle.Color = Color3.fromRGB(255, 200, 0) slot.TargetCircle.Filled = false
                slot.TargetCircle.Thickness = 1.2 slot.TargetCircle.Transparency = 0.85 slot.TargetCircle.NumSides = 32
            else slot.TargetCircle.Visible = false end
        elseif slot.TargetCircle.__OBJECT_EXISTS then slot.TargetCircle.Visible = false end
    end
    for char in pairs(espSlots) do
        if not seen[char] then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not char.Parent or (hum and hum.Health <= 0) then ReleaseSlot(char) end
        end
    end
    for char in pairs(chamObjects) do
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not char.Parent or (hum and hum.Health <= 0) then
            pcall(function() chamObjects[char]:Destroy() end) chamObjects[char] = nil
        end
    end
end))

local Window = Library:CreateWindow({
    Title = "Redliner", Footer = "v1.0 — final release",
    Center = true, AutoShow = true, ToggleKeybind = Enum.KeyCode.RightControl,
})

local Tabs = {
    Combat   = Window:AddTab("Combat",   "zap"),
    Lock     = Window:AddTab("Lock",     "shield"),
    Visuals  = Window:AddTab("Visuals",  "eye"),
    Utility  = Window:AddTab("Utility",  "grid"),
    Settings = Window:AddTab("Settings", "settings"),
}

local CombatLeft  = Tabs.Combat:AddLeftGroupbox("Aimlock")
local CombatRight = Tabs.Combat:AddRightGroupbox("Combat")

CombatLeft:AddToggle("AimlockEnabled",      { Text = "Aimlock",        Default = true })
CombatLeft:AddToggle("AimlockTeamCheck",    { Text = "Team Check",     Default = true, Tooltip = "Uses is_teammate attribute." })
CombatLeft:AddToggle("AimlockVisCheck",     { Text = "Vis Check",      Default = false })
CombatLeft:AddSlider("AimlockFOV",          { Text = "FOV",            Default = 120, Min = 10, Max = 300, Rounding = 0, Suffix = "px" })
CombatLeft:AddDropdown("AimlockTargetPart", { Text = "Target Part",    Values = { "Head", "UpperTorso", "HumanoidRootPart" }, Default = 1 })
CombatLeft:AddDivider()
CombatLeft:AddToggle("ShowFOV",             { Text = "Show FOV",       Default = true })
CombatLeft:AddToggle("LockIndicator",       { Text = "Lock Indicator", Default = true })
CombatLeft:AddToggle("SilentAimEnabled",    { Text = "Silent Aim",     Default = false, Tooltip = "Requires hookmetamethod. May not work on Redliner." })
Toggles.SilentAimEnabled:OnChanged(function(s) if s then EnableSilentAim() end end)

CombatRight:AddToggle("AutoShootEnabled",   { Text = "Auto-Shoot",     Default = true })
CombatRight:AddDivider()
CombatRight:AddToggle("HitboxEnabled",      { Text = "Hitbox",         Default = true })
CombatRight:AddSlider("HitboxSize",         { Text = "Size",           Default = 3, Min = 1, Max = 8, Rounding = 1, Suffix = "x" })
CombatRight:AddButton({ Text = "Reset Hitbox", Func = function() ResetAllHitboxes() end })
CombatRight:AddDivider()
CombatRight:AddToggle("AutoClickEnabled",   { Text = "Auto Click",     Default = false })
CombatRight:AddSlider("AutoClickRate",      { Text = "Rate",           Default = 20, Min = 1, Max = 100, Rounding = 0, Suffix = "/s" })
CombatRight:AddDivider()
CombatRight:AddToggle("KillNotif",          { Text = "Kill Notif",     Default = true })
local KillLabel = CombatRight:AddLabel({ Text = "Session Kills: 0", DoesWrap = false })
CombatRight:AddButton({ Text = "Reset Kills", Func = function()
    KillCount = 0
    if KillLabel and KillLabel.SetText then KillLabel:SetText("Session Kills: 0") end
end })

local LockLeft  = Tabs.Lock:AddLeftGroupbox("Lock Behavior")
local LockRight = Tabs.Lock:AddRightGroupbox("Prediction")

LockLeft:AddToggle("StickyAim",           { Text = "Sticky Aim",          Default = false })
LockLeft:AddToggle("UUIDLock",            { Text = "UUID Lock",            Default = false })
LockLeft:AddToggle("NearestToDeath",      { Text = "Nearest to Death",     Default = true })
LockLeft:AddToggle("AntiAimDetection",    { Text = "Anti-Aim Detection",   Default = true })
LockLeft:AddSlider("AntiAimThreshold",    { Text = "AA Threshold",         Default = 8, Min = 2, Max = 20, Rounding = 1 })
LockLeft:AddDivider()
LockLeft:AddButton({ Text = "Break Lock", Func = function()
    aimState.lock = nil aimState.uuid = nil aimState.phase = "idle"
    Library:Notify({ Title = "Lock Cleared", Description = "Target released.", Time = 2 })
end })

LockRight:AddToggle("VelocityPrediction",  { Text = "Velocity Prediction",  Default = true })
LockRight:AddToggle("PingCompensation",    { Text = "Ping Compensation",    Default = true })
LockRight:AddToggle("StrafePrediction",    { Text = "Strafe Prediction",    Default = true })
LockRight:AddToggle("VerticalPrediction",  { Text = "Vertical Prediction",  Default = true })
LockRight:AddDivider()
LockRight:AddSlider("VelocityLookahead",   { Text = "Lookahead",            Default = 50, Min = 0, Max = 200, Rounding = 0, Suffix = "ms" })
LockRight:AddSlider("PredictionStrength",  { Text = "Strength",             Default = 100, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })

Toggles.UUIDLock:OnChanged(function(s) if s and Toggles.StickyAim.Value then Toggles.StickyAim:SetValue(false) end end)
Toggles.StickyAim:OnChanged(function(s) if s and Toggles.UUIDLock.Value then Toggles.UUIDLock:SetValue(false) end end)

local VisLeft  = Tabs.Visuals:AddLeftGroupbox("ESP")
local VisRight = Tabs.Visuals:AddRightGroupbox("Chams")
local ESPTabbox  = VisLeft:AddTabbox()
local BoxTab     = ESPTabbox:AddTab("Box")
local DetailsTab = ESPTabbox:AddTab("Details")
local ExtrasTab  = ESPTabbox:AddTab("Extras")

BoxTab:AddToggle("ESPEnabled",          { Text = "Enable ESP",       Default = false })
BoxTab:AddToggle("ESPBox",              { Text = "Box",              Default = true })
BoxTab:AddDropdown("ESPBoxStyle",       { Text = "Style",            Values = { "Corner", "Full" }, Default = 1 })
do local BCT = BoxTab:AddToggle("_BCT", { Text = "Box Color", Default = false })
   BCT:AddColorPicker("ESPBoxColor", { Title = "Box", Default = Color3.fromRGB(255, 50, 50) }) end
BoxTab:AddToggle("ESPTeamCheck",        { Text = "Team Check",       Default = true })
BoxTab:AddToggle("ESPVisibleOnly",      { Text = "Visible Only",     Default = false })
BoxTab:AddSlider("ESPMaxDistance",      { Text = "Max Distance",     Default = 1000, Min = 50, Max = 5000, Rounding = 0, Suffix = " studs" })

DetailsTab:AddToggle("ESPName",             { Text = "Name",             Default = true })
DetailsTab:AddToggle("ESPDistance",         { Text = "Distance",         Default = true })
DetailsTab:AddToggle("ESPHealthBar",        { Text = "Health Bar",       Default = true })
DetailsTab:AddToggle("ESPTargetCircle",     { Text = "Target Circle",    Default = true })
DetailsTab:AddSlider("ESPTargetCircleRadius", { Text = "Circle Radius",  Default = 14, Min = 6, Max = 40, Rounding = 0, Suffix = "px" })

ExtrasTab:AddToggle("ESPTracer",            { Text = "Tracer",           Default = false })

VisRight:AddToggle("ChamsEnabled",          { Text = "Enable Chams",     Default = true })
do local CECol = VisRight:AddToggle("_CECol", { Text = "Enemy Color", Default = false })
   CECol:AddColorPicker("ChamsEnemyColor", { Title = "Enemy", Default = Color3.fromRGB(255, 50, 50) }) end

local UtilLeft  = Tabs.Utility:AddLeftGroupbox("Movement")
local UtilRight = Tabs.Utility:AddRightGroupbox("Misc")

UtilLeft:AddToggle("SpeedHackEnabled",   { Text = "Speed Hack",       Default = false })
UtilLeft:AddSlider("SpeedHackValue",     { Text = "Hack Speed",       Default = 50, Min = 1, Max = 500, Rounding = 0, Suffix = " WS" })
UtilLeft:AddDivider()
UtilLeft:AddSlider("WalkSpeed",          { Text = "Walk Speed",       Default = 16, Min = 0, Max = 500, Rounding = 0, Suffix = " WS",
    Callback = function(v)
        if not (Toggles.SpeedHackEnabled and Toggles.SpeedHackEnabled.Value) then
            local h = GetHum() if h then h.WalkSpeed = v end
        end
    end })
UtilLeft:AddSlider("JumpPower",          { Text = "Jump Power",       Default = 50, Min = 0, Max = 500, Rounding = 0, Suffix = " JP",
    Callback = function(v) local h = GetHum() if h then h.JumpPower = v end end })
UtilLeft:AddToggle("InfiniteJump",       { Text = "Infinite Jump",    Default = false })

Library:GiveSignal(UIS.JumpRequest:Connect(function()
    if not (Toggles.InfiniteJump and Toggles.InfiniteJump.Value) then return end
    local h = GetHum() if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
end))

UtilRight:AddToggle("AntiAFK",           { Text = "Anti-AFK",         Default = false })
UtilRight:AddToggle("FullbrightEnabled", { Text = "Fullbright",       Default = false })
UtilRight:AddToggle("RemoveFog",         { Text = "Remove Fog",       Default = false })

local DefaultFogEnd = game:GetService("Lighting").FogEnd
local DefaultAmbient = game:GetService("Lighting").Ambient
local DefaultOutdoor = game:GetService("Lighting").OutdoorAmbient
local DefaultBrightness = game:GetService("Lighting").Brightness

Toggles.RemoveFog:OnChanged(function(s)
    game:GetService("Lighting").FogEnd = s and 1e9 or DefaultFogEnd
end)
Toggles.FullbrightEnabled:OnChanged(function(s)
    local L = game:GetService("Lighting")
    if s then
        L.Ambient = Color3.fromRGB(255, 255, 255) L.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        L.Brightness = 2 L.GlobalShadows = false L.FogEnd = 1e9
    else
        L.Ambient = DefaultAmbient L.OutdoorAmbient = DefaultOutdoor
        L.Brightness = DefaultBrightness L.GlobalShadows = true L.FogEnd = DefaultFogEnd
    end
end)
Toggles.AntiAFK:OnChanged(function(s)
    if s then task.spawn(function()
        local vu = game:GetService("VirtualUser")
        while Toggles.AntiAFK.Value do
            vu:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            task.wait(0.1)
            vu:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            task.wait(15)
        end
    end) end
end)

local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu")
MenuGroup:AddLabel("Menu Keybind"):AddKeyPicker("MenuKeybind", { Default = "RightControl", NoUI = true, Text = "Menu Keybind" })
Library.ToggleKeybind = Options.MenuKeybind
MenuGroup:AddDivider()
MenuGroup:AddButton({ Text = "Unload", Func = function()
    Library:Notify({ Title = "Unloading", Description = "Cleaning up...", Time = 2 })
    task.wait(0.5) Library:Unload()
end })

Toggles.SpeedHackEnabled:OnChanged(function(s)
    if s then ApplySpeedHack()
    else
        if SpeedHackConn then SpeedHackConn:Disconnect() SpeedHackConn = nil end
        local hum = GetHum()
        if hum then hum.WalkSpeed = Options.WalkSpeed and Options.WalkSpeed.Value or 16 end
    end
end)
Toggles.AutoClickEnabled:OnChanged(function(s)
    if s then
        if autoClickConn then autoClickConn:Disconnect() autoClickConn = nil end
        local last = 0
        autoClickConn = RunService.Heartbeat:Connect(function()
            if not Toggles.AutoClickEnabled.Value then autoClickConn:Disconnect() autoClickConn = nil return end
            local now = tick()
            local rate = Options.AutoClickRate and Options.AutoClickRate.Value or 20
            if now - last >= 1 / rate then last = now pcall(mouse1click) end
        end)
    else if autoClickConn then autoClickConn:Disconnect() autoClickConn = nil end end
end)
Toggles.HitboxEnabled:OnChanged(function(s) if not s then ResetAllHitboxes() end end)
RunService.Heartbeat:Connect(function()
    if KillLabel and KillLabel.SetText then KillLabel:SetText("Session Kills: " .. KillCount) end
end)

Library:OnUnload(function()
    ResetAllHitboxes() ReleaseAllSlots() CleanupAllChams()
    if SpeedHackConn then SpeedHackConn:Disconnect() end
    if autoClickConn then autoClickConn:Disconnect() end
    if FOVCircle.__OBJECT_EXISTS then FOVCircle:Remove() end
    if FOVPulse.__OBJECT_EXISTS then FOVPulse:Remove() end
    if LockLabelDraw.__OBJECT_EXISTS then LockLabelDraw:Remove() end
    velHistory = {} visCache = {} visCacheTime = {}
    local L = game:GetService("Lighting")
    L.Ambient = DefaultAmbient L.OutdoorAmbient = DefaultOutdoor
    L.Brightness = DefaultBrightness L.FogEnd = DefaultFogEnd
end)

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("Redliner")
SaveManager:SetFolder("Redliner/configs")
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
