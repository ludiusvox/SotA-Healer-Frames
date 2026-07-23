-- name: SotA Healer Frames
-- author: Ludiusvox
-- version: 1.0
-- description: Advanced 4x3 cubic healer frames for 12-man raids with prioritized buff/debuff tracking.

--.name SotA Healer Frames
--.author Ludiusvox
--.version 1.0
--.description Advanced 4x3 cubic healer frames for 12-man raids.
--.icon SotaHealerFrames.png

local ScriptName = "SotA Healer Frames";
local Version = "1.0";
local CreatorName = "Ludiusvox";
local Description = "Advanced 4x3 cubic healer frames for 12-man raids.";

-- SotaHealerFrames.lua
-- Advanced Healer Interface for Shroud of the Avatar
-- Implementation based on "Architectural Blueprint for Advanced Lua Interface Extensions"

-- [[ CONFIGURATION ]]
local config = {
    updateRate = 0.1,    -- 10 ticks per second (100ms)
    lastUpdate = 0,
    framesPos = { x = 0, y = 0, manual = false }, -- Centered dynamically unless moved
    frameSize = { w = 100, h = 100 }, -- Cubic/Square for easier clicking
    grid = { cols = 4, rows = 3 },    -- 4x3 grid for 12 players
    cubeSize = 32,
    cubePos = { x = 20, y = 150 },
    chatPos = { x = 10, y = 600 },
    settingsFile = "", -- Path set in ShroudOnStart
    colors = {
        hpHigh = "00FF00AA",
        hpMid = "FFFF00AA",
        hpLow = "FF0000AA",
        focus = "0000FFAA",
        bg = "00000088",
        soothingRain = "#00CCFF", -- Specific shade of blue
        knightsGrace = "#FFD700", -- Gold/Knightly
        digIn = "#C0C0C0",        -- Silver
        torpor = "#006400",       -- Dark Green
        douse = "#FF7F7FAA",      -- Light Red (Fire DoT)
        blind = "#FFFF00AA",      -- Yellow
        debuffGeneral = "#8B0000AA", -- Dark Red
        healingGrace = "#90EE90"   -- Light Green
    }
}

-- [[ STATE ]]
local partyData = {}
local buffsData = {}
local globalTrackedBuffs = {} -- [playerName][buffName] = expiry
local questJournal = {}
local chatLog = { social = {}, combat = {} }
local screenWidth = 1920
local screenHeight = 1080
local myName = ""

-- Buff Metadata
local BUFF_META = {
    ["Soothing Rain"] = { duration = 32, color = config.colors.soothingRain },
    ["Knight's Grace"] = { duration = 30, color = config.colors.knightsGrace },
    ["Dig In"] = { duration = 20, color = config.colors.digIn },
    ["Torpor"] = { duration = 30, color = config.colors.torpor },
    ["Healing Grace"] = { duration = 20, color = config.colors.healingGrace },
    -- Debuffs (Tracked via Chat)
    ["Burning"] = { duration = 15, isDebuff = true, color = config.colors.douse },
    ["Fire Arrow"] = { duration = 10, isDebuff = true, color = config.colors.douse },
    ["Blinded"] = { duration = 8, isDebuff = true, color = config.colors.blind },
    ["Blind"] = { duration = 8, isDebuff = true, color = config.colors.blind },
    ["Stunned"] = { duration = 4, isDebuff = true, color = config.colors.debuffGeneral },
    ["Rooted"] = { duration = 6, isDebuff = true, color = config.colors.debuffGeneral }
}

-- [[ CALLBACKS ]]

function ShroudOnStart()
    ShroudLog("SotA Healer Frames v1.1 - Loaded")
    screenWidth = ShroudGetScreenX()
    screenHeight = ShroudGetScreenY()
    myName = ShroudGetPlayerName()

    -- Set settings path (R151 compatibility)
    config.settingsFile = ShroudLuaPath .. "/SotaHealerFrames/user.ini"
    LoadSettings()

    -- Hide native party UI to avoid redundancy
    if ShroudHideNativeParty then
        ShroudHideNativeParty(true)
        ShroudLog("Native party frames hidden.")
    end
end

function ShroudOnDisableScript()
    SaveSettings()
    -- Restore native party UI when the script is disabled
    if ShroudHideNativeParty then
        ShroudHideNativeParty(false)
        ShroudLog("Native party frames restored.")
    end
end

function ShroudOnUpdate()
    local now = ShroudGetTime()
    if now - config.lastUpdate < config.updateRate then return end
    config.lastUpdate = now

    UpdatePartyData()
    UpdateBuffData()
    CleanupTrackedBuffs(now)
end

