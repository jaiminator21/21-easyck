-- Prueba de humo de 21-easyck.
-- Simula el runtime de FiveM y oxmysql para recorrer el flujo entero sin
-- levantar un servidor: apertura de la interfaz, listado de personajes,
-- escaneo de la base de datos, vista previa, CK con selección de tablas y de
-- filas sueltas, y el export.
--
--   lua tools/smoke.lua

local ROOT = (arg and arg[0] and arg[0]:match('^(.*)tools[/\\]smoke%.lua$')) or ''
local queries, events, clientMsgs = {}, {}, {}

-- ── json mínimo ────────────────────────────────────────────────────────
json = {
    encode = function() return '{json}' end,
    decode = function(s)
        if s == nil or s == '' then error('empty') end
        if s:find('firstname') then return { firstname = 'Juan', lastname = 'Pérez', birthdate = '1990-01-01', phone = '555' } end
        if s:find('cash') then return { cash = 1234, bank = 56789, crypto = 3 } end
        if s:find('police') then return { label = 'Policía', name = 'police', grade = { name = 'Cadete', level = 0 } } end
        if s:find('none') then return { label = 'Ninguna', name = 'none' } end
        error('unknown json')
    end,
}

-- ── natives ────────────────────────────────────────────────────────────
function GetCurrentResourceName() return '21-easyck' end
function GetResourceState(name) return name == 'qbx_core' and 'started' or 'missing' end
function GetPlayers() return { '1', '5' } end
function GetPlayerName(src) return 'Jugador' .. tostring(src) end
function GetPlayerPing() return 42 end
function GetPlayerIdentifierByType() return 'license:abc' end
local clock = 0
function GetGameTimer() clock = clock + 1000 return clock end
function IsPlayerAceAllowed() return true end
function DropPlayer() end
function PerformHttpRequest() end
function Wait() end
function CreateThread(fn) fn() end
function TriggerEvent() end
function TriggerClientEvent(name, src, data) clientMsgs[#clientMsgs + 1] = { name = name, data = data } end
function RegisterCommand() end
function AddEventHandler() end
function RegisterNetEvent(name, fn) events[name] = fn end

-- Para el candado de server/guard.lua: lee los archivos de verdad del recurso.
local stopped
function StopResource(name) stopped = name end

function LoadResourceFile(_, file)
    local handle = io.open(ROOT .. file, 'r')
    if not handle then return nil end
    local contents = handle:read('a')
    handle:close()
    return contents
end

function GetResourceMetadata(_, key)
    local manifest = LoadResourceFile(nil, 'fxmanifest.lua') or ''
    return manifest:match(key .. " '([^']+)'")
end

local qbxPlayer = { PlayerData = { citizenid = 'ABC12345', charinfo = { firstname = 'Juan', lastname = 'Pérez' }, job = { label = 'Policía' } } }
-- En FiveM `exports` se puede llamar (exports('nombre', fn)) e indexar (exports.qbx_core)
_G.exports = setmetatable({
    qbx_core = { GetPlayer = function(_, src) return src == 1 and qbxPlayer or nil end },
}, { __call = function(_, name, fn) _G.resourceExports[name] = fn end })
_G.resourceExports = {}

-- ── base de datos simulada ─────────────────────────────────────────────
-- columnas: { nombre, tipo, es_clave_primaria }
local schema = {
    players         = { { 'citizenid', 'varchar', true }, { 'name', 'varchar' }, { 'charinfo', 'longtext' },
                        { 'money', 'longtext' }, { 'job', 'longtext' }, { 'gang', 'longtext' }, { 'last_updated', 'timestamp' } },
    player_vehicles = { { 'id', 'int', true }, { 'citizenid', 'varchar' }, { 'plate', 'varchar' }, { 'vehicle', 'varchar' }, { 'garage', 'varchar' }, { 'state', 'int' } },
    playerskins     = { { 'id', 'int', true }, { 'citizenid', 'varchar' }, { 'model', 'varchar' } },
    player_outfits  = { { 'id', 'int', true }, { 'citizenid', 'varchar' }, { 'outfitname', 'varchar' }, { 'model', 'varchar' } },
    player_groups   = { { 'citizenid', 'varchar', true }, { 'group', 'varchar', true }, { 'type', 'varchar' }, { 'grade', 'int' } },
    properties      = { { 'id', 'int', true }, { 'owner', 'varchar' }, { 'name', 'varchar' } },
    -- No están en Config.Tables: tienen que salir por el escaneo
    phone_messages  = { { 'id', 'int', true }, { 'citizenid', 'varchar' }, { 'number', 'varchar' }, { 'message', 'text' } },
    npwd_messages   = { { 'id', 'int', true }, { 'sender_citizenid', 'varchar' }, { 'receiver_citizenid', 'varchar' }, { 'body', 'text' } },
    twitter_accounts= { { 'id', 'int', true }, { 'citizenid', 'varchar' }, { 'username', 'varchar' } },
    mdt_convictions = { { 'id', 'int', true }, { 'citizenid', 'varchar' }, { 'charge', 'varchar' } },
    bans            = { { 'id', 'int', true }, { 'citizenid', 'varchar' }, { 'reason', 'varchar' } },
    -- Nombre con guion, como los recursos 21-*: hay que poder entrecomillarlo
    ['21-robberies_evidence'] = { { 'id', 'int', true }, { 'citizenid', 'varchar' }, { 'item', 'varchar' } },
    easy_ck_log     = { { 'id', 'int', true }, { 'char_id', 'varchar' }, { 'kept_tables', 'text' } },
}

-- Filas que tiene el personaje en cada tabla. Lo que no esté aquí, 0.
local counts = {
    players = 1, player_vehicles = 6, playerskins = 1, player_outfits = 4,
    player_groups = 3, properties = 2,
    phone_messages = 184, npwd_messages = 12, twitter_accounts = 2,
    mdt_convictions = 0, -- detectada pero sin filas: no debe aparecer
    ['21-robberies_evidence'] = 4,
}

local charRow = {
    citizenid = 'ABC12345', name = 'Jaime', last_updated = '2026-09-19 22:00:00',
    charinfo = '{"firstname":"Juan"}', money = '{"cash":1}', job = '{"label":"police"}', gang = '{"none":1}',
}

local function run(query, params)
    queries[#queries + 1] = query

    if query:find('information_schema.tables WHERE') then
        return schema[params[1]] and 1 or 0
    end

    -- Escaneo: todas las columnas que casan con los patrones
    if query:find('information_schema.columns col') then
        local rows = {}
        for name, columns in pairs(schema) do
            for _, column in ipairs(columns) do
                local lower = column[1]:lower()
                if lower:find('citizenid') or lower:find('charid') or lower:find('identifier')
                    or lower:find('cid') or lower == 'owner' then
                    rows[#rows + 1] = { t = name, c = column[1] }
                end
            end
        end
        table.sort(rows, function(a, b) return a.t .. a.c < b.t .. b.c end)
        return rows
    end

    if query:find('information_schema.columns') then
        local rows = {}
        for _, column in ipairs(schema[params[1]] or {}) do
            rows[#rows + 1] = { c = column[1], t = column[2], k = column[3] and 'PRI' or '' }
        end
        return rows
    end

    -- Recuento por lotes: se resuelve cada subconsulta por el nombre de su tabla
    if query:find('^SELECT %(SELECT COUNT') then
        local row, index = {}, 0
        for name in query:gmatch('FROM `([^`]+)` WHERE') do
            index = index + 1
            row['c' .. index] = counts[name] or 0
        end
        return row
    end

    if query:find('^SELECT COUNT%(%*%) FROM `') then
        return counts[query:match('^SELECT COUNT%(%*%) FROM `([^`]+)`')] or 0
    end

    if query:find('^SELECT %* FROM `players`') then
        if query:find('LIMIT 1') then return charRow end
        return { charRow, charRow }
    end

    if query:find('^SELECT') then
        local name = query:match('FROM `([^`]+)`')
        local rows = {}
        for i = 1, math.min(counts[name] or 0, tonumber(query:match('LIMIT (%d+)')) or 25) do
            rows[#rows + 1] = { id = i, citizenid = 'ABC12345', plate = 'ABC ' .. i, vehicle = 'sultan',
                                number = '555-010' .. i, username = 'user' .. i, body = 'hola',
                                outfitname = 'Traje', model = 'mp_m_freemode_01', name = 'Casa', group = 'police',
                                type = 'job', grade = 1, garage = 'legion', state = 1, message = 'hola' }
        end
        return rows
    end

    if query:find('^DELETE') or query:find('^UPDATE') then return 2 end
    if query:find('^INSERT') then return 10 end
    return {}
end

MySQL = {
    query = { await = run }, scalar = { await = run }, single = { await = run },
    update = { await = run }, insert = { await = run },
    ready = function(fn) fn() end,
}

-- ── carga del recurso ──────────────────────────────────────────────────
dofile(ROOT .. 'config.lua')
dofile(ROOT .. 'locales.lua')
dofile(ROOT .. 'server/guard.lua')
dofile(ROOT .. 'server/bridge.lua')
dofile(ROOT .. 'server/main.lua')

local function last(name)
    for i = #clientMsgs, 1, -1 do
        if clientMsgs[i].name == name then return clientMsgs[i].data end
    end
end

local failures = 0
local function check(label, cond, extra)
    print((cond and '  ok   ' or '  FAIL ') .. label .. (extra and (' -> ' .. tostring(extra)) or ''))
    if not cond then failures = failures + 1 end
end

local function touched(list)
    local out = {}
    for _, q in ipairs(list) do
        local name = q:match('^DELETE FROM `([^`]+)`') or q:match('^UPDATE `([^`]+)`')
        if name then out[name] = q end
    end
    return out
end

print('\n== candado de identidad ==')
check('el recurso se valida a sí mismo', GuardOk == true)
check('no se ha detenido', stopped == nil, stopped)

print('\n== apertura ==')
source = 1
events['21-easyck:ui:request']()
local open = last('21-easyck:ui:open')
check('framework detectado', open.framework == 'qbox', open.framework)
check('textos de interfaz', open.locale.tab_all == 'Todos', open.locale.tab_all)
check('jugadores en línea', #open.players == 2, #open.players)
check('nombre del personaje', open.players[1].name == 'Juan Pérez', open.players[1].name)

print('\n== pestaña todos ==')
events['21-easyck:ui:list']('juan', 0)
local list = last('21-easyck:ui:list')
check('devuelve personajes', #list.characters == 2, #list.characters)
check('marca quién está en línea', list.characters[1].online == 1, tostring(list.characters[1].online))

print('\n== escaneo de la base de datos ==')
events['21-easyck:ui:preview']('cid:ABC12345')
local preview = last('21-easyck:ui:preview')
check('sin error', preview.error == nil, preview.error)

local byName = {}
for _, tbl in ipairs(preview.tables) do byName[tbl.table] = tbl end

check('salen las tablas configuradas', byName.players and byName.player_vehicles and byName.properties)
check('sale una tabla que no está en la config', byName.phone_messages ~= nil)
check('marcada como detectada', byName.phone_messages and byName.phone_messages.discovered == true)
check('sale la de redes sociales', byName.twitter_accounts ~= nil)
check('detecta las dos columnas de los mensajes',
    byName.npwd_messages and #byName.npwd_messages.links == 2,
    byName.npwd_messages and table.concat(byName.npwd_messages.links, ','))
check('las detectadas sin filas no se enseñan', byName.mdt_convictions == nil)
check('respeta la lista de ignoradas (baneos)', byName.bans == nil)
check('admite nombres de tabla con guion', byName['21-robberies_evidence'] ~= nil)
check('recuento real', byName.phone_messages and byName.phone_messages.count == 184, byName.phone_messages and byName.phone_messages.count)
check('la principal va bloqueada', byName.players.locked == true and byName.players.selected == true)

print('\n== filas ==')
check('clave primaria detectada', byName.player_vehicles.key == 'id', byName.player_vehicles.key)
check('sin clave primaria de una columna no hay filas sueltas', byName.player_groups.key == nil, byName.player_groups.key)
check('las filas traen su id', byName.player_vehicles.rows[1] and byName.player_vehicles.rows[1].id == '1',
    byName.player_vehicles.rows[1] and byName.player_vehicles.rows[1].id)
check('muestra limitada a Config.Preview.MaxRows', #byName.phone_messages.rows == 25, #byName.phone_messages.rows)
check('columnas automáticas sin la de enlace', (function()
    for _, column in ipairs(byName.twitter_accounts.columns) do
        if column == 'citizenid' then return false end
    end
    return true
end)())

queries = {}
events['21-easyck:ui:rows']('phone_messages', 'ABC12345')
local rows = last('21-easyck:ui:rows')
check('carga todas las filas de una tabla', rows and #rows.rows == 184, rows and #rows.rows)

print('\n== CK con selección de tablas y de filas ==')
queries = {}
events['21-easyck:ui:execute']('ABC12345', 'Motivo de prueba', {
    { table = 'player_vehicles', ids = { '2', '5' } },   -- solo dos coches
    { table = 'twitter_accounts' },                      -- la cuenta entera
    { table = 'tabla_inventada' },                       -- no existe: se ignora
})
local result = last('21-easyck:ui:result')
check('CK correcto', result.ok == true, result.message)

local hit = touched(queries)
check('borra la tabla detectada elegida', hit.twitter_accounts ~= nil)
check('borra siempre la principal', hit.players ~= nil)
check('no toca lo que no se ha marcado', hit.phone_messages == nil and hit.playerskins == nil and hit.npwd_messages == nil)
check('ignora tablas inventadas', hit.tabla_inventada == nil)
check('borra solo las filas marcadas', hit.player_vehicles and hit.player_vehicles:find('`id` IN %(%?, %?%)') ~= nil,
    hit.player_vehicles)
check('el borrado por filas sigue atado al personaje',
    hit.player_vehicles and hit.player_vehicles:find('`citizenid` = %?') ~= nil)

local insert
for _, q in ipairs(queries) do if q:find('^INSERT INTO easy_ck_log') then insert = q end end
check('deja constancia de lo conservado y lo parcial', insert and insert:find('kept_tables') ~= nil)

print('\n== la ejecución exige vista previa ==')
events['21-easyck:ui:execute']('ABC12345', 'otra vez', { { table = 'player_vehicles' } })
check('segunda ejecución rechazada', last('21-easyck:ui:result').ok == false, last('21-easyck:ui:result').message)

print('\n== export sin interfaz (valores por defecto) ==')
queries = {}
local ok, affected = resourceExports.CharacterKill('ABC12345', 'Desde otro recurso')
check('el export sigue funcionando', ok == true, affected)

local all = touched(queries)
check('sin selección borra todo lo vinculado al personaje',
    all.players and all.player_vehicles and all.playerskins and all.player_outfits
    and all.player_groups and all.properties and all.phone_messages and all.twitter_accounts
    and all.npwd_messages ~= nil)
check('sin selección tampoco toca los baneos', all.bans == nil)
check('sin selección borra también las tablas con guion', all['21-robberies_evidence'] ~= nil)

-- Este va al final: deja GuardOk a false a propósito.
print('\n== el candado salta si se renombra la carpeta ==')
local realName = GetCurrentResourceName
function GetCurrentResourceName() return 'freeck-vendido-en-tebex' end
dofile(ROOT .. 'server/guard.lua')
check('no se carga con otro nombre de carpeta', GuardOk == false)
check('detiene el recurso', stopped == 'freeck-vendido-en-tebex', stopped)
GetCurrentResourceName = realName

if failures > 0 then
    print(('\n%d comprobaciones han fallado.\n'):format(failures))
    os.exit(1)
end
print('\nTodo correcto.\n')
