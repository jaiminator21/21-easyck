-- Adaptadores por framework. Cada uno expone:
--   getCharId(src)     -> ID del personaje cargado por el jugador (o nil)
--   getName(row)       -> nombre legible a partir de la fila de la tabla principal
--   getOnlineInfo(src) -> { name, job } del jugador conectado, sin tocar la base de datos (opcional)
--   getSummary(row)    -> lista de { label, value } que se muestra en la ficha de la interfaz
--   hasGroup(src)      -> true si el jugador pertenece a alguno de Config.Permissions.Groups
--   list               -> { search = { columnas donde buscar }, order = 'columna' } para la pestaña "Todos"
--   idType             -> 'string' | 'number'

local function aceGroup(src)
    for _, group in ipairs(Config.Permissions.Groups) do
        if IsPlayerAceAllowed(src, 'group.' .. group) then
            return true
        end
    end
    return false
end

local function fullName(first, last)
    return (('%s %s'):format(first or '?', last or ''):gsub('%s+$', ''))
end

local function decode(value)
    if type(value) == 'table' then return value end
    local ok, res = pcall(json.decode, value or '')
    if ok and type(res) == 'table' then return res end
    return {}
end

local function money(amount)
    local n = tonumber(amount)
    if not n then return nil end
    local formatted = ('%d'):format(math.floor(n))
    local sign = formatted:sub(1, 1) == '-' and '-' or ''
    formatted = formatted:gsub('^%-', '')
    while true do
        local replaced
        formatted, replaced = formatted:gsub('^(%d+)(%d%d%d)', '%1.%2')
        if replaced == 0 then break end
    end
    return ('%s$%s'):format(sign, formatted)
end

