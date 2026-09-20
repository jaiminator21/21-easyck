-- Resource identity lock.
--
-- The license allows using and modifying this script, but not reselling it or
-- republishing it as your own. What this file checks is that the identity has not
-- been changed: the resource name, the fxmanifest credits, the event and export
-- names, and that the LICENSE file is still there.
--
-- This is not copy protection: the code ships in plain Lua and the lock can be
-- removed. It only makes renaming the script a deliberate act, so that nobody can
-- claim they republished it under another name by accident.

local EXPECTED_NAME   = '21-easyck'
local EXPECTED_AUTHOR = 'Jaime Sebastián'

-- Strings that must still be present, verbatim, in each file.
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
        'The following is expressly PROHIBITED',
    },
}

local resourceName = GetCurrentResourceName()

local function fail(reason)
    print('^1')
    print('^1  ############################################################^0')
    print(('^1  %s stopped: %s^0'):format(EXPECTED_NAME, reason))
    print('^1  ############################################################^0')
    print(('^3  This script is distributed for free as "%s", by %s.^0'):format(EXPECTED_NAME, EXPECTED_AUTHOR))
    print('^3  You may use and modify it, but not rename it, republish it as your^0')
    print('^3  own or sell it. Full terms in LICENSE.^0')
    print('^3  If you got it from a store or a paid bundle, it was sold to you^0')
    print('^3  without permission: get it for free from the original repository.^0')
    print('^1')

    GuardOk = false
    pcall(StopResource, resourceName)
    return false
end

-- Runs on startup. Nothing else in the resource does anything unless this passes.
local function verify()
    if resourceName ~= EXPECTED_NAME then
        return fail(('the folder is named "%s" and must be named "%s"'):format(resourceName, EXPECTED_NAME))
    end

    if GetResourceMetadata(resourceName, 'name', 0) ~= EXPECTED_NAME then
        return fail('the name in fxmanifest.lua was changed')
    end

    if GetResourceMetadata(resourceName, 'author', 0) ~= EXPECTED_AUTHOR then
        return fail('the author credits were removed from fxmanifest.lua')
    end

    for file, markers in pairs(MARKERS) do
        local contents = LoadResourceFile(resourceName, file)
        if not contents or contents == '' then
            return fail(('%s is missing'):format(file))
        end
        for _, marker in ipairs(markers) do
            if not contents:find(marker, 1, true) then
                return fail(("the script's identity was altered in %s (%s)"):format(file, marker))
            end
        end
    end

    GuardOk = true
    return true
end

verify()
