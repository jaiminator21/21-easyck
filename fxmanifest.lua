fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'easy-ck'
description 'Character Kill standalone y multi-framework (ESX, QBCore, Qbox, ox_core)'
author 'Jaime Sebastián'
version '1.0.0'

shared_scripts {
    'config.lua',
    'locales.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/main.lua',
}

client_script 'client/main.lua'

dependency 'oxmysql'
