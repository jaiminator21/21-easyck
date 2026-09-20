Config = {}

-- Idioma de los mensajes: 'es' | 'en'
Config.Locale = 'es'

-- Framework: 'auto' | 'esx' | 'qbcore' | 'qbox' | 'ox' | 'custom'
-- En 'auto' se detecta según los recursos arrancados (qbx_core > es_extended > qb-core > ox_core).
Config.Framework = 'auto'

-- Comandos
Config.Command        = 'characterkill'
Config.ConfirmCommand = 'ckconfirm'
Config.CancelCommand  = 'ckcancel'
-- Abre la interfaz con la lista de jugadores y la vista previa de lo que se va a borrar
Config.MenuCommand    = 'ckmenu'
-- Tecla por defecto para la interfaz ('' para no asignar ninguna). El jugador puede cambiarla en Ajustes > Teclado.
Config.MenuKeybind    = ''

-- Escribe en la consola (F8 en el cliente, consola del servidor) cada paso de la
-- interfaz. Útil si /ckmenu no abre nada.
Config.Debug = false

-- Segundos que tiene el staff para confirmar el CK
Config.ConfirmTimeout = 30

-- Obliga a escribir un motivo: /characterkill <id> <motivo>
Config.RequireReason = false

-- Permisos. La consola del servidor siempre tiene permiso.
Config.Permissions = {
    -- add_ace group.admin easyck.use allow
    Ace = 'easyck.use',
    -- Grupos del framework que también pueden usarlo (ESX getGroup / QBCore HasPermission / ACE group.<nombre>)
    Groups = { 'admin', 'superadmin', 'god' },
}

-- Autodetección: easy-ck recorre TODA la base de datos y se queda con cualquier
-- tabla que tenga una columna con el ID del personaje (en Qbox/QB el `citizenid`).
-- Ese ID es el identificador principal: lo que se busca en la base de datos es su
-- valor, así que una columna que no contenga ese ID sale con 0 filas y no se muestra.
-- Así aparecen también las tablas de scripts que no has puesto a mano: teléfono,
-- redes sociales, casas, tatuajes, trabajos, facturas...
Config.Discovery = {
    Enabled = true,

    -- Cualquier columna cuyo nombre CONTENGA uno de estos textos se considera un
    -- vínculo con el personaje. Cubre nombres como `citizenid`, `owner_citizenid`,
    -- `sender_citizenid`, `target_cid`, `player_charid`...
    -- Al nombre de la columna principal del framework se le añade solo.
    Patterns = {
        'citizenid', 'citizen_id', 'charid', 'char_id', 'identifier',
        'stateid', 'state_id', 'cid',
    },

    -- Nombres exactos de columnas que no llevan ninguno de esos textos.
    -- Que sobren no molesta: si no contienen el ID del personaje, salen a 0 filas
    -- y no se enseñan.
    Columns = { 'owner', 'holder', 'player', 'character', 'character_id', 'user' },

    -- Si una tabla tiene varias columnas válidas (por ejemplo emisor y receptor en
    -- los mensajes del teléfono), se cuentan y se borran las filas de todas ellas.

    -- Tablas que nunca se tocan aunque tengan una de esas columnas.
    -- Los baneos y los avisos del staff van aquí a propósito: si se borraran con el CK,
    -- cualquiera se quitaría un baneo haciéndose un personaje nuevo. Quita de la lista
    -- lo que quieras que sí se borre.
    Ignore = {
        'easy_ck_log',
        'bans', 'ban', 'banlist', 'ban_list', 'easyadmin_bans', 'txadmin_bans',
        'warnings', 'warns', 'player_warns', 'playerwarnings', 'admin_logs', 'logs',
    },

    -- Las tablas detectadas salen marcadas para borrar. Ponlo en false si prefieres
    -- revisarlas una a una antes de cada CK.
    DefaultSelected = true,
}

-- Vista previa de la interfaz: qué se le muestra al staff antes de confirmar el CK.
Config.Preview = {
    -- Filas de detalle que se envían por tabla al abrir la ficha
    -- (el recuento siempre es el total real)
    MaxRows = 25,

    -- Filas que se envían al pulsar "cargar todas las filas" de una tabla,
    -- que es cuando se pueden marcar y desmarcar una a una
    MaxRowsExpanded = 500,

    -- Etiqueta, columnas y estado por defecto de cada tabla. Las tablas que no estén aquí
    -- salen igualmente con su nombre y su número de filas.
    --   label   = nombre que se muestra en la interfaz
    --   columns = columnas del detalle (las que no existan en tu BD se ignoran)
    --   default = false -> la casilla sale desmarcada, así que NO se borra salvo que el staff la marque.
    --             Afecta también al comando /characterkill, que respeta estos valores por defecto.
    -- La tabla principal del personaje siempre se borra y no se puede desmarcar.
    Tables = {
        players         = { label = 'Personaje',       columns = { 'citizenid', 'name', 'money', 'job' } },
        users           = { label = 'Personaje',       columns = { 'identifier', 'firstname', 'lastname', 'accounts' } },
        characters      = { label = 'Personaje',       columns = { 'charId', 'firstName', 'lastName' } },
        player_vehicles = { label = 'Vehículos',       columns = { 'plate', 'vehicle', 'garage', 'state' } },
        owned_vehicles  = { label = 'Vehículos',       columns = { 'plate', 'vehicle', 'type', 'stored' } },
        vehicles        = { label = 'Vehículos',       columns = { 'plate', 'model', 'stored' } },
        playerskins     = { label = 'Apariencia',      columns = { 'model' } },
        player_outfits  = { label = 'Outfits',         columns = { 'outfitname', 'model' } },
        player_houses   = { label = 'Casas',           columns = { 'house', 'stash' } },
        properties      = { label = 'Propiedades',     columns = { 'id', 'name' } },
        owned_properties= { label = 'Propiedades',     columns = { 'name', 'price' } },
        apartments      = { label = 'Apartamentos',    columns = { 'name', 'type' } },
        bank_accounts   = { label = 'Cuentas bancarias', columns = { 'account_name', 'account_balance' } },
        player_groups   = { label = 'Trabajos y bandas', columns = { 'group', 'type', 'grade' } },
        player_contacts = { label = 'Contactos',       columns = { 'name', 'number' } },
        player_mails    = { label = 'Correos',         columns = { 'sender', 'subject' } },
        phone_messages  = { label = 'Mensajes',        columns = { 'number' } },
        phone_invoices  = { label = 'Facturas',        columns = { 'amount', 'society' } },
        billing         = { label = 'Facturas',        columns = { 'label', 'amount' } },
        crypto_transactions = { label = 'Cripto',      columns = { 'title', 'message' } },
        user_licenses   = { label = 'Licencias',       columns = { 'type' } },
        addon_account_data    = { label = 'Cuentas',   columns = { 'account_name', 'money' } },
        addon_inventory_items = { label = 'Inventarios', columns = { 'inventory_name', 'name', 'count' } },
        datastore_data  = { label = 'Datos guardados', columns = { 'name' } },
        character_inventory = { label = 'Inventario',  columns = { 'name' } },
        character_groups    = { label = 'Grupos',      columns = { 'name', 'grade' } },
        character_licenses  = { label = 'Licencias',   columns = { 'name' } },
    },
}

