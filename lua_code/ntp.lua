local print, string, unpack = print, string, unpack
local sntp_sync = sntp.sync
local rtctime_epoch2cal, rtctime_get = rtctime.epoch2cal, rtctime.get
local string_format = string.format

return({
    tz=0,
    
    syncdns=function(self, cb, fail)
        sntp_sync({"0.cz.pool.ntp.org", "1.cz.pool.ntp.org", "2.cz.pool.ntp.org"},
            function (ts)
                self.tz = 3600 -- CET
                if self:dst(ts) then
                    self.tz = self.tz + 3600
                    print("Daylight saving +1h")
                end -- adjust for daylight saving
                print("Time updated: "..self:format())
                if cb then cb(ts) end
            end, function ()
                print("Time update fail!")
                if fail then fail() end
            end)
    end,
   
    ts2gmt=function(self, ts)
        local tm = rtctime_epoch2cal(ts)
        return {tm["year"], tm["mon"], tm["day"], tm["hour"], tm["min"], tm["sec"]}
    end,
    
    time=function(self)
        return rtctime_get() + self.tz
    end,
    
    format=function(self, ts)
        if not ts then 
            ts=rtctime_get() + self.tz
        end
        local dt=self:ts2gmt(ts)
        return string.format("%04u/%01u/%01u %02u:%02u:%02u",unpack(dt))
    end,

    dst=function(self, ts)
        if not ts then ts=self:time() end
        local tm = rtctime_epoch2cal(ts)
        local dt = {tm["year"], tm["mon"], tm["day"], tm["hour"], tm["min"], tm["sec"]}
        
        local dow = (tm["wday"]+6) % 7
        print("day of week: "..dow)

        local pS = dt[3] - dow --previousSunday 
        --print("previous sunday: "..pS)

        if (dt[2] < 3 or dt[2] > 10) then return false end
        if (dt[2] > 3 and dt[2] < 10) then return true end

        if (dt[2] == 3) then return pS>=25 end
        if (dt[2] == 10) then return pS<25 end
    end
})
