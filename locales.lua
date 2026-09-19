Locales = {
    es = {
        no_permission   = 'No tienes permiso para usar este comando.',
        usage           = 'Uso: /%s <id en línea | id de personaje> [motivo]. Usa cid:<id> para forzar el ID de personaje.',
        reason_required = 'Debes indicar un motivo.',
        player_no_char  = 'El jugador %s no tiene ningún personaje cargado.',
        char_not_found  = 'No existe ningún personaje con el ID "%s".',
        confirm         = 'CK preparado: %s (%s) [%s]. Escribe /%s en %ds para confirmar o /%s para cancelar.',
        online          = 'en línea, ID %s',
        offline         = 'desconectado',
        nothing_pending = 'No tienes ningún CK pendiente de confirmar.',
        expired         = 'La confirmación ha caducado. Vuelve a lanzar el comando.',
        cancelled       = 'CK cancelado.',
        busy            = 'Ya hay un CK en curso para ese personaje.',
        in_progress     = 'Ejecutando CK de %s...',
        done            = 'CK completado: %s (%s). Filas afectadas: %d.',
        failed          = 'Error al ejecutar el CK: %s',
        kick_message    = 'Tu personaje ha sufrido un CK (muerte permanente). Motivo: %s',
        no_reason       = 'Sin motivo',
        console         = 'Consola',
        suggestion      = 'Realiza un CK (muerte permanente) a un personaje',
        arg_target      = 'ID en línea o ID de personaje (cid:<id>)',
        arg_reason      = 'Motivo (opcional)',
        confirm_help    = 'Confirma el CK pendiente',
        cancel_help     = 'Cancela el CK pendiente',
    },
    en = {
        no_permission   = 'You are not allowed to use this command.',
        usage           = 'Usage: /%s <server id | character id> [reason]. Use cid:<id> to force a character id.',
        reason_required = 'You must provide a reason.',
        player_no_char  = 'Player %s has no character loaded.',
        char_not_found  = 'No character found with id "%s".',
        confirm         = 'CK ready: %s (%s) [%s]. Type /%s within %ds to confirm or /%s to cancel.',
        online          = 'online, ID %s',
        offline         = 'offline',
        nothing_pending = 'You have no pending CK to confirm.',
        expired         = 'Confirmation expired. Run the command again.',
        cancelled       = 'CK cancelled.',
        busy            = 'A CK is already running for that character.',
        in_progress     = 'Running CK on %s...',
        done            = 'CK completed: %s (%s). Rows affected: %d.',
        failed          = 'CK failed: %s',
        kick_message    = 'Your character has been character-killed (permanent death). Reason: %s',
        no_reason       = 'No reason',
        console         = 'Console',
        suggestion      = 'Character-kill (permanent death) a character',
        arg_target      = 'Server id or character id (cid:<id>)',
        arg_reason      = 'Reason (optional)',
        confirm_help    = 'Confirm the pending CK',
        cancel_help     = 'Cancel the pending CK',
    },
}

function L(key, ...)
    local str = (Locales[Config.Locale] or Locales.en)[key] or Locales.en[key] or key
    if select('#', ...) > 0 then
        return str:format(...)
    end
    return str
end