-- Milisegundos que se espera tras expulsar al jugador para que el framework
-- termine de guardar sus datos ANTES de borrarlos (si no, el guardado podría recrear el personaje).
Config.SaveDelay = 3000

-- Guarda una copia JSON de todas las filas borradas en la tabla `easy_ck_log` (permite restaurar a mano)
Config.Backup = true

-- Webhook de Discord para registrar los CK ('' para desactivar)
Config.Webhook      = ''
Config.WebhookName  = 'Easy CK'
Config.WebhookColor = 15158332

-- Notificación al staff. Por defecto usa el chat. Puedes sustituirla por la de tu framework:
-- Config.Notify = function(src, msg, kind) TriggerClientEvent('ox_lib:notify', src, { description = msg, type = kind }) end
Config.Notify = nil

--[[
    Tablas que se borran en cada framework.
      table   = nombre de la tabla
      column  = columna que contiene el ID del personaje (identifier / citizenid / charId)
      main    = tabla principal del personaje (se usa para buscarlo y se borra la última)
      update  = en lugar de DELETE, hace UPDATE <table> SET <update> (borrado lógico)
      filter  = condición extra al buscar el personaje en la tabla principal

    Las tablas que no existan en tu base de datos se ignoran automáticamente.
    Añade aquí las tablas de tus scripts (teléfono, casas, facturas...).
]]
Config.Tables = {
    esx = {
        { table = 'users',                 column = 'identifier', main = true },
        { table = 'owned_vehicles',        column = 'owner' },
        { table = 'user_licenses',         column = 'owner' },
        { table = 'addon_account_data',    column = 'owner' },
        { table = 'addon_inventory_items', column = 'owner' },
        { table = 'datastore_data',        column = 'owner' },
        { table = 'owned_properties',      column = 'owner' },
        { table = 'billing',               column = 'identifier' },
    },

    qbcore = {
        { table = 'players',             column = 'citizenid', main = true },
        { table = 'player_vehicles',     column = 'citizenid' },
        { table = 'playerskins',         column = 'citizenid' },
        { table = 'player_outfits',      column = 'citizenid' },
        { table = 'player_houses',       column = 'citizenid' },
        { table = 'apartments',          column = 'citizenid' },
        { table = 'bank_accounts',       column = 'citizenid' },
        { table = 'player_contacts',     column = 'citizenid' },
        { table = 'player_mails',        column = 'citizenid' },
        { table = 'phone_messages',      column = 'citizenid' },
        { table = 'phone_invoices',      column = 'citizenid' },
        { table = 'crypto_transactions', column = 'citizenid' },
    },

    qbox = {
        { table = 'players',         column = 'citizenid', main = true },
        { table = 'player_groups',   column = 'citizenid' },
        { table = 'player_vehicles', column = 'citizenid' },
        { table = 'playerskins',     column = 'citizenid' },
        { table = 'player_outfits',  column = 'citizenid' },
        { table = 'properties',      column = 'owner' },
    },

    ox = {
        -- ox_core marca los personajes como borrados en lugar de eliminarlos
        { table = 'characters', column = 'charId', main = true, update = 'deleted = CURDATE()', filter = 'deleted IS NULL' },
        -- Descomenta para eliminar también sus datos asociados:
        -- { table = 'vehicles',            column = 'owner' },
        -- { table = 'character_inventory', column = 'charId' },
        -- { table = 'character_groups',    column = 'charId' },
        -- { table = 'character_licenses',  column = 'charId' },
    },

    custom = {
        { table = 'characters', column = 'id', main = true },
    },
}

-- Solo si Config.Framework = 'custom': cómo obtener el ID del personaje de un jugador conectado
-- y cómo mostrar su nombre a partir de la fila de la tabla principal.
Config.Custom = {
    GetCharId = function(src)
        return Player(src).state.charId
    end,
    GetName = function(row)
        return ('%s %s'):format(row.firstname or '?', row.lastname or '')
    end,
    -- 'string' o 'number', según el tipo de la columna del ID en la base de datos
    IdType = 'string',
}
