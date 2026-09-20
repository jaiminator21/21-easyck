-- Candado de identidad del recurso.
--
-- La licencia permite usar y modificar el script, pero no revenderlo ni publicarlo
-- como propio. Lo que comprueba esto es que no se le haya cambiado la identidad:
-- el nombre del recurso, los créditos del fxmanifest, los nombres de los eventos y
-- del export, y que siga estando el archivo LICENSE.
--
-- No es una protección: el código va en claro y se puede quitar. Es un candado que
-- obliga a tocar el script a conciencia para renombrarlo, de forma que nadie pueda
-- decir que lo publicó con otro nombre "sin darse cuenta".

local EXPECTED_NAME   = '21-easyck'
local EXPECTED_AUTHOR = 'Jaime Sebastián'

-- Cadenas que tienen que seguir estando tal cual en cada archivo.
local MARKERS = {
    ['fxmanifest.lua'] = {
        "name '21-easyck'",
        "author 'Jaime Sebastián'",
    },
    ['server/main.lua'] = {
        "RegisterNetEvent('21-easyck:ui:request'",
        "RegisterNetEvent('21-easyck:ui:preview'",
        "RegisterNetEvent('21-easyck:ui:execute'",
        "TriggerEvent('21-easyck:characterKilled'",
        "exports('CharacterKill'",
    },
    ['client/main.lua'] = {
        "RegisterNetEvent('21-easyck:ui:open'",
        "TriggerServerEvent('21-easyck:ui:request')",
        "RegisterNUICallback('execute'",
    },
    ['LICENSE'] = {
        'Copyright (c) 2026 Jaime Sebastián',
        'Queda expresamente PROHIBIDO',
    },
}

local resourceName = GetCurrentResourceName()

local function fail(reason)
    print('^1')
    print('^1  ############################################################^0')
    print(('^1  %s se ha detenido: %s^0'):format(EXPECTED_NAME, reason))
    print('^1  ############################################################^0')
    print(('^3  Este script se distribuye gratis como "%s", de %s.^0'):format(EXPECTED_NAME, EXPECTED_AUTHOR))
    print('^3  Puedes usarlo y modificarlo, pero no renombrarlo ni publicarlo^0')
    print('^3  como propio ni venderlo. Condiciones completas en LICENSE.^0')
    print('^3  Si lo has descargado de una tienda o de un pack de pago, te lo^0')
    print('^3  han vendido sin permiso: pídelo gratis en el repositorio original.^0')
    print('^1')

    GuardOk = false
    pcall(StopResource, resourceName)
    return false
end

-- Se ejecuta al arrancar. El resto del recurso no hace nada si esto no pasa.
local function verify()
    if resourceName ~= EXPECTED_NAME then
        return fail(('la carpeta se llama "%s" y tiene que llamarse "%s"'):format(resourceName, EXPECTED_NAME))
    end

    if GetResourceMetadata(resourceName, 'name', 0) ~= EXPECTED_NAME then
        return fail('se ha cambiado el nombre en fxmanifest.lua')
    end

    if GetResourceMetadata(resourceName, 'author', 0) ~= EXPECTED_AUTHOR then
        return fail('se han quitado los créditos del autor en fxmanifest.lua')
    end

    for file, markers in pairs(MARKERS) do
        local contents = LoadResourceFile(resourceName, file)
        if not contents or contents == '' then
            return fail(('falta el archivo %s'):format(file))
        end
        for _, marker in ipairs(markers) do
            if not contents:find(marker, 1, true) then
                return fail(('se ha modificado la identidad del script en %s (%s)'):format(file, marker))
            end
        end
    end

    GuardOk = true
    return true
end

verify()
