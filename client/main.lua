-- Mismo candado que en server/guard.lua: si se ha renombrado la carpeta, el
-- cliente no registra ni el comando ni la interfaz.
if GetCurrentResourceName() ~= '21-easyck' then
    print('^121-easyck: la carpeta del recurso se ha renombrado, el script no se carga.^0')
    return
end

local uiOpen = false

local function debug(msg)
    if Config.Debug then
        print(('[21-easyck] %s'):format(msg))
    end
end

local function closeUi()
    if not uiOpen then return end
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

---------------------------------------------------------------------------
-- Comando y tecla para abrir la interfaz. El permiso se comprueba en el
-- servidor; aquí solo se pide abrirla.
---------------------------------------------------------------------------

RegisterCommand(Config.MenuCommand, function()
    if uiOpen then return closeUi() end
    debug('/' .. Config.MenuCommand .. ' -> pidiendo la interfaz al servidor')
    TriggerServerEvent('21-easyck:ui:request')
end, false)

if Config.MenuKeybind and Config.MenuKeybind ~= '' then
    RegisterKeyMapping(Config.MenuCommand, L('keybind_label'), 'keyboard', Config.MenuKeybind)
end

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/' .. Config.Command, L('suggestion'), {
        { name = 'id', help = L('arg_target') },
        { name = 'motivo', help = L('arg_reason') },
    })
    TriggerEvent('chat:addSuggestion', '/' .. Config.ConfirmCommand, L('confirm_help'))
    TriggerEvent('chat:addSuggestion', '/' .. Config.CancelCommand, L('cancel_help'))
    TriggerEvent('chat:addSuggestion', '/' .. Config.MenuCommand, L('menu_help'))
end)

---------------------------------------------------------------------------
-- Respuestas del servidor -> interfaz
---------------------------------------------------------------------------

RegisterNetEvent('21-easyck:ui:open', function(data)
    debug(('el servidor ha respondido: %s jugadores'):format(#(data.players or {})))
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end)

RegisterNetEvent('21-easyck:ui:players', function(players)
    SendNUIMessage({ action = 'players', data = players })
end)

RegisterNetEvent('21-easyck:ui:list', function(data)
    SendNUIMessage({ action = 'list', data = data })
end)

RegisterNetEvent('21-easyck:ui:preview', function(data)
    SendNUIMessage({ action = 'preview', data = data })
end)

RegisterNetEvent('21-easyck:ui:rows', function(data)
    SendNUIMessage({ action = 'rows', data = data })
end)

RegisterNetEvent('21-easyck:ui:result', function(data)
    SendNUIMessage({ action = 'result', data = data })
end)

---------------------------------------------------------------------------
-- Interfaz -> servidor
---------------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb(1)
end)

RegisterNUICallback('players', function(_, cb)
    TriggerServerEvent('21-easyck:ui:players')
    cb(1)
end)

RegisterNUICallback('list', function(data, cb)
    TriggerServerEvent('21-easyck:ui:list', data.search or '', data.offset or 0)
    cb(1)
end)

RegisterNUICallback('preview', function(data, cb)
    TriggerServerEvent('21-easyck:ui:preview', tostring(data.target or ''))
    cb(1)
end)

RegisterNUICallback('rows', function(data, cb)
    TriggerServerEvent('21-easyck:ui:rows', tostring(data.table or ''), tostring(data.charId or ''))
    cb(1)
end)

RegisterNUICallback('execute', function(data, cb)
    TriggerServerEvent('21-easyck:ui:execute', tostring(data.charId or ''), data.reason or '', data.tables or {})
    cb(1)
end)

-- Si el recurso se reinicia con la interfaz abierta, no dejar el ratón bloqueado.
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        SetNuiFocus(false, false)
    end
end)
