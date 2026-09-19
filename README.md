# easy-ck

Script **standalone** de FiveM para hacer **CK (Character Kill / muerte permanente)** con un solo comando. Funciona con **ESX, QBCore, Qbox y ox_core**, y con cualquier otro framework mediante el modo `custom`.

## Características

- **Interfaz** (`/ckmenu`) con la lista de jugadores conectados y la lista completa de personajes de la base de datos, con buscador.
- **Vista previa de todo lo que se va a borrar** antes de confirmar: vehículos, outfits, cuentas, contactos, mensajes… con el número de filas y una muestra de cada tabla.
- **Casillas por tabla** para elegir qué se borra y qué se conserva (por ejemplo dejar intactos los mensajes del teléfono o las redes sociales).
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

   El ACE `easyck.use` es lo único que hace falta para tener permiso. No basta con
   `add_ace group.admin command allow`: eso solo cubre los comandos restringidos,
   no los permisos propios de cada script.
3. Revisa `Config.Tables` en `config.lua` y añade las tablas de tus scripts (teléfono, casas, facturas…).

## Uso

| Comando | Descripción |
|---|---|
| `/ckmenu` | Abre la interfaz (lista de jugadores + vista previa + selección de tablas) |
| `/characterkill 12 Muerte en rol de atraco` | CK al jugador conectado con ID 12 |
| `/characterkill ABC12345 Motivo` | CK por citizenid (QB/Qbox) aunque esté desconectado |
| `/characterkill char1:1a2b3c...` | CK por identifier (ESX multicharacter) |
| `/characterkill cid:37` | Fuerza que `37` se interprete como ID de personaje (útil en ox_core) |
| `/ckconfirm` | Confirma el CK pendiente |
| `/ckcancel` | Cancela el CK pendiente |

Si pasas un número y hay un jugador conectado con ese ID, se usa ese jugador. Si no hay nadie conectado con ese ID, el número se interpreta como ID de personaje. Usa `cid:` si quieres evitar la ambigüedad.

También funciona desde la consola del servidor (`characterkill 12`, `ckconfirm`).

## Interfaz

`/ckmenu` (configurable en `Config.MenuCommand`, y con tecla opcional en `Config.MenuKeybind`).

- **En línea**: jugadores conectados, con su ID de servidor, su citizenid y su trabajo.
- **Todos**: todos los personajes de la tabla principal, ordenados por última conexión y con
  buscador por nombre o citizenid. Así se puede hacer CK a alguien que lleva meses sin entrar.
- Al elegir un personaje se muestra su ficha (nombre, teléfono, trabajo, dinero…) y **todas las
  tablas que le pertenecen**, con el número de filas y un desplegable con una muestra de los datos
  (matrículas, nombres de outfits, saldos…). El tamaño de la muestra es `Config.Preview.MaxRows`.
- Cada tabla tiene una casilla. Lo que quede desmarcado **no se toca**. La tabla principal del
  personaje siempre se borra y no se puede desmarcar.
- El CK se lanza manteniendo pulsado el botón, para que no salga por un clic de más.

### Elegir qué se borra

Las casillas salen marcadas por defecto. Si hay tablas que casi nunca quieres borrar (redes
sociales, mensajes del teléfono…), márcalas en `Config.Preview.Tables` con `default = false`:

```lua
phone_messages  = { label = 'Mensajes', columns = { 'number' }, default = false },
player_contacts = { label = 'Contactos', columns = { 'name', 'number' }, default = false },
```

Salen desmarcadas en la interfaz y el comando `/characterkill` también las respeta, así que solo
se borran si el staff las marca a mano.

Para que una tabla aparezca en la interfaz tiene que estar en `Config.Tables` del framework que
uses. Lo de `Config.Preview.Tables` es solo la etiqueta, las columnas del detalle y el valor por
defecto de la casilla.

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

Cada CK guarda en `easy_ck_log.backup` un JSON con este formato: `{ "tabla": [filas...] }`. Si hace falta revertir un CK, puedes reinsertar esas filas a mano. La columna `easy_ck_log.kept_tables` indica qué tablas se dejaron sin tocar en ese CK.

## Prueba de humo

`lua tools/smoke.lua` recorre el flujo entero (interfaz, listados, vista previa, CK con selección
parcial y export) con un servidor y una base de datos simulados. No necesita FiveM ni MySQL.

> ⚠️ Prueba el script primero en una base de datos de desarrollo y revisa que la lista de tablas coincida con tu servidor. El borrado es real.
