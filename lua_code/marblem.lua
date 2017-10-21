local n=require("ntp")

local PIN = 3
local speed = 1023

local pwm_setup, pwm_start, pwm_stop, pwm_setduty = pwm.setup, pwm.start, pwm.stop, pwm.setduty
local tmr_alarm, tmr_unregister, tmr_ALARM_SINGLE, tmr_ALARM_AUTO, tmr_create = tmr.alarm, tmr.unregister, tmr.ALARM_SINGLE, tmr.ALARM_AUTO, tmr.create
local string_find, string_gmatch, string_format, string_sub, string_gsub = string.find, string.gmatch, string.format, string.sub, string.gsub
local gpio_mode, gpio_serout, gpio_write, gpio_HIGH, gpio_LOW, gpio_OUTPUT = gpio.mode, gpio.serout, gpio.write, gpio.HIGH, gpio.LOW, gpio.OUTPUT

local tmr_stop = tmr_create()
local tmr_tug = tmr_create()
local tmr_sync = tmr_create()

local last_seen = 0

gpio_mode(PIN, gpio_OUTPUT)
gpio_write(PIN, gpio_LOW)

function turn(time, duty)
  duty = duty or speed
  time = time or 1000
  pwm_setup(PIN, 2000, 1023)
  pwm_start(PIN)
  tmr_alarm(tmr_tug, 100, tmr_ALARM_SINGLE, function() return pwm_setduty(PIN, duty) end)
  tmr_alarm(tmr_stop, time, tmr_ALARM_SINGLE, function() return pwm_stop(PIN) end)
end

function timeSync()
	n:syncdns(function () return tmr_alarm(tmr_sync, 90*60*1000, tmr_ALARM_AUTO, timeSync) end,
		function() return tmr_alarm(tmr_sync, 10*1000, tmr_ALARM_SINGLE, timeSync) end)
end
timeSync()

function ping()
  print("time: ", n:format(), n:format(last_seen))
  local cnt = 1
  net_info.ping("brick.lan", cnt, function (b, ip, sq, ttl, tm) 
    print(string.format("%d bytes from %s, icmp_seq=%d ttl=%d time=%dms", b, ip, sq, ttl, tm)) 
    cnt = cnt - 1
    if b > 0 then last_seen = n:time() end
  end)
end
cron.schedule("*/2 * * * *", ping)

function cronhandler(e)
  local T=n:time()
  local gmt = n:ts2gmt(T)
  print("time: ", n:format(T), n:format(last_seen))
  local hour, minute = gmt[4], gmt[5]
  if (T - last_seen < 3600) and ((hour >= 7 and hour <=23) or (hour == 0 and minute == 0)) then
    if minute == 0 then -- full hour
      --(hour - 1) % 12 + 1
      turn(5000)
    else
      turn(500 * minute / 15)
    end
  end
end
cron.schedule("*/15 * * * *", cronhandler)

srv=net.createServer(net.TCP)
srv:listen(80,function(conn)
  conn:on("receive", function(client, request)
    local _, _, method, path, vars = string_find(request, "([A-Z]+) (.+)?(.+) HTTP")
    if(method == nil)then
        _, _, method, path = string_find(request, "([A-Z]+) (.+) HTTP")
    end
    print("request: ", method, path, vars)
    path = string_sub(path, 2) -- remove first char, i.e. "/"
    local index = (path == "")
    path = index and "index.html" or path
    local fd = file.open(path, "r")
    if not fd then 
        client:send("HTTP/1.0 404 Not Found\r\n\r\n404 Not Found\r\n") 
        return
    end
    if index then
      local _GET = {}
      if (vars ~= nil)then
          for k, v in string_gmatch(vars, "(%w+)=(%w+)&*") do
              _GET[k] = v
          end
      end
      local _GET_time, _GET_speed = _GET.time, _GET.speed
      _GET = nil
      if(_GET_time and _GET_speed) then
        print("turn: ", _GET_speed, _GET_time)
        turn(_GET_time * 1000, _GET_speed)
      end

      local line, content = "", ""
      while line do
          line = string_gsub(line, "$TIME", _GET_time or 5)
          line = string_gsub(line, "$SPEED", _GET_speed or speed)
          content = content .. line
          line = fd:readline()
      end
      fd:close()
      if content then 
        client:send(content, function (c) 
          c:close() 
          c:on("sent", nil)
        end) 
      end
    else
      local function sendfile()
        local line=fd:read(1024)
        if line then
          client:send(line, sendfile)
        else
          fd:close()
          client:close()
          client:on("sent", nil)
        end
      end
      sendfile()
    end
  end)
end)
