local setmetatable = setmetatable
local tonumber = tonumber
local io = io
local type = type
local print = print
local button = require("awful.button")
local vicious = require("vicious")
local wibox = require("wibox")
local widget2 = require("awful.widget")
local config = require("forgotten")
local beautiful = require("beautiful")
local util = require("awful.util")
local radical      = require( "radical"                  )
local allinone = require("widgets.allinone")
local capi = { screen = screen, mouse = mouse}

local module = {}

local mainMenu = nil

local errcount = 0

local volumewidget2 = nil

--Pulseaudio pid
local pavuId = -1
local pavuSinkN=0



function amixer_volume_int(format)
    local f
    if mode == "pulse" then
        f = io.popen('pactl list sinks | grep -A 9 "Sink #'..pavuSinkN..'" | tail -n 1 | cut -d "/" -f 2 | grep -o -e "[0-9]*"')
    else
        f = io.popen('amixer sget Master 2> /dev/null | tail -n1 |cut -f 7 -d " " | grep -o -e "[0-9]*"')
    end

    if f then
        local l = f:read()
        f:close()
        local toReturn
        if (not l) or l == "" then
            toReturn = 0
            if mode == "alsa" then
                errcount = errcount + 1
                if errcount > 10 then
                    print("Too many amixer failure, stopping listener")
                    vicious.unregister(volumewidget2)
                end
            end
        else
            toReturn = tonumber(l)
        end
        return {toReturn}
    else
        print("Calling amixer failed")
    end
    return {}
end

--args {
--      pavuSink    =   Default sink number
--      mode        =   "pulse" : Pulseaudio mode (Require pactl)
--                      "alsa"  : Alsa mode
--                      nil     : Search for pactl if not found use alsa
local function new(mywibox3,args)
    --Variables---------------------------------------------------------
    local pavuSink, mode = nil,nil

    --Functions---------------------------------------------------------
    function volumeUp(devId)
        util.spawn_with_shell("amixer sset "..devId.." 2%+ >/dev/null")
    end
    function volumeDown(devId)
        util.spawn_with_shell("amixer sset "..devId.." 2%- >/dev/null")
    end
    function soundInfo()

        --Add menu header
        mainMenu:add_widget(radical.widgets.header(aMenu,"CHANNEL")  , {height = 20  , width = 200})

        --Parse Devices names
        local f = io.popen("amixer scontrols | awk '{print$4}'| grep -oe '[a-zA-Z]*'")
        while true do
            local aChannal = f:read("*line")
            if aChannal == nil then break end

            local f2= io.popen('amixer sget '.. aChannal ..' 2> /dev/null | tail -n1 |cut -f 7 -d " " | grep -o -e "[0-9]*" 2> /dev/null')
            local aVolume = (tonumber(f2:read("*line")) or 0) / 100
            f2:close()

            local mute = wibox.widget.imagebox()
            mute:set_image(config.iconPath .. "volm.png")

            local volume = widget2.progressbar()
            volume:set_width(80)
            volume:set_height(20)
            volume:set_background_color(beautiful.bg_normal)
            volume:set_border_color(beautiful.fg_normal)
            volume:set_color(beautiful.fg_normal)
            volume:set_value(aVolume or 0)
            if (widget2.progressbar.set_offset ~= nil) then
                volume:set_offset(1)
            end

            mainMenu:add_item({text=aChannal,prefix_widget=mute,suffix_widget=volume,button4=function(geo,parent)
                        print("Scroll UP") 
                        aVolume=aVolume+0.02
                        volume:set_value(aVolume)
                    end, button5=function(geo,parent)
                        print("Scroll Down") 
                        aVolume=aVolume-0.02
                        volume:set_value(aVolume)
                    end})
        end
        f:close()
    end

    --Constructor ------------------------------------------------------
    if volumewidget2 then return volumewidget2 end
    volumewidget2 = allinone()
    volumewidget2:set_icon(config.iconPath .. "vol.png")

    --Parse args
    if args ~= nil then
        pavuSink    =  args.pavuSink
        mode        =  args.mode
    end

    --Auto working mode selection
    if not mode then
        --Check if pulseaudio is running
        local f = io.popen('whereis pavucontrol | cut -d":" -f2| wc -c')
        local temp = (tonumber(f:read("*all")) or 0)
        if temp > 2 then
            mode    =   "pulse"
            pavuSink=   pavuSink or 0
        else mode="alsa" end
        --
        print("INFO@SoundInfo: Auto mode detected",soundService)
        f:close()
    end

    local btn
    if mode=="alsa" then
        --Alsa mode (Classic)

        btn = util.table.join(
            button({ }, 1, function(geo)
                    if not mainMenu then
                        mainMenu = radical.context({width=200,arrow_type=radical.base.arrow_type.CENTERED})
                        soundInfo()
                    end
                    mainMenu.visible = not mainMenu.visible
                    mainMenu.parent_geometry = geo

                    if mywibox3 and type(mywibox3) == "wibox" then
                        mywibox3.visible = not mywibox3.visible
                    end
                    musicBarVisibility = true
                end),
            button({ }, 3, function()
                    util.spawn_with_shell("amixer set Master 1+ toggle")
                end),
            button({ }, 4, function()
                    util.spawn_with_shell("amixer sset Master 2%+ >/dev/null")
                    if volumewidget2.percent > 0.98 then volumewidget2.percent=1
                    else volumewidget2.percent=volumewidget2.percent+0.02 end
                    print("V:",volumewidget2.percent)
                end),
            button({ }, 5, function()
                    util.spawn_with_shell("amixer sset Master 2%- >/dev/null")
                    if volumewidget2.percent < 0.02 then volumewidget2.percent=0
                    else volumewidget2.percent=volumewidget2.percent-0.02 end
                end)
        )
    else
        --Pulseaudio mode
        btn = util.table.join(
            button({ }, 1, function(geo)
                    if pavuId == -1 then
                        --Open pavucontrol
                        pavuId=(util.spawn("pavucontrol") or -1)
                    else
                        --Close open window
                        util.spawn_with_shell('kill -3 ' ..pavuId)
                        pavuId=-1
                    end
                end),
            button({ }, 3, function()
                    util.spawn_with_shell("pactl set-sink-mute "..pavuSinkN.." toggle")
                end),
            button({ }, 4, function()
                    if volumewidget2.percent > 1.48 then
                        volumewidget2.percent=1.5
                        util.spawn_with_shell("pactl set-sink-volume "..pavuSinkN.." -- 150%")
                    else
                        volumewidget2.percent=volumewidget2.percent+0.02
                        util.spawn_with_shell("pactl set-sink-volume "..pavuSinkN.." -- +2%")
                    end

                end),
            button({ }, 5, function()
                    util.spawn_with_shell("pactl set-sink-volume "..pavuSinkN.." -- -2%")
                    if volumewidget2.percent < 0.02 then volumewidget2.percent=0
                    else volumewidget2.percent=volumewidget2.percent-0.02 end
                end)
        )
    end

    vicious.register(volumewidget2, amixer_volume_int, '$1',5)
    volumewidget2:buttons(btn)
    return volumewidget2
end

return setmetatable(module, { __call = function(_, ...) return new(...) end })
