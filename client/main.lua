CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/' .. Config.Command, L('suggestion'), {
        { name = 'id', help = L('arg_target') },
        { name = 'motivo', help = L('arg_reason') },
    })
    TriggerEvent('chat:addSuggestion', '/' .. Config.ConfirmCommand, L('confirm_help'))
    TriggerEvent('chat:addSuggestion', '/' .. Config.CancelCommand, L('cancel_help'))
end)