function ShroudOnGUI()
    DrawRaidFrames()
    DrawLegend()
    DrawStatusCubes()
    DrawQuestTicker()
    DrawEnhancedChat()
end

function ShroudOnConsoleInput(channel, sender, message)
    ProcessIncomingChat(channel, sender, message)
end

-- [[ DATA ACQUISITION ]]

function UpdatePartyData()
    partyData = {}
    local count = ShroudGetPartyMemberCount()

    -- We want a fixed 12-slot array where the player is in a central "Power Spot"
    -- In a 4x3 grid (indices 1-12), indices 6 and 7 are the most central.
    local playerSlot = 6

    local others = {}
    if count > 0 then
        for i = 1, count do
            table.insert(others, ShroudGetPartyMemberName(i))
        end
    end

    local otherIdx = 1
    for i = 1, 12 do
        local name = nil
        if i == playerSlot then
            name = myName
        elseif otherIdx <= #others then
            name = others[otherIdx]
            otherIdx = otherIdx + 1
        end

        if name then
            local hp, maxHp, focus, maxFocus = 0, 0, 0, 0
            if name == myName then
                hp = ShroudGetStat(0)
                maxHp = ShroudGetStat(1)
                focus = ShroudGetStat(2)
                maxFocus = ShroudGetStat(3)
            else
                -- Find the original party index for this name
                local pIdx = -1
                for j = 1, count do
                    if ShroudGetPartyMemberName(j) == name then pIdx = j break end
                end
                if pIdx ~= -1 then
                    hp = ShroudGetPartyMemberStat(pIdx, 0)
                    maxHp = ShroudGetPartyMemberStat(pIdx, 1)
                    focus = ShroudGetPartyMemberStat(pIdx, 2)
                    maxFocus = ShroudGetPartyMemberStat(pIdx, 3)
                end
            end

            partyData[i] = {
                name = name,
                hp = hp,
                maxHp = maxHp,
                focus = focus,
                maxFocus = maxFocus,
                buffs = globalTrackedBuffs[name] or {}
            }
        else
            partyData[i] = nil -- Empty slot
        end
    end
end

function UpdateBuffData()
    buffsData = {}
    local count = ShroudGetBuffCount()
    for i = 0, count - 1 do
        local name = ShroudGetBuffName(i)
        local timeLeft = ShroudGetBuffTimeRemaining(i)
        -- We assume a 10 min default for ratio calculation if max unknown
        local ratio = timeLeft / 600
        table.insert(buffsData, { name = name, time = timeLeft, ratio = ratio })
    end
end

-- [[ RENDERING LOGIC ]]

function DrawRaidFrames()
    local cols = config.grid.cols
    local rows = config.grid.rows
    local w = config.frameSize.w
    local h = config.frameSize.h
    local spacing = 8

    -- Calculate center of screen or use saved position
    local gridWidth = cols * (w + spacing) - spacing
    local gridHeight = rows * (h + spacing) - spacing

    local startX, startY
    if config.framesPos.manual then
        startX = config.framesPos.x
        startY = config.framesPos.y
    else
        startX = screenWidth / 2 - gridWidth / 2
        startY = screenHeight / 2 - gridHeight / 2
    end

    for i = 1, 12 do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = startX + col * (w + spacing)
        local y = startY + row * (h + spacing)

        local member = partyData[i]

        -- Main Frame Box (always draw slots for "cubic" feel)
        ShroudGUIBox(x, y, w, h, member and "" or "Empty")

        if member then
            -- HP Vertical Bar (Background)
            if member.maxHp > 0 then
                local ratio = member.hp / member.maxHp
                local hpH = (h - 20) * ratio
                -- Using a label as a background color bar
                local color = config.colors.hpHigh
                if ratio < 0.3 then color = config.colors.hpLow elseif ratio < 0.6 then color = config.colors.hpMid end

                -- Draw HP Fill
                ShroudGUILabel(x + 5, y + (h - 15) - hpH, w - 10, hpH, string.format("<color=%s>█</color>", color))

                -- HP Text
                ShroudGUILabel(x + 5, y + h - 20, w - 10, 20, string.format("%d%%", math.floor(ratio * 100)))
            end

            -- Name Overlay (Centered)
            ShroudGUILabel(x + 5, y + 5, w - 10, 20, member.name:sub(1, 8))

            -- [[ BUFF INDICATORS ]]

            -- Soothing Rain (Top Left)
            if member.buffs["Soothing Rain"] then
                local colorText = string.format("<color=%s>█</color>", config.colors.soothingRain)
                ShroudGUILabel(x + 2, y + 2, 15, 15, colorText)
            end

            -- Dig In (Silver - Top Right)
            if member.buffs["Dig In"] then
                local colorText = string.format("<color=%s>█</color>", config.colors.digIn)
                ShroudGUILabel(x + w - 15, y + 2, 15, 15, colorText)
            end

            -- Torpor (Dark Green - Bottom Left)
            if member.buffs["Torpor"] then
                local colorText = string.format("<color=%s>█</color>", config.colors.torpor)
                ShroudGUILabel(x + 2, y + h - 15, 15, 15, colorText)
            end

            -- Healing Grace (Light Green - Bottom Right)
            if member.buffs["Healing Grace"] then
                local colorText = string.format("<color=%s>█</color>", config.colors.healingGrace)
                ShroudGUILabel(x + w - 15, y + h - 15, 15, 15, colorText)
            end

            -- [[ DEBUFF INDICATORS ]]
            local activeDebuffColor = nil
            for bName, _ in pairs(member.buffs) do
                local meta = BUFF_META[bName]
                if meta and meta.isDebuff then
                    if meta.color == config.colors.blind then
                        activeDebuffColor = config.colors.blind
                    elseif meta.color == config.colors.douse and activeDebuffColor ~= config.colors.blind then
                        activeDebuffColor = config.colors.douse
                    elseif not activeDebuffColor then
                        activeDebuffColor = config.colors.debuffGeneral
                    end
                end
            end

            if activeDebuffColor then
                local colorText = string.format("<color=%s>█</color>", activeDebuffColor)
                -- Right side indicator strip
                ShroudGUILabel(x + w - 12, y + 15, 10, h - 30, colorText .. "\n" .. colorText .. "\n" .. colorText .. "\n" .. colorText)
            end
        end
    end
