Config = {}

-- Message language: 'es' | 'en'
Config.Locale = 'es'

-- Framework: 'auto' | 'esx' | 'qbcore' | 'qbox' | 'ox' | 'custom'
-- With 'auto' it is detected from the running resources (qbx_core > es_extended > qb-core > ox_core).
Config.Framework = 'auto'

-- Commands
Config.Command        = 'characterkill'
Config.ConfirmCommand = 'ckconfirm'
Config.CancelCommand  = 'ckcancel'
-- Opens the UI: player list plus a preview of everything that will be deleted
Config.MenuCommand    = 'ckmenu'
-- Default key for the UI ('' for none). Players can rebind it in Settings > Key Bindings.
Config.MenuKeybind    = ''

-- Logs every step of the UI to the console (F8 on the client, server console).
-- Useful when /ckmenu does not open anything.
Config.Debug = false

-- Seconds the staff member has to confirm the CK
Config.ConfirmTimeout = 30

-- Forces a reason to be given: /characterkill <id> <reason>
Config.RequireReason = false

-- Permissions. The server console is always allowed.
Config.Permissions = {
    -- add_ace group.admin easyck.use allow
    Ace = 'easyck.use',
    -- Framework groups that may also use it (ESX getGroup / QBCore HasPermission / ACE group.<name>)
    Groups = { 'admin', 'superadmin', 'god' },
}

-- Auto-discovery: 21-easyck walks the WHOLE database and keeps every table that has
-- a column holding the character id (`citizenid` on Qbox/QB).
-- That id is the primary identifier: what is looked up in the database is its VALUE,
-- so a column that does not hold it comes back with 0 rows and is never shown.
-- This is how tables you never listed by hand show up too: phone, social media,
-- houses, tattoos, jobs, invoices...
Config.Discovery = {
    Enabled = true,

    -- Any column whose name CONTAINS one of these strings counts as a link to the
    -- character. Covers names such as `citizenid`, `owner_citizenid`,
    -- `sender_citizenid`, `target_cid`, `player_charid`...
    -- The main column of your framework is added to this list automatically.
    Patterns = {
        'citizenid', 'citizen_id', 'charid', 'char_id', 'identifier',
        'stateid', 'state_id', 'cid',
    },

    -- Exact column names that do not contain any of those strings.
    -- Extra entries do no harm: if they do not hold the character id, they come back
    -- with 0 rows and are not shown.
    Columns = { 'owner', 'holder', 'player', 'character', 'character_id', 'user' },

    -- When a table has several matching columns (sender and receiver in phone
    -- messages, for example), rows from all of them are counted and deleted.

    -- Tables that are never touched, even if they have one of those columns.
    -- Bans and staff warnings are here on purpose: if a CK wiped them, anyone could
    -- clear a ban by making a new character. Remove from this list whatever you do
    -- want deleted.
    Ignore = {
        'easy_ck_log',
        'bans', 'ban', 'banlist', 'ban_list', 'easyadmin_bans', 'txadmin_bans',
        'warnings', 'warns', 'player_warns', 'playerwarnings', 'admin_logs', 'logs',
    },

    -- Discovered tables come pre-ticked for deletion. Set this to false if you would
    -- rather review them one by one before each CK.
    DefaultSelected = true,
}

-- UI preview: what the staff member sees before confirming the CK.
Config.Preview = {
    -- Detail rows sent per table when the character sheet opens
    -- (the row count is always the real total)
    MaxRows = 25,

    -- Rows sent when "load every row" is pressed on a table, which is when rows can
    -- be ticked and unticked individually
    MaxRowsExpanded = 500,

    -- Label, columns and default state per table. Tables that are not listed here
    -- still show up, with their raw name and their row count.
    --   label   = name shown in the UI
    --   columns = detail columns (any that do not exist in your database are ignored)
    --   default = false -> the checkbox starts unticked, so it is NOT deleted unless
    --             the staff member ticks it. The /characterkill command honours these
    --             defaults too.
    -- The character's main table is always deleted and cannot be unticked.
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

-- Milliseconds to wait after kicking the player so the framework finishes saving
-- their data BEFORE it is deleted (otherwise that save could recreate the character).
Config.SaveDelay = 3000

-- Stores a JSON copy of every deleted row in the `easy_ck_log` table (allows manual restore)
Config.Backup = true

-- Discord webhook to log every CK ('' to disable)
Config.Webhook      = ''
Config.WebhookName  = 'Easy CK'
Config.WebhookColor = 15158332

-- Staff notification. Uses the chat by default. Swap it for your framework's:
-- Config.Notify = function(src, msg, kind) TriggerClientEvent('ox_lib:notify', src, { description = msg, type = kind }) end
Config.Notify = nil

--[[
    Tables deleted for each framework.
      table   = table name
      column  = column holding the character id (identifier / citizenid / charId)
      main    = the character's main table (used to look them up, deleted last)
      update  = run UPDATE <table> SET <update> instead of DELETE (soft delete)
      filter  = extra condition when looking the character up in the main table

    Tables that do not exist in your database are skipped automatically.
    Add your own scripts' tables here (phone, houses, invoices...).
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
        -- ox_core flags characters as deleted instead of removing them
        { table = 'characters', column = 'charId', main = true, update = 'deleted = CURDATE()', filter = 'deleted IS NULL' },
        -- Uncomment to delete their related data as well:
        -- { table = 'vehicles',            column = 'owner' },
        -- { table = 'character_inventory', column = 'charId' },
        -- { table = 'character_groups',    column = 'charId' },
        -- { table = 'character_licenses',  column = 'charId' },
    },

    custom = {
        { table = 'characters', column = 'id', main = true },
    },
}

-- Only when Config.Framework = 'custom': how to get the character id of an online
-- player, and how to render their name from the main table row.
Config.Custom = {
    GetCharId = function(src)
        return Player(src).state.charId
    end,
    GetName = function(row)
        return ('%s %s'):format(row.firstname or '?', row.lastname or '')
    end,
    -- 'string' or 'number', matching the type of the id column in the database
    IdType = 'string',
}
