-- Prueba de humo de easy-ck.
-- Simula el runtime de FiveM y oxmysql para recorrer el flujo entero sin
-- levantar un servidor: apertura de la interfaz, listado de personajes,
-- vista previa, CK con selección parcial de tablas y export.
--
--   lua tools/smoke.lua

-- Se ejecuta con:  lua tools/smoke.lua   (desde la carpeta del recurso)
local ROOT = (arg and arg[0] and arg[0]:match('^(.*)tools[/\\]smoke%.lua$')) or ''
local queries, events, clientMsgs = {}, {}, {}

-- ── json mínimo ────────────────────────────────────────────────────────
json = {
    encode = function(v) return '{json}' end,
    decode = function(s)
        if s == nil or s == '' then error('empty') end
        if s:find('firstname') then return { firstname = 'Juan', lastname = 'Pérez', birthdate = '1990-01-01', phone = '555' } end
        if s:find('cash') then return { cash = 1234, bank = 56789, crypto = 3 } end
        if s:find('"label"') and s:find('police') then return { label = 'Policía', name = 'police', grade = { name = 'Cadete', level = 0 } } end
        if s:find('none') then return { label = 'Ninguna', name = 'none' } end
        error('unknown json')
    end,
}

-- ── natives ────────────────────────────────────────────────────────────
function GetCurrentResourceName() return 'easy-ck' end
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
local qbxPlayer = { PlayerData = { citizenid = 'ABC12345', charinfo = { firstname = 'Juan', lastname = 'Pérez' }, job = { label = 'Policía' } } }
-- En FiveM `exports` se puede llamar (exports('nombre', fn)) e indexar (exports.qbx_core)
_G.exports = setmetatable({
    qbx_core = { GetPlayer = function(_, src) return src == 1 and qbxPlayer or nil end },
}, { __call = function(_, name, fn) _G.resourceExports[name] = fn end })
_G.resourceExports = {}

-- ── oxmysql simulado ───────────────────────────────────────────────────
local columns = {
    players = { 'citizenid', 'name', 'charinfo', 'money', 'job', 'gang', 'last_updated' },
    player_vehicles = { 'citizenid', 'plate', 'vehicle', 'garage', 'state' },
    playerskins = { 'citizenid', 'model' },
    player_outfits = { 'citizenid', 'outfitname', 'model' },
    player_groups = { 'citizenid', 'group', 'type', 'grade' },
    properties = { 'owner', 'id', 'name' },
    easy_ck_log = { 'id', 'char_id', 'kept_tables' },
}

local charRow = {
    citizenid = 'ABC12345', name = 'Jaime', last_updated = '2026-09-19 22:00:00',
    charinfo = '{"firstname":"Juan"}', money = '{"cash":1}', job = '{"label":"police"}', gang = '{"none":1}',
}

