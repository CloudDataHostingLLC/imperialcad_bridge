local QBCore = exports['qb-core']:GetCoreObject()

-- ======================= Basics =======================
local function getCitizenId(src)
    local P = QBCore.Functions.GetPlayer(src)
    return P and P.PlayerData and P.PlayerData.citizenid or nil
end

local function getAPIKey() return GetConvar("imperialAPI", "") end
local function getCommunityId() return GetConvar("imperial_community_id", "") end

-- ======================= Config: Registration Expiration =======================
-- Change how long registrations last (in months).
local REG_EXPIRES_IN_MONTHS = 12

local function addMonthsToDate(utcNow, months)
    local y = tonumber(os.date("!%Y", utcNow))
    local m = tonumber(os.date("!%m", utcNow))
    local d = tonumber(os.date("!%d", utcNow))
    m = m + months
    y = y + math.floor((m - 1) / 12)
    m = ((m - 1) % 12) + 1
    if d > 28 then d = 28 end -- simple month-end clamp
    return os.time({ year = y, month = m, day = d, hour = 0, min = 0, sec = 0, isdst = false })
end

local function computeRegExpirationISO()
    local now = os.time(os.date("!*t"))              -- UTC now
    local exp = addMonthsToDate(now, REG_EXPIRES_IN_MONTHS)
    return os.date("!%Y-%m-%d", exp)                 -- "YYYY-MM-DD" (JSON string)
end

-- ======================= Color map =======================
local COLOR = {
    [0]="Black",[1]="Black",[2]="Black",[3]="Silver",[4]="Silver",[5]="Gray",
    [6]="Gray",[7]="Gray",[8]="Silver",[9]="White",[10]="White",[11]="White",
    [12]="Blue",[13]="Blue",[27]="Green",[28]="Green",[34]="Red",[35]="Red",
}
local function colorName(idx) return COLOR[tonumber(idx) or -1] or "Black" end

