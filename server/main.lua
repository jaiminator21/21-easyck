local resourceName = GetCurrentResourceName()
local Bridge
local pending = {} -- [staffSrc] = { charId, name, reason, expires }
local busy = {}    -- [charId] = true mientras se ejecuta un CK

---------------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------------

local function notify(src, msg, kind)
    if src == 0 then
        print(('[easy-ck] %s'):format(msg))
    elseif Config.Notify then
        Config.Notify(src, msg, kind or 'inform')
    else
        TriggerClientEvent('chat:addMessage', src, {
            color = kind == 'error' and { 255, 80, 80 } or { 255, 170, 60 },
            multiline = true,
            args = { 'CK', msg },
        })
    end
end

local function hasPermission(src)
    if src == 0 then return true end
    if not Bridge then return false end
    if IsPlayerAceAllowed(src, Config.Permissions.Ace) then return true end
    return Bridge.hasGroup(src) == true
end

-- Los nombres de tabla/columna vienen de config.lua; se validan igualmente.
local function ident(name)
    assert(type(name) == 'string' and name:match('^[%w_]+$'), ('Identificador SQL no válido: %s'):format(tostring(name)))
    return '`' .. name .. '`'
end

local existsCache = {}
local function tableExists(name)
    if existsCache[name] == nil then
        local count = MySQL.scalar.await(
            'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?',
            { name }
        )
        existsCache[name] = (tonumber(count) or 0) > 0
    end
    return existsCache[name]
end

local function normalizeId(value)
    if Bridge.idType == 'number' then
        return tonumber(value)
    end
    return value and tostring(value)
end

local function findOnlineByCharId(charId)
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local ok, current = pcall(Bridge.getCharId, src)
        if ok and current ~= nil and tostring(current) == tostring(charId) then
            return src
        end
    end
end

local function fetchCharacter(charId)
    local main = Bridge.mainTable
    local query = ('SELECT * FROM %s WHERE %s = ?%s LIMIT 1'):format(
        ident(main.table), ident(main.column), main.filter and (' AND ' .. main.filter) or ''
    )
    return MySQL.single.await(query, { charId })
end

local function staffInfo(src)
    if src == 0 or not src then
        return L('console'), 'console'
    end
    return GetPlayerName(src) or ('ID ' .. src), GetPlayerIdentifierByType(src, 'license') or 'unknown'
end

-- Resuelve lo que escribe el staff:
--   "12"      -> jugador en línea con ID 12 (si no lo hay, se trata como ID de personaje)
--   "cid:XYZ" -> ID de personaje (citizenid / identifier / charId)
--   "XYZ"     -> ID de personaje
local function resolveTarget(input)
    local explicit = input:match('^cid:(.+)$') or input:match('^char:(.+)$')

    if not explicit then
        local serverId = tonumber(input)
        if serverId and GetPlayerName(serverId) then
            local charId = Bridge.getCharId(serverId)
            if not charId then
                return nil, L('player_no_char', serverId)
            end
            return charId
        end
    end

    local charId = normalizeId(explicit or input)
    if charId == nil then
        return nil, L('char_not_found', input)
    end
    return charId
end