local function run(query, params)
    queries[#queries + 1] = query
    if query:find('information_schema.tables') then return 1 end
    if query:find('information_schema.columns') then
        local name = params[1]
        local rows = {}
        for _, c in ipairs(columns[name] or {}) do rows[#rows + 1] = { c = c } end
        return rows
    end
    if query:find('^SELECT COUNT%(%*%) FROM') then return 3 end
    if query:find('^SELECT %* FROM `players`') then
        if query:find('LIMIT 1') then return charRow end
        return { charRow, charRow }
    end
    if query:find('^SELECT') then return { { plate = 'ABC 123', vehicle = 'sultan', garage = 'legion', state = 1 } } end
    if query:find('^DELETE') or query:find('^UPDATE') then return 2 end
    if query:find('^INSERT') then return 10 end
    if query:find('^ALTER') then return 0 end
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
dofile(ROOT .. 'server/bridge.lua')
dofile(ROOT .. 'server/main.lua')

local function last(name)
    for i = #clientMsgs, 1, -1 do
        if clientMsgs[i].name == name then return clientMsgs[i].data end
    end
end

local function check(label, cond, extra)
    print((cond and '  ok   ' or '  FAIL ') .. label .. (extra and (' -> ' .. tostring(extra)) or ''))
    if not cond then os.exit(1) end
end

print('\n== apertura ==')
source = 1
events['easy-ck:ui:request']()
local open = last('easy-ck:ui:open')
check('framework detectado', open.framework == 'qbox', open.framework)
check('textos de interfaz', open.locale.title ~= nil and open.locale.tab_all == 'Todos', open.locale.tab_all)
check('jugadores en línea', #open.players == 2, #open.players)
check('citizenid del jugador 1', open.players[1].charId == 'ABC12345', open.players[1].charId)
check('nombre del personaje', open.players[1].name == 'Juan Pérez', open.players[1].name)

print('\n== pestaña todos ==')
source = 1
events['easy-ck:ui:list']('juan', 0)
local list = last('easy-ck:ui:list')
check('devuelve personajes', #list.characters == 2, #list.characters)
check('marca quién está en línea', list.characters[1].online == 1, tostring(list.characters[1].online))
local searchQuery = queries[#queries - 1] or ''
check('busca en varias columnas', select(2, queries[#queries]:gsub('LIKE', '')) >= 0)

print('\n== vista previa ==')
source = 1
events['easy-ck:ui:preview']('cid:ABC12345')
local preview = last('easy-ck:ui:preview')
check('sin error', preview.error == nil, preview.error)
check('nombre', preview.name == 'Juan Pérez', preview.name)
check('tablas listadas', #preview.tables == 6, #preview.tables)
check('la principal va bloqueada', preview.tables[1].locked == true and preview.tables[1].selected == true)
local byName = {}
for _, tbl in ipairs(preview.tables) do byName[tbl.table] = tbl end
check('recuento por tabla', byName.player_vehicles.count == 3, byName.player_vehicles.count)
check('detalle de vehículos', #byName.player_vehicles.rows == 1 and byName.player_vehicles.rows[1][1] == 'ABC 123',
    byName.player_vehicles.rows[1] and byName.player_vehicles.rows[1][1])
check('columnas filtradas por las que existen', #byName.player_vehicles.columns == 4, #byName.player_vehicles.columns)
check('etiqueta traducida', byName.player_outfits.label == 'Outfits', byName.player_outfits.label)
check('ficha con dinero', (function()
    for _, f in ipairs(preview.summary) do if f.key == 'f_cash' then return f.value == '$1' end end
end)() ~= nil)

print('\n== ejecución con selección parcial ==')
queries = {}
source = 1
events['easy-ck:ui:execute']('ABC12345', 'Motivo de prueba', { 'player_vehicles', 'tabla_falsa' })
local result = last('easy-ck:ui:result')
check('CK correcto', result.ok == true, result.message)

local deleted = {}
for _, q in ipairs(queries) do
    local tbl = q:match('^DELETE FROM `([%w_]+)`') or q:match('^UPDATE `([%w_]+)`')
    if tbl then deleted[tbl] = true end
end
check('borra la tabla elegida', deleted.player_vehicles == true)
check('borra siempre la principal', deleted.players == true)
check('respeta lo no seleccionado', deleted.playerskins == nil and deleted.player_outfits == nil and deleted.properties == nil)
check('ignora tablas inventadas por el cliente', deleted.tabla_falsa == nil)

local insert
for _, q in ipairs(queries) do if q:find('^INSERT INTO easy_ck_log') then insert = q end end
check('registra el CK con las tablas conservadas', insert and insert:find('kept_tables') ~= nil)

print('\n== segunda confirmación sin vista previa ==')
source = 1
events['easy-ck:ui:execute']('ABC12345', 'otra vez', { 'player_vehicles' })
local second = last('easy-ck:ui:result')
check('exige vista previa antes de ejecutar', second.ok == false, second.message)

print('\n== export sin interfaz (valores por defecto) ==')
queries = {}
local ok, affected = resourceExports.CharacterKill('ABC12345', 'Desde otro recurso')
check('el export sigue funcionando', ok == true, affected)

local deletedAll = {}
for _, q in ipairs(queries) do
    local tbl = q:match('^DELETE FROM `([%w_]+)`') or q:match('^UPDATE `([%w_]+)`')
    if tbl then deletedAll[tbl] = true end
end
check('sin selección borra todas las tablas configuradas',
    deletedAll.players and deletedAll.player_vehicles and deletedAll.playerskins
    and deletedAll.player_outfits and deletedAll.player_groups and deletedAll.properties)

print('\nTodo correcto.\n')