-- ======================= VIN generator (EKY, check digit, A–Z/0–9) =======================
local VIN_ALPH = "ABCDEFGHJKLMNPRSTUVWXYZ"  -- no I/O/Q
local function vin_char_from_num(n)
    if n < 10 then return tostring(n) end
    return VIN_ALPH:sub((n-10) % #VIN_ALPH + 1, (n-10) % #VIN_ALPH + 1)
end

local YEAR_CODES = {
    [2010]='A',[2011]='B',[2012]='C',[2013]='D',[2014]='E',[2015]='F',[2016]='G',[2017]='H',
    [2018]='J',[2019]='K',[2020]='L',[2021]='M',[2022]='N',[2023]='P',[2024]='R',[2025]='S',
    [2026]='T',[2027]='V',[2028]='W',[2029]='X',[2030]='Y',[2031]='1',[2032]='2',[2033]='3',
    [2034]='4',[2035]='5',[2036]='6',[2037]='7',[2038]='8',[2039]='9'
}

local function bytehash(s)
    local h1,h2,h3 = 2166136261, 16777619, 0
    for i=1,#s do
        h1 = (h1 ~ s:byte(i)) * 16777619 % 2^32
        h2 = (h2 ~ (s:byte(i) * 31)) * 2166136261 % 2^32
        h3 = (h3 + s:byte(i) * (i%13+1)) % 2^32
    end
    return h1, h2, h3
end

local function vin_check_digit(vin17_with_placeholder_at_9)
    local translit = {
        A=1,B=2,C=3,D=4,E=5,F=6,G=7,H=8,J=1,K=2,L=3,M=4,N=5,P=7,R=9,S=2,T=3,U=4,V=5,W=6,X=7,Y=8,Z=9,
        ["1"]=1,["2"]=2,["3"]=3,["4"]=4,["5"]=5,["6"]=6,["7"]=7,["8"]=8,["9"]=9,["0"]=0
    }
    local weights = {8,7,6,5,4,3,2,10,0,9,8,7,6,5,4,3,2}
    local sum = 0
    for i=1,17 do
        local c = vin17_with_placeholder_at_9:sub(i,i)
        local v = translit[c] or 0
        sum = sum + v * weights[i]
    end
    local r = sum % 11
    return (r == 10) and "X" or tostring(r)
end

local function generateVIN(model, year, plateNoSpace, charid)
    local y = tonumber(year) or 2015
    local wmi = "EKY"  -- requested prefix
    local seed = (tostring(model).."|"..tostring(plateNoSpace).."|"..tostring(charid).."|"..tostring(y)):upper():gsub("[^A-Z0-9]","")
    local h1,h2,h3 = bytehash(seed)
    local vds = ""
    for i=0,4 do vds = vds .. vin_char_from_num(((h1 >> (i*5)) % 33)) end
    local cd = "X"
    local yc = YEAR_CODES[y] or "S"
    local plant = vin_char_from_num((h2 % 33))
    local serial = ""
    for i=0,5 do serial = serial .. vin_char_from_num(((h3 >> (i*5)) % 33)) end
    local vin = wmi .. vds .. cd .. yc .. plant .. serial
    local real_cd = vin_check_digit(vin)
    vin = (vin:sub(1,8) .. real_cd .. vin:sub(10))
    return vin:gsub("[^A-Z0-9]", "")   -- absolutely no punctuation
end

-- ======================= Make/Model cleaning =======================
local function isBadMake(s)
    if not s or s == "" then return true end
    local up = tostring(s):upper()
    return up == "UNKNOWN" or up == "UNK" or up == "N/A" or up == "NULL" or up == "NONE"
end

-- strip leading year, remove agency suffixes, keep (Marked/Unmarked)
local function normalizeModelLabel(label)
    local s = tostring(label or "")
    s = s:gsub("^%s*([12]%d%d%d)[%s%-_]+", "")  -- remove leading year "2016 "
    local up = s:upper()
    local marked   = up:find("MARKED")   ~= nil
    local unmarked = up:find("UNMARKED") ~= nil

    local cleaned = up
        :gsub("%s+MORGAN%s+SO", "")
        :gsub("%s+SO$", "")
        :gsub("%s+PD$", "")
        :gsub("%s+POLICE$", "")
        :gsub("%s+SHERIFF$", "")
        :gsub("%s+HP$", "")
        :gsub("%s+STATE%s+PATROL$", "")
        :gsub("%s+HIGHWAY%s+PATROL$", "")
        :gsub("%s+MARKED", "")
        :gsub("%s+UNMARKED", "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")

    if marked   then cleaned = cleaned .. " (MARKED)" end
    if unmarked then cleaned = cleaned .. " (UNMARKED)" end

    local titled = cleaned:lower():gsub("(%a)([%w_']*)", function(a,b) return a:upper()..b end)
    return titled
end

local function guessMakeModel(displayLabel)
    local norm = normalizeModelLabel(displayLabel or "")
    local up   = norm:upper()
    if up:find("EXPLORER") then
        return "Ford", (up:find("MARKED") and "Explorer (Marked)") or (up:find("UNMARKED") and "Explorer (Unmarked)") or "Explorer"
    end
    if up:find("GRANGER")  then return "Declasse","Granger" end
    if up:find("STANIER")  then return "Vapid","Stanier" end
    if up:find("CHARGER")  then return "Dodge","Charger" end
    if up:find("DURANGO")  then return "Dodge","Durango" end
    if up:find("TAHOE")    then return "Chevrolet","Tahoe" end
    if up:find("IMPALA")   then return "Chevrolet","Impala" end
    if up:find("CROWN VIC") or up:find("CROWN VICTORIA") or up:find("CVPI") then
        return "Ford","Crown Victoria"
    end
    local first = norm:match("^(%S+)")
    if first then
        local rest = norm:sub(#first+2)
        if rest and #rest > 0 then return first, rest end
    end
    return "Declasse", (norm ~= "" and norm or "Granger")
end

local function cleanMakeModel(rawMake, rawModel)
    local make  = tostring(rawMake or "")
    local model = tostring(rawModel or "")
    if isBadMake(make) or tonumber(make) then
        return guessMakeModel(model)
    end
    if model == "" then
        return make, "Unknown"
    end
    local normModel = normalizeModelLabel(model)
    local gMake, gModel = guessMakeModel(normModel)
    if gMake and gModel then
        if gMake ~= make and (normModel:upper():find(gMake:upper()) or normModel:upper():find(gModel:upper())) then
            return gMake, gModel
        end
    end
    return make, normModel
end

-- ======================= Imperial lookup =======================
local function fetchSSNByCitizenId(charid, cb)
    local url = ("https://imperialcad.app/api/1.1/wf/GetCharacter?charid=%s&commId=%s"):format(charid, getCommunityId())
    PerformHttpRequest(url, function(status, resp, _)
        if status ~= 200 or not resp then return cb(nil) end
        local ok, j = pcall(json.decode, resp)
        if not ok or j.status ~= "success" or not (j.response and j.response.ssn) then return cb(nil) end
        cb(tostring(j.response.ssn))
    end, "GET", "", {["APIKEY"]=getAPIKey(), ["Content-Type"]="application/json"})
end

-- ======================= Export register (owner by numeric SSN) =======================
local function export_register_vehicle(ownerSSN, fields, cb)
    if GetResourceState("ImperialCAD") ~= "started" then
        return cb(false, { note = "ImperialCAD not started" })
    end

    local regDate = computeRegExpirationISO()  -- "YYYY-MM-DD" (string)

    local payload = {
        vehicleData = {
            plate      = fields.plateCAD,   -- keep single space for CAD UI
            model      = fields.model,
            Make       = fields.Make,
            color      = fields.color,
            year       = fields.year,
            vin        = fields.vin,        -- already A–Z/0–9 only
            regState   = "KY",
            regStatus  = "Valid",

            -- Expiration: cover ALL likely key names (all same ISO string)
            regExpDate             = regDate,
            expirationDate         = regDate,
            RegExpDate             = regDate,
            regExpiry              = regDate,
            registrationExp        = regDate,
            registrationExpiration = regDate,
            titleExpDate           = regDate,
            titleExpirationDate    = regDate,

            stolen     = false
        },

        -- Some templates look here for expiration
        vehicleRegistration = {
            expDate        = regDate,
            expirationDate = regDate
        },

        vehicleInsurance = {
            hasInsurance        = true,
            insuranceStatus     = "Active",
            insurancePolicyNum  = ("POL-%s"):format(fields.plateNoSpace)
        },

        vehicleOwner = { ownerSSN = tostring(ownerSSN) }
    }

    print("^3[imperialcad_bridge]^7 Using EXPORT CreateVehicleAdvanced: "..json.encode(payload))
    exports["ImperialCAD"]:CreateVehicleAdvanced(payload, function(success, res)
        if success then
            print("^2[imperialcad_bridge]^7 EXPORT success: "..(type(res)=="table" and json.encode(res) or tostring(res)))
            cb(true, res)
        else
            print("^1[imperialcad_bridge]^7 EXPORT failed: "..(type(res)=="table" and json.encode(res) or tostring(res)))
            cb(false, res)
        end
    end)
end

-- ======================= Main event =======================
RegisterNetEvent("imperialcad:registerVehicle", function(data)
    local src    = source
    local charid = getCitizenId(src)
    if not charid then
        print("^1[imperialcad_bridge]^7 No citizenid for src", src)
        return
    end

    -- Plate: keep ONE space for CAD; nospace for IDs
    local plateRaw     = tostring(data.plate or "")
    local plateTrim    = plateRaw:gsub("^%s+",""):gsub("%s+$","")
    local plateCAD     = plateTrim:gsub("%s+", " ")
    local plateNoSpace = plateCAD:gsub("%s+","")

    local yearNum  = tonumber(data.year) or 2015
    local colorStr = colorName(data.color or "0")
    local make, model = cleanMakeModel(data.make or "", data.model or "")
    local vin = generateVIN(model, yearNum, plateNoSpace, charid)

    local fields = {
        plateCAD     = plateCAD,
        plateNoSpace = plateNoSpace,
        model  = model,
        Make   = make,
        color  = colorStr,
        year   = yearNum,
        vin    = vin
    }

    fetchSSNByCitizenId(charid, function(numericSSN)
        if not numericSSN then
            print(("^1[imperialcad_bridge]^7 Could not resolve SSN for %s"):format(charid))
            return
        end
        export_register_vehicle(numericSSN, fields, function(ok, _)
            if ok then
                print(("[imperialcad_bridge] Registered (EXPORT ADV) %s -> SSN %s"):format(plateCAD, numericSSN))
            else
                print("^1[imperialcad_bridge]^7 Registration failed for plate "..plateCAD)
            end
        end)
    end)
end)

-- =====================================================================
-- ===================  /cadregister (existing plate)  ==================
-- =====================================================================

-- Simple chat helper
local function _sendChat(src, msg)
    TriggerClientEvent('chat:addMessage', src, { args = { '^3imperialcad', msg } })
end

-- Query player's vehicle by plate (matches with or without spaces)
local function dbGetOwnedVehicleByPlate(citizenid, plate_input, cb)
    local nospace = (tostring(plate_input or "")):gsub("%s+", "")
    local sql = [[
        SELECT *
          FROM player_vehicles
         WHERE citizenid = ?
           AND (
                UPPER(plate) = UPPER(?)
             OR  REPLACE(UPPER(plate),' ','') = UPPER(?)
           )
         LIMIT 1
    ]]
    exports.oxmysql:single(sql, { citizenid, plate_input, nospace }, function(row)
        cb(row)
    end)
end

-- Build fields from DB row + player context and push to CAD
local function registerExistingToCAD(src, row)
    local P = QBCore.Functions.GetPlayer(src)
    if not P then
        _sendChat(src, '^1Could not load your player data.')
        return
    end
    local charid  = P.PlayerData.citizenid

    -- Plate formatting
    local plateDB      = tostring(row.plate or "")
    local plateTrim    = plateDB:gsub("^%s+",""):gsub("%s+$","")
    local plateCAD     = plateTrim:gsub("%s+", " ")
    local plateNoSpace = plateCAD:gsub("%s+","")

    -- Pull what we can from DB; infer the rest
    local dbModelLabel = tostring(row.vehicle or "")
    local make, model  = cleanMakeModel(row.make or "", dbModelLabel)
    local yearNum      = tonumber(row.year) or 2015
    local colorIdx     = tonumber(row.color) or 0
    local colorStr     = colorName(colorIdx)
    local vin          = generateVIN(model, yearNum, plateNoSpace, charid)

    local fields = {
        plateCAD     = plateCAD,
        plateNoSpace = plateNoSpace,
        model  = model,
        Make   = make,
        color  = colorStr,
        year   = yearNum,
        vin    = vin
    }

    fetchSSNByCitizenId(charid, function(numericSSN)
        if not numericSSN then
            _sendChat(src, '^1Could not resolve your CAD SSN; is your character set up in ImperialCAD?')
            return
        end
        export_register_vehicle(numericSSN, fields, function(ok, _res)
            if ok then
                _sendChat(src, ('^2Registered plate ^7%s^2 to your CAD profile.'):format(plateCAD))
            else
                _sendChat(src, '^1Registration failed. Check server console for details.')
            end
        end)
    end)
end

-- /cadregister <plate>
RegisterCommand('cadregister', function(source, args)
    local src = source
    if src == 0 then
        print('[imperialcad_bridge] /cadregister cannot be used from console.')
        return
    end
    if not args[1] then
        _sendChat(src, '^1Usage:^7 /cadregister <plate>')
        return
    end

    local P = QBCore.Functions.GetPlayer(src)
    if not P then
        _sendChat(src, '^1Could not load your player.')
        return
    end
    local citizenid = P.PlayerData.citizenid
    local plateArg  = table.concat(args, ' ')  -- allow spaces in command

    dbGetOwnedVehicleByPlate(citizenid, plateArg, function(row)
        if not row then
            _sendChat(src, ('^1No vehicle with plate ^7%s ^1found on your account.'):format(plateArg))
            return
        end
        registerExistingToCAD(src, row)
    end)
end, false)  -- false = anyone can use; set to true if you want ACE

-- Optional: add a chat suggestion so players see usage
CreateThread(function()
    TriggerClientEvent('chat:addSuggestion', -1, '/cadregister', 'Register an existing owned vehicle in CAD by plate', {
        { name = 'plate', help = 'Example: 123 ABC or 123ABC' },
    })
end)

-- Optional ACE example (if you set the command to admin-only above):
-- add_ace resource.imperialcad_bridge command.cadregister allow
-- add_principal identifier.fivem:YOUR_IDENTIFIER group.admin
