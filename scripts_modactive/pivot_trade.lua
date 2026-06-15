
local main_gui = reqscript('internal/pivot_trade/pivot_trade_ui')

if not dfhack_flags.module then
    main_gui.main()
end