-- Añade el campo solo si tiene valor, para que la ficha no se llene de huecos.
-- `key` es la clave del texto en locales.lua (ui.f_*), la interfaz la traduce.
local function field(list, key, value)
    if value == nil or value == '' then return end
    list[#list + 1] = { key = key, value = tostring(value) }
end

local Adapters = {}

---------------------------------------------------------------------------
-- ESX
---------------------------------------------------------------------------

Adapters.esx = function()
    local ESX = exports['es_extended']:getSharedObject()
    return {
        idType = 'string',
        list = { search = { 'identifier', 'firstname', 'lastname' }, order = 'identifier' },
        getCharId = function(src)
            local xPlayer = ESX.GetPlayerFromId(src)
            return xPlayer and xPlayer.identifier
        end,
        getName = function(row)
            return fullName(row.firstname, row.lastname)
        end,
        getOnlineInfo = function(src)
            local xPlayer = ESX.GetPlayerFromId(src)
            if not xPlayer then return end
            return {
                name = xPlayer.getName and xPlayer.getName() or nil,
                job = xPlayer.job and xPlayer.job.label or nil,
            }
        end,
        getSummary = function(row)
            local accounts = decode(row.accounts)
            local out = {}
            field(out, 'f_name', fullName(row.firstname, row.lastname))
            field(out, 'f_birth', row.dateofbirth)
            field(out, 'f_phone', row.phone_number)
            field(out, 'f_job', row.job and ('%s (%s)'):format(row.job, row.job_grade or 0))
            field(out, 'f_group', row.group)
            field(out, 'f_cash', money(accounts.money))
            field(out, 'f_bank', money(accounts.bank))
            field(out, 'f_black', money(accounts.black_money))
            return out
        end,
        hasGroup = function(src)
            local xPlayer = ESX.GetPlayerFromId(src)
            if xPlayer then
                local current = xPlayer.getGroup()
                for _, group in ipairs(Config.Permissions.Groups) do
                    if current == group then return true end
                end
            end
            return aceGroup(src)
        end,
    }
end

---------------------------------------------------------------------------
-- QBCore / Qbox (mismo esquema de base de datos)
---------------------------------------------------------------------------

local function charinfoName(row)
    local info = decode(row.charinfo)
    return fullName(info.firstname, info.lastname)
end

local function qbSummary(row)
    local info, cash, job, gang = decode(row.charinfo), decode(row.money), decode(row.job), decode(row.gang)
    local out = {}
    field(out, 'f_name', fullName(info.firstname, info.lastname))
    field(out, 'f_birth', info.birthdate)
    field(out, 'f_phone', info.phone)
    if job.label then
        field(out, 'f_job', ('%s - %s'):format(job.label, job.grade and (job.grade.name or job.grade.level) or '?'))
    end
    if gang.label and gang.name ~= 'none' then
        field(out, 'f_gang', gang.label)
    end
    field(out, 'f_cash', money(cash.cash))
    field(out, 'f_bank', money(cash.bank))
    field(out, 'f_crypto', cash.crypto)
    field(out, 'f_last_seen', row.last_updated)
    return out
end

local qbList = { search = { 'citizenid', 'name', 'charinfo' }, order = 'last_updated' }

Adapters.qbcore = function()
    local QBCore = exports['qb-core']:GetCoreObject()
    return {
        idType = 'string',
        list = qbList,
        getCharId = function(src)
            local player = QBCore.Functions.GetPlayer(src)
            return player and player.PlayerData.citizenid
        end,
        getName = charinfoName,
        getSummary = qbSummary,
        getOnlineInfo = function(src)
            local player = QBCore.Functions.GetPlayer(src)
            if not player then return end
            local data = player.PlayerData
            return {
                name = fullName(data.charinfo and data.charinfo.firstname, data.charinfo and data.charinfo.lastname),
                job = data.job and data.job.label or nil,
            }
        end,
        hasGroup = function(src)
            for _, group in ipairs(Config.Permissions.Groups) do
                if QBCore.Functions.HasPermission(src, group) then return true end
            end
            return aceGroup(src)
        end,
    }
end

Adapters.qbox = function()
    return {
        idType = 'string',
        list = qbList,
        getCharId = function(src)
            local player = exports.qbx_core:GetPlayer(src)
            return player and player.PlayerData.citizenid
        end,
        getName = charinfoName,
        getSummary = qbSummary,
        getOnlineInfo = function(src)
            local player = exports.qbx_core:GetPlayer(src)
            if not player then return end
            local data = player.PlayerData
            return {
                name = fullName(data.charinfo and data.charinfo.firstname, data.charinfo and data.charinfo.lastname),
                job = data.job and data.job.label or nil,
            }
        end,
        hasGroup = aceGroup,
    }
end

---------------------------------------------------------------------------
-- ox_core
---------------------------------------------------------------------------

Adapters.ox = function()
    return {
        idType = 'number',
        list = { search = { 'charId', 'firstName', 'lastName', 'stateId' }, order = 'lastPlayed' },
        getCharId = function(src)
            local ok, player = pcall(function() return exports.ox_core:GetPlayer(src) end)
            if ok and player and player.charId then
                return player.charId
            end
            return Player(src).state.charId
        end,
        getName = function(row)
            return fullName(row.firstName, row.lastName)
        end,
        getSummary = function(row)
            local out = {}
            field(out, 'f_name', fullName(row.firstName, row.lastName))
            field(out, 'f_state_id', row.stateId)
            field(out, 'f_birth', row.dateOfBirth)
            field(out, 'f_gender', row.gender)
            field(out, 'f_phone', row.phoneNumber)
            field(out, 'f_last_seen', row.lastPlayed)
            return out
        end,
        hasGroup = aceGroup,
    }
end

---------------------------------------------------------------------------
-- Personalizado
---------------------------------------------------------------------------

Adapters.custom = function()
    return {
        idType = Config.Custom.IdType or 'string',
        list = Config.Custom.List,
        getCharId = Config.Custom.GetCharId,
        getName = Config.Custom.GetName,
        getSummary = function(row)
            local out = {}
            field(out, 'f_name', Config.Custom.GetName(row))
            return out
        end,
        hasGroup = aceGroup,
    }
end

local detectionOrder = {
    { resource = 'qbx_core',    framework = 'qbox' },
    { resource = 'es_extended', framework = 'esx' },
    { resource = 'qb-core',     framework = 'qbcore' },
    { resource = 'ox_core',     framework = 'ox' },
}

local function detect()
    for _, entry in ipairs(detectionOrder) do
        local state = GetResourceState(entry.resource)
        if state == 'started' or state == 'starting' then
            return entry.framework
        end
    end
end

function LoadBridge()
    local framework = Config.Framework
    if framework == 'auto' then
        framework = detect()
        if not framework then
            error('[easy-ck] No se ha detectado ningún framework. Define Config.Framework (usa "custom" si tienes uno propio).')
        end
    end

    local factory = Adapters[framework]
    if not factory then
        error(('[easy-ck] Framework no soportado: %s'):format(tostring(framework)))
    end

    local bridge = factory()
    bridge.name = framework
    bridge.tables = Config.Tables[framework] or {}

    for _, t in ipairs(bridge.tables) do
        if t.main then bridge.mainTable = t end
    end
    if not bridge.mainTable then
        error(('[easy-ck] Config.Tables.%s necesita una tabla con main = true'):format(framework))
    end

    return bridge
end