local function sendWebhook(data, staffName, staffLicense, affected)
    if not Config.Webhook or Config.Webhook == '' then return end

    PerformHttpRequest(Config.Webhook, function() end, 'POST', json.encode({
        username = Config.WebhookName,
        embeds = { {
            title = 'Character Kill',
            color = Config.WebhookColor,
            fields = {
                { name = 'Personaje', value = ('%s (`%s`)'):format(data.name, data.charId), inline = true },
                { name = 'Framework', value = Bridge.name, inline = true },
                { name = 'Staff', value = ('%s\n`%s`'):format(staffName, staffLicense), inline = false },
                { name = 'Motivo', value = data.reason ~= '' and data.reason or L('no_reason'), inline = false },
                { name = 'Filas afectadas', value = tostring(affected), inline = true },
            },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

---------------------------------------------------------------------------
-- CK
---------------------------------------------------------------------------

-- Ejecuta el CK. Debe llamarse dentro de un hilo (usa Wait y consultas await).
local function executeCK(data, staffSrc)
    local key = tostring(data.charId)
    if busy[key] then
        return false, L('busy')
    end
    busy[key] = true

    local ok, result = pcall(function()
        -- 1. Expulsar al jugador si está conectado y esperar a que el framework guarde,
        --    para que ese guardado no vuelva a crear el personaje después de borrarlo.
        local targetSrc = findOnlineByCharId(data.charId)
        if targetSrc then
            DropPlayer(tostring(targetSrc), L('kick_message', data.reason ~= '' and data.reason or L('no_reason')))
            Wait(Config.SaveDelay)
        end

        -- 2. Tablas secundarias primero y la principal al final (por claves foráneas).
        local ordered = {}
        for _, t in ipairs(Bridge.tables) do
            if not t.main and tableExists(t.table) then
                ordered[#ordered + 1] = t
            end
        end
        ordered[#ordered + 1] = Bridge.mainTable

        -- 3. Copia de seguridad de todo lo que se va a tocar.
        local backup = {}
        if Config.Backup then
            for _, t in ipairs(ordered) do
                local okSelect, rows = pcall(MySQL.query.await,
                    ('SELECT * FROM %s WHERE %s = ?'):format(ident(t.table), ident(t.column)), { data.charId })
                if okSelect and rows and #rows > 0 then
                    backup[t.table] = rows
                elseif not okSelect then
                    print(('[easy-ck] ^3No se pudo copiar %s: %s^0'):format(t.table, tostring(rows)))
                end
            end
        end

        -- 4. Borrado.
        local affected, mainAffected = 0, 0
        for _, t in ipairs(ordered) do
            local query
            if t.update then
                query = ('UPDATE %s SET %s WHERE %s = ?'):format(ident(t.table), t.update, ident(t.column))
            else
                query = ('DELETE FROM %s WHERE %s = ?'):format(ident(t.table), ident(t.column))
            end

            local okQuery, count = pcall(MySQL.update.await, query, { data.charId })
            if okQuery then
                affected = affected + (tonumber(count) or 0)
                if t == Bridge.mainTable then mainAffected = tonumber(count) or 0 end
            else
                print(('[easy-ck] ^3Error en %s: %s^0'):format(t.table, tostring(count)))
            end
        end

        if mainAffected == 0 then
            error(('no se ha modificado la tabla principal (%s)'):format(Bridge.mainTable.table))
        end

        -- 5. Registro.
        local staffName, staffLicense = staffInfo(staffSrc)
        MySQL.insert.await(
            'INSERT INTO easy_ck_log (char_id, char_name, framework, reason, staff_name, staff_license, backup) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { key, data.name, Bridge.name, data.reason, staffName, staffLicense, Config.Backup and json.encode(backup) or nil }
        )
        sendWebhook(data, staffName, staffLicense, affected)

        TriggerEvent('easy-ck:characterKilled', {
            charId = data.charId,
            name = data.name,
            reason = data.reason,
            framework = Bridge.name,
            staff = staffSrc,
        })

        return affected
    end)

    busy[key] = nil
    return ok, result
end

local function prepare(src, args)
    local input = args[1]
    if not input then
        return notify(src, L('usage', Config.Command), 'error')
    end

    local reason = table.concat(args, ' ', 2)
    if Config.RequireReason and reason == '' then
        return notify(src, L('reason_required'), 'error')
    end

    local charId, err = resolveTarget(input)
    if not charId then
        return notify(src, err, 'error')
    end

    local row = fetchCharacter(charId)
    if not row then
        return notify(src, L('char_not_found', tostring(charId)), 'error')
    end

    local name = Bridge.getName(row)
    local onlineSrc = findOnlineByCharId(charId)

    pending[src] = {
        charId = charId,
        name = name,
        reason = reason,
        expires = os.time() + Config.ConfirmTimeout,
    }

    notify(src, L('confirm',
        name, tostring(charId),
        onlineSrc and L('online', onlineSrc) or L('offline'),
        Config.ConfirmCommand, Config.ConfirmTimeout, Config.CancelCommand
    ))
end

local function confirm(src)
    local data = pending[src]
    pending[src] = nil

    if not data then
        return notify(src, L('nothing_pending'), 'error')
    end
    if os.time() > data.expires then
        return notify(src, L('expired'), 'error')
    end

    notify(src, L('in_progress', data.name))
    local ok, result = executeCK(data, src)
    if ok then
        notify(src, L('done', data.name, tostring(data.charId), result), 'success')
    else
        notify(src, L('failed', tostring(result)), 'error')
    end
end

---------------------------------------------------------------------------
-- Comandos
---------------------------------------------------------------------------

RegisterCommand(Config.Command, function(src, args)
    if not Bridge then
        return notify(src, 'easy-ck todavía no está listo.', 'error')
    end
    if not hasPermission(src) then
        return notify(src, L('no_permission'), 'error')
    end
    CreateThread(function() prepare(src, args) end)
end, false)

RegisterCommand(Config.ConfirmCommand, function(src)
    if not hasPermission(src) then
        return notify(src, L('no_permission'), 'error')
    end
    CreateThread(function() confirm(src) end)
end, false)

RegisterCommand(Config.CancelCommand, function(src)
    if pending[src] then
        pending[src] = nil
        notify(src, L('cancelled'))
    else
        notify(src, L('nothing_pending'), 'error')
    end
end, false)

AddEventHandler('playerDropped', function()
    pending[source] = nil
end)

---------------------------------------------------------------------------
-- Export para otros recursos (sin confirmación):
--   local ok, result = exports['easy-ck']:CharacterKill('ABC12345', 'Motivo')
---------------------------------------------------------------------------

exports('CharacterKill', function(input, reason)
    if not Bridge then return false, 'not ready' end
    local charId, err = resolveTarget(tostring(input))
    if not charId then return false, err end

    local row = fetchCharacter(charId)
    if not row then return false, L('char_not_found', tostring(charId)) end

    return executeCK({
        charId = charId,
        name = Bridge.getName(row),
        reason = reason or '',
    }, nil)
end)

---------------------------------------------------------------------------
-- Arranque
---------------------------------------------------------------------------

MySQL.ready(function()
    Bridge = LoadBridge()

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `easy_ck_log` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `char_id` VARCHAR(100) NOT NULL,
            `char_name` VARCHAR(100) NULL,
            `framework` VARCHAR(20) NULL,
            `reason` TEXT NULL,
            `staff_name` VARCHAR(100) NULL,
            `staff_license` VARCHAR(100) NULL,
            `backup` LONGTEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX (`char_id`)
        )
    ]])

    print(('[%s] ^2Listo^0 - framework: ^5%s^0, comando: /%s'):format(resourceName, Bridge.name, Config.Command))
end)
