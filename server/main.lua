local resourceName = GetCurrentResourceName()
local Bridge
local pending = {}     -- [staffSrc] = { charId, name, reason, expires } (flujo por chat)
local uiPending = {}   -- [staffSrc] = { charId, name, expires } (flujo por interfaz)
local lastRequest = {} -- [staffSrc] = último GetGameTimer(), anti-spam de la interfaz
local busy = {}        -- [charId] = true mientras se ejecuta un CK

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

local columnsCache = {}
local function columnsOf(name)
    if not columnsCache[name] then
        local rows = MySQL.query.await(
            'SELECT column_name AS c FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ?',
            { name }
        ) or {}
        local set = {}
        for _, row in ipairs(rows) do
            set[row.c or row.column_name] = true
        end
        columnsCache[name] = set
    end
    return columnsCache[name]
end

local function previewConfig(name)
    return (Config.Preview and Config.Preview.Tables or {})[name] or {}
end

-- Una tabla se borra por defecto salvo que en Config.Preview.Tables tenga default = false.
local function selectedByDefault(name)
    return previewConfig(name).default ~= false
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

local function sendWebhook(data, staffName, staffLicense, affected, kept)
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
                kept and { name = 'Tablas conservadas', value = kept, inline = false } or nil,
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
        --    Solo las seleccionadas: data.tables es un conjunto { ['player_vehicles'] = true, ... }.
        --    Sin selección se usan los valores por defecto de Config.Preview.
        local selection = data.tables
        local ordered, kept = {}, {}
        for _, t in ipairs(Bridge.tables) do
            if not t.main and tableExists(t.table) then
                local wanted = selection and selection[t.table] == true or (not selection and selectedByDefault(t.table))
                if wanted then
                    ordered[#ordered + 1] = t
                else
                    kept[#kept + 1] = t.table
                end
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
        local keptList = #kept > 0 and table.concat(kept, ', ') or nil
        MySQL.insert.await(
            'INSERT INTO easy_ck_log (char_id, char_name, framework, reason, staff_name, staff_license, kept_tables, backup) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { key, data.name, Bridge.name, data.reason, staffName, staffLicense, keptList, Config.Backup and json.encode(backup) or nil }
        )
        sendWebhook(data, staffName, staffLicense, affected, keptList)

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
    uiPending[source] = nil
    lastRequest[source] = nil
end)

---------------------------------------------------------------------------
-- Interfaz (NUI)
---------------------------------------------------------------------------

-- Anti-spam por jugador y por tipo de petición: dos clics seguidos en el mismo
-- botón no repiten la consulta, pero pedir otra cosa distinta nunca se bloquea.
local function uiAllowed(src, kind)
    if not Bridge then
        notify(src, L('ui_not_ready'), 'error')
        return false
    end
    if not hasPermission(src) then
        notify(src, L('no_permission'), 'error')
        return false
    end

    local now = GetGameTimer()
    local history = lastRequest[src]
    if not history then
        history = {}
        lastRequest[src] = history
    end
    if history[kind] and now - history[kind] < 150 then
        return false
    end
    history[kind] = now
    return true
end

local function onlinePlayers()
    local list = {}
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local okId, charId = pcall(Bridge.getCharId, src)
        local info
        if Bridge.getOnlineInfo then
            local okInfo, res = pcall(Bridge.getOnlineInfo, src)
            info = okInfo and res or nil
        end
        list[#list + 1] = {
            id = src,
            steam = GetPlayerName(src),
            charId = okId and charId ~= nil and tostring(charId) or nil,
            name = info and info.name or nil,
            job = info and info.job or nil,
            ping = GetPlayerPing(src),
            online = src,
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- Pestaña "Todos": busca en la tabla principal, así salen también los personajes
-- de jugadores desconectados.
local function listCharacters(search, offset, limit)
    local main = Bridge.mainTable
    local cols = columnsOf(main.table)
    local where, params = {}, {}

    if main.filter then
        where[#where + 1] = '(' .. main.filter .. ')'
    end

    search = type(search) == 'string' and search:sub(1, 60) or ''
    if search ~= '' then
        local ors = {}
        local searchable = (Bridge.list and Bridge.list.search) or { main.column }
        for _, col in ipairs(searchable) do
            if cols[col] then
                ors[#ors + 1] = ident(col) .. ' LIKE ?'
                params[#params + 1] = '%' .. search .. '%'
            end
        end
        if #ors > 0 then
            where[#where + 1] = '(' .. table.concat(ors, ' OR ') .. ')'
        end
    end

    local order = Bridge.list and Bridge.list.order
    if not (order and cols[order]) then order = main.column end

    limit = math.min(math.max(tonumber(limit) or 30, 1), 100)
    offset = math.min(math.max(tonumber(offset) or 0, 0), 100000)

    local query = ('SELECT * FROM %s%s ORDER BY %s DESC LIMIT %d OFFSET %d'):format(
        ident(main.table),
        #where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or '',
        ident(order), limit, offset
    )

    local ok, rows = pcall(MySQL.query.await, query, params)
    if not ok then
        print(('[easy-ck] ^3Error listando personajes: %s^0'):format(tostring(rows)))
        return {}, false
    end

    -- Marca cuáles están conectados ahora mismo.
    local onlineByChar = {}
    for _, player in ipairs(onlinePlayers()) do
        if player.charId then onlineByChar[player.charId] = player.id end
    end

    local list = {}
    for _, row in ipairs(rows or {}) do
        local charId = row[main.column]
        local okName, name = pcall(Bridge.getName, row)
        list[#list + 1] = {
            charId = tostring(charId),
            name = okName and name or tostring(charId),
            sub = Bridge.list and Bridge.list.order and row[Bridge.list.order] and tostring(row[Bridge.list.order]):sub(1, 19) or nil,
            online = onlineByChar[tostring(charId)],
        }
    end

    return list, #rows == limit
end

local function cell(value)
    if value == nil then return '' end
    if type(value) == 'table' then value = json.encode(value) end
    value = tostring(value)
    if #value > 140 then value = value:sub(1, 140) .. '…' end
    return value
end

-- Todo lo que se va a borrar del personaje, tabla por tabla.
local function buildPreview(charId)
    local row = fetchCharacter(charId)
    if not row then
        return nil, L('char_not_found', tostring(charId))
    end

    local maxRows = (Config.Preview and Config.Preview.MaxRows) or 25
    local okSummary, summary = true, {}
    if Bridge.getSummary then
        okSummary, summary = pcall(Bridge.getSummary, row)
    end

    local preview = {
        charId = tostring(charId),
        name = Bridge.getName(row),
        online = findOnlineByCharId(charId),
        framework = Bridge.name,
        summary = okSummary and summary or {},
        tables = {},
    }

    for _, t in ipairs(Bridge.tables) do
        if tableExists(t.table) then
            local cfg = previewConfig(t.table)
            local tableCols = columnsOf(t.table)
            local where = ident(t.column) .. ' = ?'
            if t.main and t.filter then
                where = where .. ' AND (' .. t.filter .. ')'
            end

            local okCount, count = pcall(MySQL.scalar.await,
                ('SELECT COUNT(*) FROM %s WHERE %s'):format(ident(t.table), where), { charId })
            count = okCount and (tonumber(count) or 0) or 0

            local columns = {}
            for _, col in ipairs(cfg.columns or {}) do
                if tableCols[col] then columns[#columns + 1] = col end
            end

            local rows = {}
            if count > 0 and #columns > 0 then
                local select = {}
                for _, col in ipairs(columns) do select[#select + 1] = ident(col) end
                local okRows, result = pcall(MySQL.query.await,
                    ('SELECT %s FROM %s WHERE %s LIMIT %d'):format(
                        table.concat(select, ', '), ident(t.table), where, maxRows), { charId })
                if okRows then
                    for _, r in ipairs(result or {}) do
                        local cells = {}
                        for i, col in ipairs(columns) do cells[i] = cell(r[col]) end
                        rows[#rows + 1] = cells
                    end
                end
            end

            preview.tables[#preview.tables + 1] = {
                table = t.table,
                label = cfg.label or t.table,
                count = count,
                columns = columns,
                rows = rows,
                mode = t.update and 'update' or 'delete',
                locked = t.main == true,             -- la tabla principal siempre se borra
                selected = t.main == true or selectedByDefault(t.table),
            }
        end
    end

    return preview
end

-- Nunca se hace caso a la lista de tablas del cliente sin validarla contra la config.
local function sanitizeSelection(list)
    local allowed = {}
    for _, t in ipairs(Bridge.tables) do allowed[t.table] = true end

    local selection = {}
    if type(list) == 'table' then
        for _, name in ipairs(list) do
            if type(name) == 'string' and allowed[name] then selection[name] = true end
        end
    end
    selection[Bridge.mainTable.table] = true
    return selection
end

RegisterNetEvent('easy-ck:ui:request', function()
    local src = source
    if Config.Debug then
        print(('[easy-ck] %s (%s) pide la interfaz: bridge=%s permiso=%s'):format(
            GetPlayerName(src) or '?', src, tostring(Bridge ~= nil), tostring(hasPermission(src))))
    end
    if not uiAllowed(src, 'open') then return end
    TriggerClientEvent('easy-ck:ui:open', src, {
        locale = LUI(),
        framework = Bridge.name,
        requireReason = Config.RequireReason and true or false,
        players = onlinePlayers(),
    })
end)

RegisterNetEvent('easy-ck:ui:players', function()
    local src = source
    if not uiAllowed(src, 'players') then return end
    TriggerClientEvent('easy-ck:ui:players', src, onlinePlayers())
end)

RegisterNetEvent('easy-ck:ui:list', function(search, offset)
    local src = source
    if not uiAllowed(src, 'list') then return end
    CreateThread(function()
        local list, more = listCharacters(search, offset, 30)
        TriggerClientEvent('easy-ck:ui:list', src, {
            characters = list,
            offset = math.max(tonumber(offset) or 0, 0),
            more = more,
            search = type(search) == 'string' and search or '',
        })
    end)
end)

RegisterNetEvent('easy-ck:ui:preview', function(target)
    local src = source
    if not uiAllowed(src, 'preview') then return end
    if type(target) ~= 'string' or target == '' or #target > 80 then return end

    CreateThread(function()
        local charId, err = resolveTarget(target)
        if not charId then
            return TriggerClientEvent('easy-ck:ui:preview', src, { error = err })
        end

        local preview, previewErr = buildPreview(charId)
        if not preview then
            return TriggerClientEvent('easy-ck:ui:preview', src, { error = previewErr })
        end

        -- Testigo de confirmación: solo se puede ejecutar el CK del personaje que se acaba de ver.
        uiPending[src] = {
            charId = charId,
            name = preview.name,
            expires = os.time() + 600,
        }
        TriggerClientEvent('easy-ck:ui:preview', src, preview)
    end)
end)

RegisterNetEvent('easy-ck:ui:execute', function(charId, reason, tables)
    local src = source
    if not uiAllowed(src, 'execute') then return end

    local data = uiPending[src]
    uiPending[src] = nil

    local function fail(msg)
        notify(src, msg, 'error')
        TriggerClientEvent('easy-ck:ui:result', src, { ok = false, message = msg })
    end

    if not data or tostring(data.charId) ~= tostring(charId) then
        return fail(L('nothing_pending'))
    end
    if os.time() > data.expires then
        return fail(L('expired'))
    end

    reason = type(reason) == 'string' and reason:sub(1, 300) or ''
    if Config.RequireReason and reason:gsub('%s', '') == '' then
        return fail(L('reason_required'))
    end

    local selection = sanitizeSelection(tables)

    CreateThread(function()
        notify(src, L('in_progress', data.name))
        local ok, result = executeCK({
            charId = data.charId,
            name = data.name,
            reason = reason,
            tables = selection,
        }, src)

        if ok then
            notify(src, L('done', data.name, tostring(data.charId), result), 'success')
            TriggerClientEvent('easy-ck:ui:result', src, {
                ok = true,
                message = L('done', data.name, tostring(data.charId), result),
            })
        else
            fail(L('failed', tostring(result)))
        end
    end)
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
            `kept_tables` TEXT NULL,
            `backup` LONGTEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX (`char_id`)
        )
    ]])

    -- La columna se añadió en la versión 1.1; se crea en instalaciones antiguas.
    if not columnsOf('easy_ck_log').kept_tables then
        pcall(MySQL.query.await, 'ALTER TABLE `easy_ck_log` ADD COLUMN `kept_tables` TEXT NULL')
        columnsCache['easy_ck_log'] = nil
    end

    print(('[%s] ^2Listo^0 - framework: ^5%s^0, comandos: /%s /%s'):format(
        resourceName, Bridge.name, Config.Command, Config.MenuCommand))
end)