end

function DrawStatusCubes()
    -- Native Buff Cubes
    for i, buff in ipairs(buffsData) do
        local row = math.floor((i-1) / 8)
        local col = (i-1) % 8
        local x = config.cubePos.x + col * (config.cubeSize + 4)
        local y = config.cubePos.y + row * (config.cubeSize + 4)

        local stateText = buff.name:sub(1,2)
        if buff.ratio < 0.25 then stateText = "!!" .. stateText end

        ShroudGUIBox(x, y, config.cubeSize, config.cubeSize, stateText)

        -- Special Color for Knight's Grace if in native buffs
        if buff.name == "Knight's Grace" then
            local colorText = string.format("<color=%s>K</color>", config.colors.knightsGrace)
            ShroudGUILabel(x + 2, y + 2, 20, 20, colorText)
        end
    end

    -- Tracked Knight's Grace (if not in native list but tracked)
    if globalTrackedBuffs[myName] and globalTrackedBuffs[myName]["Knight's Grace"] then
        -- Draw in a special "tracked" corner if desired, or just ensure it's highlighted
    end
end

function DrawLegend()
    local cols = config.grid.cols
    local w = config.frameSize.w
    local spacing = 8

    local gridWidth = cols * (w + spacing) - spacing
    local startX = screenWidth / 2 + gridWidth / 2 + 30
    local startY = screenHeight / 2 - 130

    local legendW = 180
    local legendH = 260

    -- Main Legend Container
    ShroudGUIBox(startX, startY, legendW, legendH, "")

    -- Header "Styled" Label
    ShroudGUILabel(startX + 10, startY + 5, legendW - 20, 25, "<b><size=14><color=#FFFFFF>INTERFACE LEGEND</color></size></b>")

    local function drawEntry(idx, color, text, subtext)
        local y = startY + 40 + (idx * 28)
        -- Icon with "CSS-like" shadow effect using two labels
        ShroudGUILabel(startX + 12, y + 2, 20, 20, "<color=#000000AA>█</color>")
        ShroudGUILabel(startX + 10, y, 20, 20, string.format("<color=%s>█</color>", color))

        -- Text labels
        ShroudGUILabel(startX + 35, y, legendW - 45, 20, "<b>" .. text .. "</b>")
        if subtext then
            ShroudGUILabel(startX + 35, y + 12, legendW - 45, 15, "<size=10><color=#CCCCCC>" .. subtext .. "</color></size>")
        end
    end

    -- Buff Section
    drawEntry(0, config.colors.soothingRain, "Soothing Rain", "32s - Top Left")
    drawEntry(1, config.colors.digIn, "Dig In", "Aura - Top Right")
    drawEntry(2, config.colors.torpor, "Torpor", "Regen - Bottom Left")
    drawEntry(3, config.colors.knightsGrace, "Knight's Grace", "Corner Highlight")

    -- Debuff Section
    ShroudGUILabel(startX + 10, startY + 155, legendW - 20, 2, "<color=#555555>_____________________</color>")
    drawEntry(4.5, config.colors.blind, "Blindness", "Yellow - High Priority")
    drawEntry(5.5, config.colors.douse, "Fire Damage", "Light Red - Douse!")
    drawEntry(6.5, config.colors.debuffGeneral, "General Debuff", "Dark Red - CC/Other")

    -- New entry for Healing Grace
    drawEntry(7.5, config.colors.healingGrace, "Healing Grace", "Light Green - Bottom Right")

    -- Adjust Legend Height
    legendH = 290
