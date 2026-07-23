-- name: SotA Healer Frames
-- author: Ludiusvox
-- version: 1.0
-- description: Advanced 4x3 cubic healer frames for 12-man raids with prioritized buff/debuff tracking.

--.name SotA Healer Frames
--.author Ludiusvox
--.version 1.0
--.description Advanced 4x3 cubic healer frames for 12-man raids.
--.icon SotaHealerFrames/SotaHealerFrames.png

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
    legendPos = { x = 0, y = 0, manual = false }, -- Centered dynamically unless moved
    frameSize = { w = 100, h = 100 }, -- Cubic/Square for easier clicking
    grid = { cols = 4, rows = 3 },    -- 4x3 grid for 12 players
    cubeSize = 32,
    cubePos = { x = 20, y = 150 },
    chatPos = { x = 10, y = 600 },
    settingsFile = "", -- Path set in ShroudOnStart
    colors = {
        hpHigh = "#00FF00B2", -- 70% opacity green
        hpMid  = "#FFFF00B2", -- 70% opacity yellow
        hpLow  = "#FF0000B2", -- 70% opacity red
        focus = "#0000FFB2",
        bg = "#222222FF",
        soothingRain = "#00CCFF",
        knightsGrace = "#FFD700",
        digIn = "#C0C0C0",
        torpor = "#006400",
        douse = "#FF7F7F",
        blind = "#FFFF00",
        debuffGeneral = "#8B0000",
        healingGrace = "#90EE90",
        valiantWarden = "#660000",  -- Deep Dark Red
        purifyBurst = "#E0FFFF"     -- Light Cyan/White
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
    ["Soothing Rain"] = { duration = 32, color = config.colors.soothingRain, phrase = "Quaes-Wast-Vatu" },
    ["Knight's Grace"] = { duration = 30, color = config.colors.knightsGrace }, -- Combat Skill (No Phrase)
    ["Dig In"] = { duration = 20, color = config.colors.digIn },              -- Combat Skill (No Phrase)
    ["Torpor"] = { duration = 30, color = config.colors.torpor, phrase = "Asen-Terra" },
    ["Healing Grace"] = { duration = 20, color = config.colors.healingGrace, phrase = "In-Reno" },
    ["Douse"] = { duration = 30, color = config.colors.soothingRain },
    ["Purify Burst"] = { duration = 20, color = config.colors.purifyBurst },
    ["Valiant Warden"] = { duration = 30, color = config.colors.valiantWarden },
    -- Debuffs (Tracked via Chat)
    ["Burning"] = { duration = 15, isDebuff = true, color = config.colors.douse },
    ["Fire Arrow"] = { duration = 10, isDebuff = true, color = config.colors.douse },
    ["Blinded"] = { duration = 8, isDebuff = true, color = config.colors.blind },
    ["Blind"] = { duration = 8, isDebuff = true, color = config.colors.blind },
    ["Stunned"] = { duration = 4, isDebuff = true, color = config.colors.debuffGeneral },
    ["Rooted"] = { duration = 6, isDebuff = true, color = config.colors.debuffGeneral }
}

