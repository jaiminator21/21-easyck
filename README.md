# easy-ck

Script **standalone** de FiveM para hacer **CK (Character Kill / muerte permanente)** con un solo comando. Funciona con **ESX, QBCore, Qbox y ox_core**, y con cualquier otro framework mediante el modo `custom`.

## Características

- Detección automática del framework (`Config.Framework = 'auto'`).
- `/characterkill <id>` acepta el **ID en línea** del jugador o el **ID del personaje** (`citizenid` en QB/Qbox, `identifier` en ESX, `charId` en ox_core). Así se puede hacer CK a personajes desconectados.
- **Confirmación en dos pasos** (`/ckconfirm`, `/ckcancel`) con tiempo límite.
- Expulsa al jugador si está conectado y espera a que el framework guarde antes de borrar, para que el personaje no reaparezca.
- **Copia de seguridad en JSON** de todas las filas borradas en la tabla `easy_ck_log` (se crea sola).
- Log en Discord por webhook.
- Lista de tablas configurable por framework. Las tablas que no existan se ignoran.
- Permisos por ACE o por grupo del framework.
- Export y evento para integrarlo con otros scripts.

## Requisitos

- [oxmysql](https://github.com/overextended/oxmysql)

## Instalación

1. Copia la carpeta en `resources/` y llámala `easy-ck`.
2. En `server.cfg`, arranca el script **después** de oxmysql y de tu framework:
   ```cfg
   ensure oxmysql
   ensure es_extended   # o qb-core / qbx_core / ox_core
   ensure easy-ck

   add_ace group.admin easyck.use allow
   ```
3. Revisa `Config.Tables` en `config.lua` y añade las tablas de tus scripts (teléfono, casas, facturas…).

## Uso

| Comando | Descripción |
|---|---|
| `/characterkill 12 Muerte en rol de atraco` | CK al jugador conectado con ID 12 |
| `/characterkill ABC12345 Motivo` | CK por citizenid (QB/Qbox) aunque esté desconectado |
| `/characterkill char1:1a2b3c...` | CK por identifier (ESX multicharacter) |
| `/characterkill cid:37` | Fuerza que `37` se interprete como ID de personaje (útil en ox_core) |
| `/ckconfirm` | Confirma el CK pendiente |
| `/ckcancel` | Cancela el CK pendiente |

Si pasas un número y hay un jugador conectado con ese ID, se usa ese jugador. Si no hay nadie conectado con ese ID, el número se interpreta como ID de personaje. Usa `cid:` si quieres evitar la ambigüedad.

También funciona desde la consola del servidor (`characterkill 12`, `ckconfirm`).

## Frameworks

| Framework | Tabla principal | ID de personaje | Borrado |
|---|---|---|---|
| ESX Legacy | `users` | `identifier` | DELETE |
| QBCore | `players` | `citizenid` | DELETE |
| Qbox | `players` | `citizenid` | DELETE |
| ox_core | `characters` | `charId` | Lógico (`deleted = CURDATE()`), igual que el propio ox_core |
| Custom | configurable | configurable | configurable |

Para otro framework, pon `Config.Framework = 'custom'` y rellena `Config.Tables.custom` y `Config.Custom`.

## Integración con otros scripts

```lua
-- Servidor: CK sin confirmación
local ok, result = exports['easy-ck']:CharacterKill('ABC12345', 'Motivo')

-- Se lanza después de cada CK
AddEventHandler('easy-ck:characterKilled', function(data)
    -- data.charId, data.name, data.reason, data.framework, data.staff
end)
```

## Restaurar un CK

Cada CK guarda en `easy_ck_log.backup` un JSON con este formato: `{ "tabla": [filas...] }`. Si hace falta revertir un CK, puedes reinsertar esas filas a mano.

> ⚠️ Prueba el script primero en una base de datos de desarrollo y revisa que la lista de tablas coincida con tu servidor. El borrado es real.
