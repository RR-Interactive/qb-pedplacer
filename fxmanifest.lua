fx_version 'cerulean'
game 'gta5'

name 'qb-pedplacer'
description 'QBCore Ped/NPC Placer — place, persist & manage peds via ox_lib menus'
author 'RR Interactive'
version '1.6.3'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/logo.png',
}

lua54 'yes'

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
}

-- Cfx.re asset escrow: config, UI and SQL install stay open.
escrow_ignore {
    'config.lua',
    'html/*',
    'sql/*',
    'README.md',
    'CHANGELOG.md',
    'LICENSE',
}

dependency '/assetpacks'