-- Phrase Mapping (Magic Words -> Buff Name)
local PHRASE_TO_BUFF = {
    ["Desen-Vatu"] = "Douse",
    ["Quaes-Wast-Vatu"] = "Soothing Rain",
    ["Asen-Terra"] = "Torpor",
    ["In-Reno"] = "Healing Grace"
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
    local now = ShroudTime or 0
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
    -- Command Parsing
    local cmd, arg1, arg2 = message:match("^/shf (%w+)%s?(%-?%d*)%s?(%-?%d*)")
    if cmd then
        if cmd == "legend" then
            if arg1 ~= "" and arg2 ~= "" then
                config.legendPos.x = tonumber(arg1)
                config.legendPos.y = tonumber(arg2)
                config.legendPos.manual = true
                ShroudLog("Legend moved to " .. arg1 .. ", " .. arg2)
                SaveSettings()
            else
                ShroudLog("Usage: /shf legend <x> <y>")
            end
            return
        elseif cmd == "frames" then
            if arg1 ~= "" and arg2 ~= "" then
                config.framesPos.x = tonumber(arg1)
                config.framesPos.y = tonumber(arg2)
                config.framesPos.manual = true
                ShroudLog("Frames moved to " .. arg1 .. ", " .. arg2)
                SaveSettings()
            else
                ShroudLog("Usage: /shf frames <x> <y>")
            end
            return
        elseif cmd == "reset" then
            config.framesPos.manual = false
            config.legendPos.manual = false
            ShroudLog("Positions reset to default.")
            SaveSettings()
            return
        end
    end
end

-- Callback for all incoming chat (Buff tracking, etc.)
function ShroudOnChat(message, sender, channel)
    ProcessIncomingChat(channel, sender, message)
end

-- [[ DATA ACQUISITION ]]

function UpdatePartyData()
    partyData = {}
    local count = 0
    if ShroudGetPartyMemberCount then count = ShroudGetPartyMemberCount() end

    local members = {}

    -- 1. Local Player Data
    local myBuffs = {}
    if ShroudGetBuffCount then
        for i = 0, ShroudGetBuffCount() - 1 do
            local bName = ShroudGetBuffName(i)
            if bName then myBuffs[bName] = true end
        end
    end

    local myData = {
        name = myName,
        hp = GetMyStat(14) or 0,
        maxHp = GetMyStat(30) or 1,
        focus = GetMyStat(13) or 0,
        maxFocus = GetMyStat(27) or 1,
        buffs = myBuffs
    }

    -- 2. Party Members (Modern R151 API with Buffs support)
    if count > 0 then
        for i = 1, count do
            local name = nil
            if ShroudGetPartyMemberName then name = ShroudGetPartyMemberName(i) end

            if name and name ~= "" and name ~= "None" then
                -- Normalize names for comparison
                local isSelf = (name == myName) or name:find(myName) or myName:find(name)

                if not isSelf then
                    local hp, maxHp, focus, maxFocus = 0, 1, 0, 1
                    local pBuffs = {}

                    -- Check for new R151 ShroudGetPartyMemberData
                    if ShroudGetPartyMemberData then
                        local data = ShroudGetPartyMemberData(i)
                        if data then
                            name = data.Name or name
                            hp = data.Health or 0
                            maxHp = data.MaxHealth or 1
                            focus = data.Focus or 0
                            maxFocus = data.MaxFocus or 1

                            -- Extract Buffs from the new R151 table
                            if data.Buffs then
                                for _, b in ipairs(data.Buffs) do
                                    if b.name then pBuffs[b.name] = true end
                                end
                            end
                        end
                    elseif ShroudGetPartyMemberStat then
                        hp = ShroudGetPartyMemberStat(i, 14) or 0
                        maxHp = ShroudGetPartyMemberStat(i, 30) or 1
                        focus = ShroudGetPartyMemberStat(i, 13) or 0
                        maxFocus = ShroudGetPartyMemberStat(i, 27) or 1
                    end

                    table.insert(members, {
                        name = name,
                        hp = hp,
                        maxHp = maxHp,
                        focus = focus,
                        maxFocus = maxFocus,
                        buffs = pBuffs
                    })
                end
            end
        end
    end

    local playerSlot = 6
    local memberIdx = 1
    for i = 1, 12 do
        if i == playerSlot then
            partyData[i] = myData
        elseif memberIdx <= #members then
            partyData[i] = members[memberIdx]
            memberIdx = memberIdx + 1
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

local function HasBuff(member, searchName)
    if not member or not member.buffs then return false end
    searchName = searchName:lower()
    for bName, _ in pairs(member.buffs) do
        if bName:lower():find(searchName) then return true end
    end
    return false
end

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

        -- Main Frame Square (Clickable Button for Targeting)
        -- Background Fill / Border
        if ShroudGUIBox then
            ShroudGUIBox(x, y, w, h, "")
        end

        if member then
            -- HP Vertical Bar (70% Opacity Full Box Fill)
            if member.maxHp > 0 then
                local ratio = member.hp / member.maxHp
                local hpH = math.floor(h * ratio)
                local color = config.colors.hpHigh
                if ratio < 0.3 then color = config.colors.hpLow elseif ratio < 0.6 then color = config.colors.hpMid end

                -- Draw HP Fill (Using extremely large size to fill background)
                if ShroudGUILabel then
                    -- Stacking multiple blocks for full width and using height scaling
                    local fillText = string.format("<size=%d><color=%s>█</color></size>", h, color)
                    ShroudGUILabel(x, y + (h - hpH), w, hpH, fillText)
                end
            end

            if ShroudGUIButton and ShroudGUIButton(x, y, w, h, "") then
                -- Action: Target the player
                ShroudConsoleInput("/target " .. member.name)
                ShroudLog("Targeting: " .. member.name)
            end

            -- Name Overlay (Top Center with Shadow)
            if ShroudGUILabel then
                ShroudGUILabel(x + 1, y + 11, w, 20, "<color=#000000FF><b>" .. member.name:sub(1, 15) .. "</b></color>")
                ShroudGUILabel(x, y + 10, w, 20, "<b>" .. member.name:sub(1, 15) .. "</b>")

                -- HP Text (Bottom Center with Shadow)
                local hpP = math.floor((member.hp / member.maxHp) * 100)
                ShroudGUILabel(x + 1, y + h - 21, w, 20, string.format("<color=#000000FF><b>%d%%</b></color>", hpP))
                ShroudGUILabel(x, y + h - 22, w, 20, string.format("<b>%d%%</b>", hpP))
            end

            -- [[ BUFF INDICATORS ]]

            -- Soothing Rain / Douse (Top Left)
            if (HasBuff(member, "Soothing Rain") or HasBuff(member, "Douse")) and ShroudGUILabel then
                local colorText = string.format("<color=%s>█</color>", config.colors.soothingRain)
                ShroudGUILabel(x + 2, y + 2, 15, 15, colorText)
            end

            -- Dig In / Knight's Grace (Silver/Gold - Top Right)
            if (HasBuff(member, "Dig In") or HasBuff(member, "Knight's Grace") or HasBuff(member, "Knights Grace")) and ShroudGUILabel then
                local isGrace = HasBuff(member, "Grace")
                local color = isGrace and config.colors.knightsGrace or config.colors.digIn
                local colorText = string.format("<color=%s>█</color>", color)
                ShroudGUILabel(x + w - 15, y + 2, 15, 15, colorText)
            end

            -- Torpor / Valiant Warden (Bottom Left)
            if (HasBuff(member, "Torpor") or HasBuff(member, "Valiant Warden")) and ShroudGUILabel then
                local isValiant = HasBuff(member, "Valiant")
                local color = isValiant and config.colors.valiantWarden or config.colors.torpor
                local colorText = string.format("<color=%s>█</color>", color)
                ShroudGUILabel(x + 2, y + h - 15, 15, 15, colorText)
            end

            -- Healing Grace / Purify Burst (Bottom Right)
            if (HasBuff(member, "Healing Grace") or HasBuff(member, "Purify Burst")) and ShroudGUILabel then
                local isPurify = HasBuff(member, "Purify")
                local color = isPurify and config.colors.purifyBurst or config.colors.healingGrace
                local colorText = string.format("<color=%s>█</color>", color)
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

            if activeDebuffColor and ShroudGUILabel then
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

        if ShroudGUIBox then
            ShroudGUIBox(x, y, config.cubeSize, config.cubeSize, stateText)
        end

        -- Special Color for Knight's Grace if in native buffs
        if buff.name == "Knight's Grace" and ShroudGUILabel then
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

    local startX, startY
    if config.legendPos.manual then
        startX = config.legendPos.x
        startY = config.legendPos.y
    else
        startX = screenWidth / 2 + gridWidth / 2 + 30
        startY = screenHeight / 2 - 130
    end

    local legendW = 240 -- Increased from 220
    local legendH = 420 -- Adjusted for new spacing

    -- Main Legend Container
    if ShroudGUIBox then
        ShroudGUIBox(startX, startY, legendW, legendH, "")
    end

    -- Header "Styled" Label
    if ShroudGUILabel then
        ShroudGUILabel(startX + 10, startY + 5, legendW - 20, 25, "<b><size=14><color=#FFFFFF>INTERFACE LEGEND</color></size></b>")
    end

    local function drawEntry(idx, color, text, subtext)
        local y = startY + 45 + (idx * 42) -- Increased vertical spacing from 38 to 42

        if ShroudGUILabel then
            -- Icon with "CSS-like" shadow effect using two labels
            ShroudGUILabel(startX + 12, y + 2, 20, 20, "<color=#000000AA>█</color>")
            ShroudGUILabel(startX + 10, y, 20, 20, string.format("<color=%s>█</color>", color))

            -- Text labels
            ShroudGUILabel(startX + 35, y, legendW - 45, 20, "<b>" .. text .. "</b>")
            if subtext then
                -- Increased spacing to subtext and width for long descriptions
                ShroudGUILabel(startX + 35, y + 16, legendW - 40, 20, "<size=10><color=#CCCCCC>" .. subtext .. "</color></size>")
            end
        end
    end

    -- Buff Section
    drawEntry(0, config.colors.soothingRain, "Rain/Douse", "Blue - Top Left")
    drawEntry(1, config.colors.digIn, "Dig In/Grace", "Silver/Gold - Top Right")
    drawEntry(2, config.colors.torpor, "Torpor", "Regen - Bottom Left")
    drawEntry(3, config.colors.valiantWarden, "Valiant Warden", "Dark Red - Bottom Left")

    -- Debuff Section
    if ShroudGUILabel then
        ShroudGUILabel(startX + 10, startY + 215, legendW - 20, 2, "<color=#555555>__________________________</color>")
    end
    drawEntry(5.4, config.colors.blind, "Blindness", "Yellow - High Priority")
    drawEntry(6.4, config.colors.douse, "Fire Damage", "Light Red - Douse!")
    drawEntry(7.4, config.colors.debuffGeneral, "General Debuff", "Dark Red - CC/Other")

    -- New entries for Healing Grace and Purify Burst
    drawEntry(8.4, config.colors.healingGrace, "Healing Grace", "Light Green - Bottom Right")
    drawEntry(9.4, config.colors.purifyBurst, "Purify Burst", "Cyan/White - Bottom Right")

    -- Adjust Legend Height
    legendH = 460
end

function DrawQuestTicker()
    local x = screenWidth - 220
    local y = 100
    if ShroudGUILabel then
        ShroudGUILabel(x, y, 200, 20, "QUEST LOG (BETA)")

        for i, q in ipairs(questJournal) do
            if i > #questJournal - 5 then
                local offset = (i - (#questJournal - 4)) * 20
                ShroudGUILabel(x, y + offset, 200, 20, "> " .. q.text)
            end
        end
    end
end

function DrawEnhancedChat()
    local x = config.chatPos.x
    local y = screenHeight - 200

    if ShroudGUIBox then
        ShroudGUIBox(x, y, 400, 180, "Enhanced Chat (Combat)")
    end

    local lines = 0
    for i = #chatLog.combat, 1, -1 do
        if lines < 8 then
            local entry = chatLog.combat[i]
            if ShroudGUILabel then
                ShroudGUILabel(x + 10, y + 160 - (lines * 18), 380, 20, entry.message)
            end
            lines = lines + 1
        end
    end
end

-- [[ CHAT INTERCEPTION & PARSING ]]

function ProcessIncomingChat(channel, sender, message)
    local now = ShroudTime or 0
    local entry = { sender = sender, message = message, time = now }

    -- 1. Magic Phrase Tracking (Words of Power)
    -- Pattern: "Player Name utters the phrase Magic-Words."
    local pName, phrase = message:match("^(.-) utters the phrase (.-)%.")
    if pName and phrase then
        local bName = PHRASE_TO_BUFF[phrase]
        if bName then
            -- Special handling for Douse (Clear Fire Debuffs)
            if bName == "Douse" then
                if globalTrackedBuffs[pName] then
                    globalTrackedBuffs[pName]["Burning"] = nil
                    globalTrackedBuffs[pName]["Fire Arrow"] = nil
                end
            elseif BUFF_META[bName] then
                if not globalTrackedBuffs[pName] then globalTrackedBuffs[pName] = {} end
                globalTrackedBuffs[pName][bName] = now + BUFF_META[bName].duration
            end
        end
    end

    -- 2. Standard Buff/Debuff Tracking (Parsing)
    -- Broadening patterns to catch various system message formats
    local pName2, bName2 = message:match("^(.-) is now under the effect of (.-)%.")
    if not pName2 then pName2, bName2 = message:match("^(.-) is now affected by (.-)%.") end

    if not pName2 then
        bName2 = message:match("^You are now under the effect of (.-)%.")
        if not bName2 then bName2 = message:match("^You are now affected by (.-)%.") end
        if bName2 then pName2 = myName end
    end

    if pName2 and bName2 and BUFF_META[bName2] then
        if not globalTrackedBuffs[pName2] then globalTrackedBuffs[pName2] = {} end
        globalTrackedBuffs[pName2][bName2] = now + BUFF_META[bName2].duration
        -- ShroudLog("Buff Detected: " .. bName2 .. " on " .. pName2) -- Debug
    end

    -- Loss of Buff
    local lpName, lbName = message:match("^(.-) has lost the effect of (.-)%.")
    if not lpName then
        lbName = message:match("^You have lost the effect of (.-)%.")
        if lbName then lpName = myName end
    end
    if lpName and lbName and globalTrackedBuffs[lpName] then
        globalTrackedBuffs[lpName][lbName] = nil
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
        table.insert(questJournal, { text = message, time = now })
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
            elseif param == 'legendX' then config.legendPos.x = tonumber(value)
            elseif param == 'legendY' then config.legendPos.y = tonumber(value)
            elseif param == 'legendManual' then config.legendPos.manual = (value == 'true')
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
    file:write("legendX=" .. tostring(config.legendPos.x) .. "\n")
    file:write("legendY=" .. tostring(config.legendPos.y) .. "\n")
    file:write("legendManual=" .. tostring(config.legendPos.manual) .. "\n")
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
    if ShroudConsoleLog then
        ShroudConsoleLog(msg)
    elseif ShroudIncomingChatMessage then
        ShroudIncomingChatMessage(msg, "Lua")
    else
        -- Fallback if not in-game environment
        print(msg)
    end
end

function GetMyStat(id)
    if ShroudGetStatValueByNumber then
        return ShroudGetStatValueByNumber(id)
    elseif ShroudGetStat then
        return ShroudGetStat(id)
    end
    return 0
end
