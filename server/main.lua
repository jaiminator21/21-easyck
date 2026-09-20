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
        print(('[21-easyck] %s'):format(msg))
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
    if GuardOk ~= true then return false end
    if src == 0 then return true end
    if not Bridge then return false end
    if IsPlayerAceAllowed(src, Config.Permissions.Ace) then return true end
    return Bridge.hasGroup(src) == true
end

-- Nombres de tabla y de columna entre acentos graves. MySQL admite ahí casi
-- cualquier cosa (guiones, espacios, puntos), así que los recursos que se llaman
-- `21-robberies_evidence` valen; lo que no se acepta es un acento grave ni
-- caracteres de control, que es lo único con lo que se podría escapar de las comillas.
local function quotable(name)
    return type(name) == 'string'
        and name ~= ''
        and #name <= 64
        and not name:find('[%c`]') -- %c = caracteres de control
end

local function ident(name)
    assert(quotable(name), ('Identificador SQL no válido: %s'):format(tostring(name)))
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

-- Columnas de una tabla: nombre, tipo y si forma parte de la clave primaria.
-- Se consulta una sola vez por tabla.
local columnsCache = {}
local function tableColumns(name)
    if not columnsCache[name] then
        local rows = MySQL.query.await(
            [[SELECT column_name AS c, data_type AS t, column_key AS k
              FROM information_schema.columns
              WHERE table_schema = DATABASE() AND table_name = ?
              ORDER BY ordinal_position]],
            { name }
        ) or {}

        local set, list, keys = {}, {}, {}
        for _, row in ipairs(rows) do
            local column = row.c or row.column_name
            local kind = tostring(row.t or row.data_type or ''):lower()
            set[column] = true
            list[#list + 1] = { name = column, kind = kind }
            if tostring(row.k or row.column_key or ''):upper() == 'PRI' then
                keys[#keys + 1] = column
            end
        end

        columnsCache[name] = { set = set, list = list, keys = keys }
    end
    return columnsCache[name]
end

local function columnsOf(name)
    return tableColumns(name).set
end

-- Solo se pueden borrar filas sueltas si la tabla tiene una clave primaria de una
-- sola columna; con claves compuestas o sin clave, la tabla va entera o no va.
local function primaryKeyOf(name)
    local keys = tableColumns(name).keys
    return #keys == 1 and keys[1] or nil
end

-- Columnas que se enseñan en el detalle de una tabla detectada automáticamente:
-- las primeras que no sean un campo enorme.
local SKIP_TYPES = { blob = true, longblob = true, mediumblob = true, tinyblob = true,
                     json = true, longtext = true, mediumtext = true }

local function autoColumns(name, links)
    local isLink = {}
    for _, column in ipairs(links or {}) do isLink[column] = true end

    local picked = {}
    for _, column in ipairs(tableColumns(name).list) do
        if not isLink[column.name] and not SKIP_TYPES[column.kind] then
            picked[#picked + 1] = column.name
            if #picked == 4 then break end
        end
    end
    return picked
end

local function previewConfig(name)
    return (Config.Preview and Config.Preview.Tables or {})[name] or {}
end

-- Una tabla se borra por defecto salvo que en Config.Preview.Tables tenga default = false.
local function selectedByDefault(name)
    return previewConfig(name).default ~= false
end

-- Valor tal y como se enseña en la interfaz.
local function cell(value)
    if value == nil then return '' end
    if type(value) == 'table' then value = json.encode(value) end
    value = tostring(value)
    if #value > 140 then value = value:sub(1, 140) .. '…' end
    return value
end

---------------------------------------------------------------------------
-- Escaneo de la base de datos
---------------------------------------------------------------------------

-- Busca en TODA la base de datos cualquier columna que pueda contener el ID del
-- personaje: por patrón en el nombre (citizenid, owner_citizenid, target_cid...)
-- y por nombres exactos. Una tabla puede tener varias (emisor y receptor, por
-- ejemplo) y se quedan todas. Se consulta una sola vez por arranque.
local discoveryCache
local function discoverTables()
    if not (Config.Discovery and Config.Discovery.Enabled) then return {} end
    if discoveryCache then return discoveryCache end
    discoveryCache = {}

    local conditions, params = {}, {}

    -- El nombre de la columna principal del framework siempre cuenta.
    local patterns, seen = {}, {}
    local function addPattern(value)
        value = tostring(value or ''):lower()
        if value ~= '' and not seen[value] then
            seen[value] = true
            patterns[#patterns + 1] = value
        end
    end
    addPattern(Bridge.mainTable.column)
    for _, pattern in ipairs(Config.Discovery.Patterns or {}) do addPattern(pattern) end

    for _, pattern in ipairs(patterns) do
        conditions[#conditions + 1] = 'LOWER(col.column_name) LIKE ?'
        params[#params + 1] = '%' .. pattern .. '%'
    end

    local exact = {}
    for _, column in ipairs(Config.Discovery.Columns or {}) do
        local lower = tostring(column):lower()
        if lower ~= '' then exact[#exact + 1] = lower end
    end
    if #exact > 0 then
        conditions[#conditions + 1] = ('LOWER(col.column_name) IN (%s)'):format(string.rep('?', #exact, ', '))
        for _, column in ipairs(exact) do params[#params + 1] = column end
    end

    if #conditions == 0 then return discoveryCache end

    local ignore = {}
    for _, name in ipairs(Config.Discovery.Ignore or {}) do
        ignore[tostring(name):lower()] = true
    end
    for _, t in ipairs(Bridge.tables) do
        ignore[t.table:lower()] = true -- ya está en Config.Tables, con su etiqueta y su orden
    end

    local ok, rows = pcall(MySQL.query.await, ([[
        SELECT col.table_name AS t, col.column_name AS c
        FROM information_schema.columns col
        JOIN information_schema.tables tbl
          ON tbl.table_schema = col.table_schema AND tbl.table_name = col.table_name
        WHERE col.table_schema = DATABASE()
          AND tbl.table_type = 'BASE TABLE'
          AND (%s)
        ORDER BY col.table_name, col.ordinal_position
    ]]):format(table.concat(conditions, ' OR ')), params)

    if not ok then
        print(('[21-easyck] ^3No se ha podido escanear la base de datos: %s^0'):format(tostring(rows)))
        return discoveryCache
    end

    local byTable, order = {}, {}
    for _, row in ipairs(rows or {}) do
        local name = tostring(row.t or row.table_name or '')
        local column = tostring(row.c or row.column_name or '')
        if quotable(name) and quotable(column) and not ignore[name:lower()] then
            if not byTable[name] then
                byTable[name] = { table = name, column = column, columns = {}, discovered = true }
                order[#order + 1] = name
            end
            local columns = byTable[name].columns
            columns[#columns + 1] = column
        end
    end

    table.sort(order)
    for _, name in ipairs(order) do
        discoveryCache[#discoveryCache + 1] = byTable[name]
    end

    if Config.Debug then
        local names = {}
        for _, entry in ipairs(discoveryCache) do
            names[#names + 1] = ('%s(%s)'):format(entry.table, table.concat(entry.columns, ','))
        end
        print(('[21-easyck] escaneo: %s tablas con vínculo al personaje además de las configuradas: %s')
            :format(#discoveryCache, table.concat(names, ' ')))
    end

    return discoveryCache
end

-- Tablas configuradas (en su orden) + las detectadas. Es la lista con la que se
-- pinta la vista previa y con la que se borra.
local function targetTables()
    local list = {}
    for _, t in ipairs(Bridge.tables) do
        if tableExists(t.table) then list[#list + 1] = t end
    end
    for _, t in ipairs(discoverTables()) do
        list[#list + 1] = t
    end
    return list
end

-- Columnas de una tabla que apuntan al personaje. Las configuradas tienen una;
-- las detectadas pueden tener varias (emisor y receptor de un mensaje, por ejemplo).
local function linkColumns(entry)
    return entry.columns or { entry.column }
end

local function whereFor(entry)
    local parts = {}
    for _, column in ipairs(linkColumns(entry)) do
        parts[#parts + 1] = ident(column) .. ' = ?'
    end

    local where = #parts > 1 and ('(' .. table.concat(parts, ' OR ') .. ')') or parts[1]
    if entry.main and entry.filter then
        where = where .. ' AND (' .. entry.filter .. ')'
    end
    return where
end

-- Un valor del ID por cada columna de la condición, en el mismo orden.
local function paramsFor(entry, charId)
    local params = {}
    for _ = 1, #linkColumns(entry) do
        params[#params + 1] = charId
    end
    return params
end

-- Cuenta las filas de todas las tablas de golpe: una consulta por cada 15 tablas
-- en vez de una por tabla, que con una base de datos grande se nota.
local function countRows(entries, charId)
    local counts = {}
    local selects, params, chunk = {}, {}, {}

    local function flush()
        if #chunk == 0 then return end
        local ok, row = pcall(MySQL.single.await, 'SELECT ' .. table.concat(selects, ', '), params)
        if ok and row then
            for index, entry in ipairs(chunk) do
                counts[entry.table] = tonumber(row['c' .. index]) or 0
            end
        else
            for _, entry in ipairs(chunk) do
                local okOne, count = pcall(MySQL.scalar.await,
                    ('SELECT COUNT(*) FROM %s WHERE %s'):format(ident(entry.table), whereFor(entry)),
                    paramsFor(entry, charId))
                counts[entry.table] = okOne and (tonumber(count) or 0) or 0
            end
        end
        selects, params, chunk = {}, {}, {}
    end

    for _, entry in ipairs(entries) do
        chunk[#chunk + 1] = entry
        selects[#selects + 1] = ('(SELECT COUNT(*) FROM %s WHERE %s) AS c%d'):format(
            ident(entry.table), whereFor(entry), #chunk)
        for _, param in ipairs(paramsFor(entry, charId)) do
            params[#params + 1] = param
        end
        if #chunk >= 15 then flush() end
    end
    flush()

    return counts
end

-- Filas de una tabla para la interfaz: la clave primaria (para poder marcar filas
-- sueltas) y unas pocas columnas legibles.
local function fetchRows(entry, charId, limit)
    local info = tableColumns(entry.table)
    local key = primaryKeyOf(entry.table)
    local configured = previewConfig(entry.table).columns

    local columns = {}
    for _, column in ipairs(configured or {}) do
        if info.set[column] then columns[#columns + 1] = column end
    end
    if #columns == 0 then
        columns = autoColumns(entry.table, linkColumns(entry))
    end

    local selects, seen = {}, {}
    if key then
        selects[#selects + 1] = ident(key)
        seen[key] = true
    end
    for _, column in ipairs(columns) do
        if not seen[column] then
            selects[#selects + 1] = ident(column)
            seen[column] = true
        end
    end
    if #selects == 0 then return columns, {}, key end

    local ok, rows = pcall(MySQL.query.await,
        ('SELECT %s FROM %s WHERE %s LIMIT %d'):format(
            table.concat(selects, ', '), ident(entry.table), whereFor(entry), limit),
        paramsFor(entry, charId))
    if not ok then
        print(('[21-easyck] ^3No se han podido leer las filas de %s: %s^0'):format(entry.table, tostring(rows)))
        return columns, {}, key
    end

    local out = {}
    for _, row in ipairs(rows or {}) do
        local cells = {}
        for index, column in ipairs(columns) do
            cells[index] = cell(row[column])
        end
        out[#out + 1] = {
            id = (key and row[key] ~= nil) and tostring(row[key]) or nil,
            cells = cells,
        }
    end
    return columns, out, key
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

        -- 2. Qué se toca: tablas configuradas + detectadas, las secundarias primero y
        --    la principal al final (por las claves foráneas).
        --    data.tables es { ['player_vehicles'] = true }  -> la tabla entera
        --                   { ['player_vehicles'] = { ids = { '4', '9' } } } -> solo esas filas
        --    Sin selección se usan los valores por defecto de la configuración.
        local selection = data.tables
        local ordered, kept, partial = {}, {}, {}

        for _, t in ipairs(targetTables()) do
            if not t.main then
                local choice = selection and selection[t.table]
                local wanted
                if selection then
                    wanted = choice ~= nil and choice ~= false
                elseif t.discovered then
                    wanted = (Config.Discovery or {}).DefaultSelected ~= false
                else
                    wanted = selectedByDefault(t.table)
                end

                if wanted then
                    local ids = type(choice) == 'table' and choice.ids or nil
                    ordered[#ordered + 1] = { entry = t, ids = ids }
                    if ids then
                        partial[#partial + 1] = ('%s (%d)'):format(t.table, #ids)
                    end
                else
                    kept[#kept + 1] = t.table
                end
            end
        end
        ordered[#ordered + 1] = { entry = Bridge.mainTable }

        -- Cada consulta va siempre acotada al personaje, aunque se borren filas
        -- sueltas: así una lista de IDs manipulada no puede tocar a otro jugador.
        local function clauseFor(job)
            local where = whereFor(job.entry)
            local params = paramsFor(job.entry, data.charId)
            if job.ids and #job.ids > 0 then
                local key = primaryKeyOf(job.entry.table)
                if key then
                    where = where .. (' AND %s IN (%s)'):format(ident(key), string.rep('?', #job.ids, ', '))
                    for _, id in ipairs(job.ids) do params[#params + 1] = id end
                end
            end
            return where, params
        end

        -- 3. Copia de seguridad de todo lo que se va a tocar.
        local backup = {}
        if Config.Backup then
            for _, job in ipairs(ordered) do
                local where, params = clauseFor(job)
                local okSelect, rows = pcall(MySQL.query.await,
                    ('SELECT * FROM %s WHERE %s'):format(ident(job.entry.table), where), params)
                if okSelect and rows and #rows > 0 then
                    backup[job.entry.table] = rows
                elseif not okSelect then
                    print(('[21-easyck] ^3No se pudo copiar %s: %s^0'):format(job.entry.table, tostring(rows)))
                end
            end
        end

        -- 4. Borrado.
        local affected, mainAffected = 0, 0
        for _, job in ipairs(ordered) do
            local t = job.entry
            local where, params = clauseFor(job)
            local query
            if t.update then
                query = ('UPDATE %s SET %s WHERE %s'):format(ident(t.table), t.update, where)
            else
                query = ('DELETE FROM %s WHERE %s'):format(ident(t.table), where)
            end

            local okQuery, count = pcall(MySQL.update.await, query, params)
            if okQuery then
                affected = affected + (tonumber(count) or 0)
                if t == Bridge.mainTable then mainAffected = tonumber(count) or 0 end
            else
                print(('[21-easyck] ^3Error en %s: %s^0'):format(t.table, tostring(count)))
            end
        end

        if mainAffected == 0 then
            error(('no se ha modificado la tabla principal (%s)'):format(Bridge.mainTable.table))
        end

        -- 5. Registro.
        local staffName, staffLicense = staffInfo(staffSrc)
        local notes = {}
        if #kept > 0 then notes[#notes + 1] = table.concat(kept, ', ') end
        if #partial > 0 then notes[#notes + 1] = 'parcial: ' .. table.concat(partial, ', ') end
        local keptList = #notes > 0 and table.concat(notes, ' | ') or nil
        MySQL.insert.await(
            'INSERT INTO easy_ck_log (char_id, char_name, framework, reason, staff_name, staff_license, kept_tables, backup) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { key, data.name, Bridge.name, data.reason, staffName, staffLicense, keptList, Config.Backup and json.encode(backup) or nil }
        )
        sendWebhook(data, staffName, staffLicense, affected, keptList)

        TriggerEvent('21-easyck:characterKilled', {
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
        return notify(src, '21-easyck todavía no está listo.', 'error')
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
        print(('[21-easyck] ^3Error listando personajes: %s^0'):format(tostring(rows)))
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

-- Todo lo que se va a borrar del personaje, tabla por tabla. Incluye las tablas
-- configuradas y las que aparecen al escanear la base de datos.
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

    local entries = targetTables()
    local counts = countRows(entries, charId)

    for _, entry in ipairs(entries) do
        local count = counts[entry.table] or 0

        -- Las configuradas salen siempre (aunque estén vacías, para que se vea que se
        -- han mirado). Las detectadas solo si tienen filas de este personaje: si no,
        -- serían decenas de tablas a cero.
        if not entry.discovered or count > 0 then
            local cfg = previewConfig(entry.table)
            local columns, rows, key = {}, {}, primaryKeyOf(entry.table)
            if count > 0 then
                columns, rows, key = fetchRows(entry, charId, maxRows)
            end

            local selected
            if entry.main then
                selected = true
            elseif entry.discovered then
                selected = (Config.Discovery or {}).DefaultSelected ~= false
            else
                selected = selectedByDefault(entry.table)
            end

            preview.tables[#preview.tables + 1] = {
                table = entry.table,
                label = cfg.label or entry.table,
                links = linkColumns(entry),          -- columnas por las que está vinculado al personaje
                count = count,
                columns = columns,
                rows = rows,
                key = key,                           -- sin clave primaria no hay filas sueltas
                mode = entry.update and 'update' or 'delete',
                locked = entry.main == true,         -- la tabla principal siempre se borra entera
                discovered = entry.discovered == true,
                selected = selected,
            }
        end
    end

    return preview
end

-- Nunca se hace caso a lo que manda el cliente sin validarlo: la tabla tiene que
-- existir en la configuración o en el escaneo, y los IDs de fila tienen que ser
-- valores sueltos. El borrado por filas siempre se acota además al personaje.
local MAX_IDS = 5000

local function sanitizeSelection(list)
    local allowed = {}
    for _, entry in ipairs(targetTables()) do allowed[entry.table] = entry end

    local selection = {}
    if type(list) == 'table' then
        for _, item in ipairs(list) do
            local name = type(item) == 'table' and item.table or item
            local entry = type(name) == 'string' and allowed[name] or nil

            if entry then
                local ids = type(item) == 'table' and item.ids or nil
                if type(ids) == 'table' and #ids > 0 and primaryKeyOf(name) then
                    local clean = {}
                    for _, id in ipairs(ids) do
                        local kind = type(id)
                        if (kind == 'string' and #id <= 100) or kind == 'number' then
                            clean[#clean + 1] = tostring(id)
                            if #clean >= MAX_IDS then break end
                        end
                    end
                    selection[name] = #clean > 0 and { ids = clean } or nil
                else
                    selection[name] = true
                end
            end
        end
    end

    selection[Bridge.mainTable.table] = true -- el personaje siempre se borra entero
    return selection
end

RegisterNetEvent('21-easyck:ui:request', function()
    local src = source
    if Config.Debug then
        print(('[21-easyck] %s (%s) pide la interfaz: bridge=%s permiso=%s'):format(
            GetPlayerName(src) or '?', src, tostring(Bridge ~= nil), tostring(hasPermission(src))))
    end
    if not uiAllowed(src, 'open') then return end
    TriggerClientEvent('21-easyck:ui:open', src, {
        locale = LUI(),
        framework = Bridge.name,
        requireReason = Config.RequireReason and true or false,
        players = onlinePlayers(),
    })
end)

RegisterNetEvent('21-easyck:ui:players', function()
    local src = source
    if not uiAllowed(src, 'players') then return end
    TriggerClientEvent('21-easyck:ui:players', src, onlinePlayers())
end)

RegisterNetEvent('21-easyck:ui:list', function(search, offset)
    local src = source
    if not uiAllowed(src, 'list') then return end
    CreateThread(function()
        local list, more = listCharacters(search, offset, 30)
        TriggerClientEvent('21-easyck:ui:list', src, {
            characters = list,
            offset = math.max(tonumber(offset) or 0, 0),
            more = more,
            search = type(search) == 'string' and search or '',
        })
    end)
end)

RegisterNetEvent('21-easyck:ui:preview', function(target)
    local src = source
    if not uiAllowed(src, 'preview') then return end
    if type(target) ~= 'string' or target == '' or #target > 80 then return end

    CreateThread(function()
        local charId, err = resolveTarget(target)
        if not charId then
            return TriggerClientEvent('21-easyck:ui:preview', src, { error = err })
        end

        local okPreview, preview, previewErr = pcall(buildPreview, charId)
        if not okPreview then
            print(('[21-easyck] ^1Error al preparar la vista previa: %s^0'):format(tostring(preview)))
            return TriggerClientEvent('21-easyck:ui:preview', src, { error = L('failed', tostring(preview)) })
        end
        if not preview then
            return TriggerClientEvent('21-easyck:ui:preview', src, { error = previewErr })
        end

        -- Testigo de confirmación: solo se puede ejecutar el CK del personaje que se acaba de ver.
        uiPending[src] = {
            charId = charId,
            name = preview.name,
            expires = os.time() + 600,
        }
        TriggerClientEvent('21-easyck:ui:preview', src, preview)
    end)
end)

-- "Cargar todas las filas" de una tabla concreta, para poder marcarlas una a una.
RegisterNetEvent('21-easyck:ui:rows', function(tableName, charId)
    local src = source
    if not uiAllowed(src, 'rows') then return end
    if type(tableName) ~= 'string' or tableName == '' or #tableName > 80 then return end

    local pendingData = uiPending[src]
    if not pendingData or tostring(pendingData.charId) ~= tostring(charId) then return end

    CreateThread(function()
        local entry
        for _, candidate in ipairs(targetTables()) do
            if candidate.table == tableName then
                entry = candidate
                break
            end
        end
        if not entry then return end

        local limit = (Config.Preview and Config.Preview.MaxRowsExpanded) or 500
        local columns, rows, key = fetchRows(entry, pendingData.charId, limit)
        TriggerClientEvent('21-easyck:ui:rows', src, {
            table = tableName,
            columns = columns,
            rows = rows,
            key = key,
        })
    end)
end)

RegisterNetEvent('21-easyck:ui:execute', function(charId, reason, tables)
    local src = source
    if not uiAllowed(src, 'execute') then return end

    local data = uiPending[src]
    uiPending[src] = nil

    local function fail(msg)
        notify(src, msg, 'error')
        TriggerClientEvent('21-easyck:ui:result', src, { ok = false, message = msg })
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
            TriggerClientEvent('21-easyck:ui:result', src, {
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
--   local ok, result = exports['21-easyck']:CharacterKill('ABC12345', 'Motivo')
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
    if GuardOk ~= true then return end -- ver server/guard.lua

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
