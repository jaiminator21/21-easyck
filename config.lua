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
