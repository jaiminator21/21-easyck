-- Adaptadores por framework. Cada uno expone:
--   getCharId(src) -> ID del personaje cargado por el jugador (o nil)
--   getName(row)   -> nombre legible a partir de la fila de la tabla principal
--   hasGroup(src)  -> true si el jugador pertenece a alguno de Config.Permissions.Groups
--   idType         -> 'string' | 'number'

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

local Adapters = {}

Adapters.esx = function()
    local ESX = exports['es_extended']:getSharedObject()
    return {
        idType = 'string',
        getCharId = function(src)
            local xPlayer = ESX.GetPlayerFromId(src)
            return xPlayer and xPlayer.identifier
        end,
        getName = function(row)
            return fullName(row.firstname, row.lastname)
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

local function charinfoName(row)
    local ok, info = pcall(json.decode, row.charinfo or '{}')
    if ok and type(info) == 'table' then
        return fullName(info.firstname, info.lastname)
    end
    return '?'
end

Adapters.qbcore = function()
    local QBCore = exports['qb-core']:GetCoreObject()
    return {
        idType = 'string',
        getCharId = function(src)
            local player = QBCore.Functions.GetPlayer(src)
            return player and player.PlayerData.citizenid
        end,
        getName = charinfoName,
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
        getCharId = function(src)
            local player = exports.qbx_core:GetPlayer(src)
            return player and player.PlayerData.citizenid
        end,
        getName = charinfoName,
        hasGroup = aceGroup,
    }
end

Adapters.ox = function()
    return {
        idType = 'number',
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
        hasGroup = aceGroup,
    }
end

Adapters.custom = function()
    return {
        idType = Config.Custom.IdType or 'string',
        getCharId = Config.Custom.GetCharId,
        getName = Config.Custom.GetName,
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