end

function DrawQuestTicker()
    local x = screenWidth - 220
    local y = 100
    ShroudGUILabel(x, y, 200, 20, "QUEST LOG (BETA)")

    for i, q in ipairs(questJournal) do
        if i > #questJournal - 5 then
            local offset = (i - (#questJournal - 4)) * 20
            ShroudGUILabel(x, y + offset, 200, 20, "> " .. q.text)
        end
    end
end

function DrawEnhancedChat()
    local x = config.chatPos.x
    local y = screenHeight - 200

    ShroudGUIBox(x, y, 400, 180, "Enhanced Chat (Combat)")

    local lines = 0
    for i = #chatLog.combat, 1, -1 do
        if lines < 8 then
            local entry = chatLog.combat[i]
            ShroudGUILabel(x + 10, y + 160 - (lines * 18), 380, 20, entry.message)
            lines = lines + 1
        end
    end
end

-- [[ CHAT INTERCEPTION & PARSING ]]

function ProcessIncomingChat(channel, sender, message)
    local entry = { sender = sender, message = message, time = ShroudGetTime() }

    -- Buff Tracking (Parsing)
    -- Pattern: "PlayerName is now under the effect of BuffName."
    local pName, bName = message:match("^(.-) is now under the effect of (.-)%.")
    if not pName then
        -- Pattern: "You are now under the effect of BuffName."
        bName = message:match("^You are now under the effect of (.-)%.")
        if bName then pName = myName end
    end

    if pName and bName and BUFF_META[bName] then
        if not globalTrackedBuffs[pName] then globalTrackedBuffs[pName] = {} end
        globalTrackedBuffs[pName][bName] = ShroudGetTime() + BUFF_META[bName].duration
    end

    -- Loss of Buff
    pName, bName = message:match("^(.-) has lost the effect of (.-)%.")
    if not pName then
        bName = message:match("^You have lost the effect of (.-)%.")
        if bName then pName = myName end
    end
    if pName and bName and globalTrackedBuffs[pName] then
        globalTrackedBuffs[pName][bName] = nil
    end

    -- Categorization Engine
    if channel == "Combat" or message:find("points of damage") or message:find("healed") then
        table.insert(chatLog.combat, entry)
        if #chatLog.combat > 100 then table.remove(chatLog.combat, 1) end
    else
        table.insert(chatLog.social, entry)
        if #chatLog.social > 100 then table.remove(chatLog.social, 1) end
    end

    -- Quest Parsing (Task Complete / Updated)
    if message:find("Task Complete") or message:find("Quest Updated") or message:find("Journal Updated") then
        table.insert(questJournal, { text = message, time = ShroudGetTime() })
        if #questJournal > 20 then table.remove(questJournal, 1) end
    end
end

-- [[ UTILS ]]

function LoadSettings()
    local file = io.open(config.settingsFile, "r")
    if not file then return end

    for line in file:lines() do
        local param, value = line:match('^([%w|_]+)%s-=%s-(.+)$')
        if param and value then
            if param == 'framesX' then config.framesPos.x = tonumber(value)
            elseif param == 'framesY' then config.framesPos.y = tonumber(value)
            elseif param == 'framesManual' then config.framesPos.manual = (value == 'true')
            end
        end
    end
    file:close()
end

function SaveSettings()
    local file = io.open(config.settingsFile, "w")
    if not file then return end

    file:write("framesX=" .. tostring(config.framesPos.x) .. "\n")
    file:write("framesY=" .. tostring(config.framesPos.y) .. "\n")
    file:write("framesManual=" .. tostring(config.framesPos.manual) .. "\n")
    file:close()
end

function CleanupTrackedBuffs(now)
    for pName, buffs in pairs(globalTrackedBuffs) do
        for bName, expiry in pairs(buffs) do
            if now > expiry then
                buffs[bName] = nil
            end
        end
    end
end

function ShroudLog(msg)
    if ShroudIncomingChatMessage then
        ShroudIncomingChatMessage(msg, "Lua")
    else
        -- Fallback if not in-game environment
        print(msg)
    end
end
