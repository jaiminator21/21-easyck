local uiOpen = false

local function debug(msg)
    if Config.Debug then
        print(('[easy-ck] %s'):format(msg))
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
    TriggerServerEvent('easy-ck:ui:request')
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

RegisterNetEvent('easy-ck:ui:open', function(data)
    debug(('el servidor ha respondido: %s jugadores'):format(#(data.players or {})))
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end)

RegisterNetEvent('easy-ck:ui:players', function(players)
    SendNUIMessage({ action = 'players', data = players })
end)

RegisterNetEvent('easy-ck:ui:list', function(data)
    SendNUIMessage({ action = 'list', data = data })
end)

RegisterNetEvent('easy-ck:ui:preview', function(data)
    SendNUIMessage({ action = 'preview', data = data })
end)

RegisterNetEvent('easy-ck:ui:result', function(data)
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
    TriggerServerEvent('easy-ck:ui:players')
    cb(1)
end)

RegisterNUICallback('list', function(data, cb)
    TriggerServerEvent('easy-ck:ui:list', data.search or '', data.offset or 0)
    cb(1)
end)

RegisterNUICallback('preview', function(data, cb)
    TriggerServerEvent('easy-ck:ui:preview', tostring(data.target or ''))
    cb(1)
end)

RegisterNUICallback('execute', function(data, cb)
    TriggerServerEvent('easy-ck:ui:execute', tostring(data.charId or ''), data.reason or '', data.tables or {})
    cb(1)
end)

-- Si el recurso se reinicia con la interfaz abierta, no dejar el ratón bloqueado.
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        SetNuiFocus(false, false)
    end
end)
