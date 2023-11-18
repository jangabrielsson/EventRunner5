---@diagnostic disable: need-check-nil
local lib = {}
local fibemu = fibaro.fibemu 
fibaro.debugFlags = fibaro.debugFlags or {}
fibaro.settings = fibaro.settings or {}
local debugFlags = fibaro.debugFlags
fibaro.utils = lib

local function equal(e1,e2)
  if e1==e2 then return true
  else
    if type(e1) ~= 'table' or type(e2) ~= 'table' then return false
    else
      for k1,v1 in pairs(e1) do if e2[k1] == nil or not equal(v1,e2[k1]) then return false end end
      for k2,_  in pairs(e2) do if e1[k2] == nil then return false end end
      return true
    end
  end
end

local function copy(t) if type(t) ~= 'table' then return t end local r = {} for k,v in pairs(t) do r[k] = copy(v) end return r end
local function copyShallow(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
local function maxn(t) local c=0 for _ in pairs(t) do c=c+1 end return c end
local function member(k,tab) for i,v in ipairs(tab) do if equal(v,k) then return i end end return false end
local function map(f,l,s) s = s or 1; local r,m={},maxn(l) for i=s,m do r[#r+1] = f(l[i]) end return r end
local function mapf(f,l,s) s = s or 1; local e=true for i=s,maxn(l) do e = f(l[i]) end return e end
local function delete(k,tab) local i = member(tab,k); if i then table.remove(tab,i) return i end end
local function mapAnd(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) if not e then return false end end return e end 
local function mapOr(f,l,s) s = s or 1; for i=s,table.maxn(l) do local e = f(l[i]) if e then return e end end return false end
local function reduce(f,l) local r = {}; for _,e in ipairs(l) do if f(e) then r[#r+1]=e end end; return r end
local function mapk(f,l) local r={}; for k,v in pairs(l) do r[k]=f(v) end; return r end
local function mapkv(f,l) local r={}; for k,v in pairs(l) do k,v=f(k,v) if k then r[k]=v end end; return r end
local function mapkl(f,l) local r={} for i,j in pairs(l) do r[#r+1]=f(i,j) end return r end

if not table.maxn then table.maxn = maxn end
table.copy,table.copyShallow,table.equal,table.max,table.member,table.map,table.mapf,table.delete = copy,copyShallow,equal,maxn,member,map,mapf,delete
table.mapAnd,table.mapOr,table.reduce,table.mapk,table.mapkv,table.mapkl = mapAnd,mapOr,reduce,mapk,mapkv,mapkl

local fmt = string.format 
local function gensym(s) return (s or "G")..fibaro._orgToString({}):match("%s(.*)") end

local encode
do -- fastEncode
  local fmt = string.format
  local function encTsort(a,b) return a[1] < b[1] end
  local sortKeys = {"type","device","deviceID","id","value","oldValue","val","key","arg","event","events","msg","res"}
  local sortOrder,sortF={},nil
  for i,s in ipairs(sortKeys) do sortOrder[s]="\n"..string.char(i+64).." "..s end
  local function encEsort(a,b)
    a,b=a[1],b[1]; a,b = sortOrder[a] or a, sortOrder[b] or b
    return a < b
  end
  function table.maxn(t) local c=0 for _ in pairs(t) do c=c+1 end return c end
  local encT={}
  encT['nil'] = function(n,out) out[#out+1]='nil' end
  function encT.number(n,out) out[#out+1]=tostring(n) end
  function encT.userdata(u,out) out[#out+1]=tostring(u) end
  function encT.thread(t,out) out[#out+1]=tostring(t) end
  encT['function'] = function(f,out) out[#out+1]=tostring(f) end
  function encT.string(str,out) out[#out+1]='"' out[#out+1]=str out[#out+1]='"' end
  function encT.boolean(b,out) out[#out+1]=b and "true" or "false" end
  function encT.table(t,out)
    local mt = getmetatable(t) if t and t.__tostring then return tostring(t) end
    if next(t)==nil then return "{}" -- Empty table
    elseif t[1]==nil then -- key value table
      local r = {}; for k,v in pairs(t) do r[#r+1]={k,v} end table.sort(r,sortF)
      out[#out+1]='{'
      local e = r[1]
      out[#out+1]=e[1]; out[#out+1]='='; encT[type(e[2])](e[2],out)
      for i=2,table.maxn(r) do local e = r[i]; out[#out+1]=','; out[#out+1]=e[1]; out[#out+1]='='; encT[type(e[2])](e[2],out) end
      out[#out+1]='}'
    else -- array table
      out[#out+1]='['
      encT[type(t[1])](t[1],out)
      for i=2,table.maxn(t) do out[#out+1]=',' encT[type(t[ i])](t[i],out) end
      out[#out+1]=']'
    end
  end
  
  function encode(o,sort)
    local out = {}
    sortF = (not sort) and encEsort or encTsort
    encT[type(o)](o,out)
    return table.concat(out)
  end
  lib.encode = encode
  json.encodeFast = encode
end

local eventMT = { __tostring = function(ev) 
  local s = encode(ev) 
  return fmt("#%s{%s}",ev.type,s:match(",(.*)}") or "") end 
}

local function shallowCopy(t) local r = {}; for k,v in pairs(t) do r[k]=v end; return r end
local EventMT = {
  __tostring = function(ev) 
      local s = encode(ev)
      return fmt("#%s{%s}",ev.type or "unknown",s:match(",(.*)}") or "")
  end,
}

----------- spec format -----------------------------
do
  local function hm(t)
    if t > 3600*100 then return os.date("%H:%M",t)
    else return fmt("%2d:%2d",t//3600,t % 3600 // 60) end
  end
  local function hms(t) 
    if t > 3600*100 then return os.date("%X",t)
    else return fmt("%2d:%2d:%2d",t//3600,t % 3600 // 60,t % 60) end
  end
  
  local function mkTruncer(n,fun,a) return function(s) return fun(s):sub(1,n),a end end
  local function mkSpacer(n,fun,a)
    local e = n < 0 and 1 or 0
    n = math.abs(n)
    return function(s)
      s = fun(s)
      local l = #s
      if l>=n then return s,a
      else return e==1 and (s..string.rep(' ',n-l)) or (string.rep(' ',n-l)..s),a end
    end
  end
  
  local specs = {}
  function specs.s(f) 
    local fun = function(s) return tostring(s),1 end
    local space,trunc = f:match("(-?%d*),?(%d*)")
    if trunc and trunc~="" then fun = mkTruncer(tonumber(trunc),fun,1) end
    if space and space~="" then fun = mkSpacer(tonumber(space),fun,1) end
    return fun
  end
  function specs.d(f) f = "%"..f.."d" return function(s) return fmt(f,s),1 end end
  function specs.f(f) f = "%"..f.."f" return function(s) return fmt(f,s),1 end end
  function specs.x(f) f = "%"..f.."x" return function(s) return fmt(f,s),1 end end
  function specs.o(f) f = "%"..f.."o" return function(s) return fmt(f,s),1 end end
  function specs.t(f)
    local s = f:match(".")
    if s then return function(s) return hms(s),1 end else return function(s) return hm(s),1 end end
  end
  function specs.l(f)
    local fun = function(s)
      local r = {} for _,e in ipairs(s) do r[#r+1]=tostring(e) end
      return table.concat(r,","),1 
    end
    local space,trunc = f:match("(-?%d*),?(%d*)")
    if trunc and trunc~="" then fun = mkTruncer(tonumber(trunc),fun,1) end
    if space and space~="" then fun = mkSpacer(tonumber(space),fun,1) end
    return fun
  end
  function specs.r(f)
    local n,c = f:match("%d*%w?")
    n = tonumber(n) or 80
    c = c~= "" and c or "-"
    return function() return c:rep(n),0 end
  end
  
  local fmtcache = {}
  function string.eformat(fmt,...)
    local frms = fmtcache[fmt]
    if not frms then
      local forms,strs,globs,n = {},{},{},0
      local res,rest = {},""
      fmt = fmt:gsub("(.-)%%([%d%-%.,%w%*]*)([sfdxlotr])",
      function(p,s,f)
        res[#res+1]=p
        local fun = specs[f](s)
        assert(fun,"Bad format specifier")
        res[#res+1]=fun
        return ""
      end)
      if fmt~="" then res[#res+1]=fmt end
      for i,p in ipairs(res) do
        if type(p) == 'string' then
          if p ~= "" then
            n=n+1
            strs[n]=p
          end
        else n=n+1 forms[#forms+1] = {i=n,f=p} end
      end
      frms = {forms=forms,strs=strs,globs=globs}
      fmtcache[fmt]=frms
    end
    local i,n,args,forms,strs,globs = 1,0,{...},frms.forms,frms.strs,frms.globs
    local stat,res = pcall(function() 
      for _,f in ipairs(forms) do strs[f.i],n = f.f(args[i],i,args) i=i+n end
      local str = table.concat(strs)
      if globs[1] then
        for _,g in ipairs(globs) do str = g(str) end
      end
      return str 
    end)
    if stat then return res
    else error(string.format("Bad argument to string.eformat specifier #%s - '%s'",i,tostring(args[i]))) end
  end
  
  getmetatable("").__idiv = function(str,len) return (#str < len or #str < 4) and str or str:sub(1,len-2)..".." end -- truncate strings
end

----------------------- Net stuff ---------------------------
local function base64encode(data)
  __assert_type(data,"string")
  local bC='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x) 
    local r,b='',x:byte() for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
    return r;
  end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if (#x < 6) then return '' end
    local c=0
    for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
    return bC:sub(c+1,c+1)
  end)..({ '', '==', '=' })[#data%3+1])
end

local function basicAuthorization(user,password) return "Basic "..base64encode(user..":"..password) end

function urlencode(str) -- very useful
  if str then
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w %-%_%.%~])", function(c)
      return ("%%%02X"):format(string.byte(c))
    end)
    str = str:gsub(" ", "%%20")
  end
  return str	
end
local function getIPaddress(name)
  if IPaddress then return IPaddress end
  if fibemu then return fibemu.config.hostIP..":"..fibemu.config.wport
  else
    name = name or ".*"
    local networkdata = api.get("/proxy?url=http://localhost:11112/api/settings/network")
    for n,d in pairs(networkdata.networkConfig or {}) do
      if n:match(name) and d.enabled then IPaddress = d.ipConfig.ip; return IPaddress end
    end
  end
end
fibaro.getIPaddress = getIPaddress

---------------- Debug ---------------------------------------------
function QuickApp:debugf(fmt,...) self:debug(fmt:format(...)) end
function QuickApp:tracef(fmt,...) self:trace(fmt:format(...)) end
function QuickApp:warningf(fmt,...) self:warning(fmt:format(...)) end
function QuickApp:errorf(fmt,...) self:error(fmt:format(...)) end

local timerMT = {
  __tostring = function(t) return fmt("[Timer:%d%s %s]",t.n,t.log or "",os.date('%T %D',t.expires or 0)) end
}

local N,NC = 0,0
local function isTimer(timer) return type(timer)=='table' and timer['%TIMER%'] end
local function makeTimer(ref,log,exp) 
  N=N+1 
  return setmetatable({['%TIMER%']=(ref or 0),n=N,log=type(log)=='string' and " ("..log..")" or nil,expires=exp or 0},timerMT)
end
local function updateTimer(timer,ref) timer['%TIMER%']=ref end
local function getTimer(timer) return timer['%TIMER%'] end

local oldClearTimout,oldSetTimout
clearTimeout,oldClearTimout=function(ref)
  if isTimer(ref) then ref=getTimer(ref) oldClearTimout(ref) end
end,clearTimeout

setTimeout,oldSetTimout=function(f,ms,log)
  local ref,maxt=makeTimer(nil,log,math.floor(os.time()+ms/1000+0.5)),2147483648-1
  local fun = function() -- wrap function to get error messages
    if debugFlags.lateTimer then
      local d = os.time() - ref.expires
      if d > debugFlags.lateTimer then fibaro.warning(__TAG,fmt("Late timer (%ds):%s",d,tostring(ref))) end
    end
    NC = NC-1
    ref.expired = true
    if ref._prehook then ref._prehook() end -- pre and posthooks
    local stat,res = pcall(f)
    if ref._posthook then ref._posthook() end
    if not stat then 
      fibaro.error(__TAG,res)
    end
  end
  NC = NC+1
  if ms > maxt then -- extend timer length > 26 days...
    updateTimer(ref,oldSetTimout(function() updateTimer(ref,getTimer(setTimeout(fun,ms-maxt))) end,maxt))
  else updateTimer(ref,oldSetTimout(fun,math.floor(ms+0.5))) end
  return ref
end,setTimeout

local oldClearInterval,oldSetInterval = clearInterval,setInterval
function setInterval(fun,ms) -- can't manage looong intervals
  return oldSetInterval(function()
    local stat,res = pcall(fun)
    if not stat then 
      fibaro.error(__TAG,res)
    end
  end,math.floor(ms+0.5))
end
fibaro.setTimeout = function(ms,fun) return setTimeout(fun,ms) end
fibaro.clearTimeout = function(ref) return clearTimeout(ref) end

local encode2,decode2 = json.encode,json.decode
function json.decode(...)
  local stat,res = pcall(decode2,...)
  if not stat then error(res,2) else return res end
end
function json.encode(...)
  local stat,res = pcall(encode2,...)
  if not stat then error(res,2) else return res end
end

--------------- Time and Sun calc  functions -----------------------
do
  local function toSeconds(str)
    __assert_type(str,"string" )
    local sun = str:match("(sun%a+)") 
    if sun then return toSeconds(str:gsub(sun,fibaro.getValue(1,sun.."Hour"))) end
    local var = str:match("(%$[A-Za-z]+)") 
    if var then return toSeconds(str:gsub(var,fibaro.getGlobalVariable(var:sub(2)))) end
    local h,m,s,op,off=str:match("(%d%d):(%d%d):?(%d*)([+%-]*)([%d:]*)")
    off = off~="" and (off:find(":") and toSeconds(off) or toSeconds("00:00:"..off)) or 0
    return 3600*h+60*m+(s~="" and s or 0)+((op=='-' or op =='+-') and -1 or 1)*off
  end
  lib.toSeconds = toSeconds
  
  ---@diagnostic disable-next-line: param-type-mismatch
  local function midnight() local t = os.date("*t"); t.hour,t.min,t.sec = 0,0,0; return os.time(t) end
  lib.midnight = midnight
  function lib.getWeekNumber(tm) return tonumber(os.date("%V",tm)) end
  function lib.now() return os.time()-midnight() end  
  
  function lib.between(start,stop,optTime)
    __assert_type(start,"string" )
    __assert_type(stop,"string" )
    start,stop,optTime=toSeconds(start),toSeconds(stop),optTime and toSeconds(optTime) or toSeconds(os.date("%H:%M"))
    stop = stop>=start and stop or stop+24*3600
    optTime = optTime>=start and optTime or optTime+24*3600
    return start <= optTime and optTime <= stop
  end
  function lib.time2str(t) return fmt("%02d:%02d:%02d",math.floor(t/3600),math.floor((t%3600)/60),t%60) end
  
  local function hm2sec(hmstr,ns)
    local offs,sun
    sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
    if sun and (sun == 'sunset' or sun == 'sunrise') then
      if ns then
        local sunrise,sunset = fibaro.utils.sunCalc(os.time()+24*3600)
        hmstr,offs = sun=='sunrise' and sunrise or sunset, tonumber(offs) or 0
      else
        hmstr,offs = fibaro.getValue(1,sun.."Hour"), tonumber(offs) or 0
      end
    end
    local sg,h,m,s = hmstr:match("^(%-?)(%d+):(%d+):?(%d*)")
    if not (h and m) then error(fmt("Bad hm2sec string %s",hmstr)) end
    return (sg == '-' and -1 or 1)*(tonumber(h)*3600+tonumber(m)*60+(tonumber(s) or 0)+(tonumber(offs or 0))*60)
  end
  
  -- toTime("10:00")     -> 10*3600+0*60 secs
  -- toTime("10:00:05")  -> 10*3600+0*60+5*1 secs
  -- toTime("t/10:00")    -> (t)oday at 10:00. midnight+10*3600+0*60 secs
  -- toTime("n/10:00")    -> (n)ext time. today at 10.00AM if called before (or at) 10.00AM else 10:00AM next day
  -- toTime("+/10:00")    -> Plus time. os.time() + 10 hours
  -- toTime("+/00:01:22") -> Plus time. os.time() + 1min and 22sec
  -- toTime("sunset")     -> todays sunset in relative secs since midnight, E.g. sunset="05:10", =>toTime("05:10")
  -- toTime("sunrise")    -> todays sunrise
  -- toTime("sunset+10")  -> todays sunset + 10min. E.g. sunset="05:10", =>toTime("05:10")+10*60
  -- toTime("sunrise-5")  -> todays sunrise - 5min
  -- toTime("t/sunset+10")-> (t)oday at sunset in 'absolute' time. E.g. midnight+toTime("sunset+10")
  
  local function toTime(time)
    if type(time) == 'number' then return time end
    local p = time:sub(1,2)
    if p == '+/' then return hm2sec(time:sub(3))+os.time()
    elseif p == 'n/' then
      local t1,t2 = midnight()+hm2sec(time:sub(3),true),os.time()
      return t1 > t2 and t1 or t1+24*60*60
    elseif p == 't/' then return  hm2sec(time:sub(3))+midnight()
    else return hm2sec(time) end
  end
  lib.toTime,lib.hm2sec = toTime,hm2sec
  
  local function sunturnTime(date, rising, latitude, longitude, zenith, local_offset)
    local rad,deg,floor = math.rad,math.deg,math.floor
    local frac = function(n) return n - floor(n) end
    local cos = function(d) return math.cos(rad(d)) end
    local acos = function(d) return deg(math.acos(d)) end
    local sin = function(d) return math.sin(rad(d)) end
    local asin = function(d) return deg(math.asin(d)) end
    local tan = function(d) return math.tan(rad(d)) end
    local atan = function(d) return deg(math.atan(d)) end
    
    local function day_of_year(date2)
      local n1 = floor(275 * date2.month / 9)
      local n2 = floor((date2.month + 9) / 12)
      local n3 = (1 + floor((date2.year - 4 * floor(date2.year / 4) + 2) / 3))
      return n1 - (n2 * n3) + date2.day - 30
    end
    
    local function fit_into_range(val, min, max)
      local range,count = max - min,nil
      if val < min then count = floor((min - val) / range) + 1; return val + count * range
      elseif val >= max then count = floor((val - max) / range) + 1; return val - count * range
      else return val end
    end
    
    -- Convert the longitude to hour value and calculate an approximate time
    local n,lng_hour,t =  day_of_year(date), longitude / 15,nil
    if rising then t = n + ((6 - lng_hour) / 24) -- Rising time is desired
    else t = n + ((18 - lng_hour) / 24) end -- Setting time is desired
    local M = (0.9856 * t) - 3.289 -- Calculate the Sun^s mean anomaly
    -- Calculate the Sun^s true longitude
    local L = fit_into_range(M + (1.916 * sin(M)) + (0.020 * sin(2 * M)) + 282.634, 0, 360)
    -- Calculate the Sun^s right ascension
    local RA = fit_into_range(atan(0.91764 * tan(L)), 0, 360)
    -- Right ascension value needs to be in the same quadrant as L
    local Lquadrant = floor(L / 90) * 90
    local RAquadrant = floor(RA / 90) * 90
    RA = RA + Lquadrant - RAquadrant; RA = RA / 15 -- Right ascension value needs to be converted into hours
    local sinDec = 0.39782 * sin(L) -- Calculate the Sun's declination
    local cosDec = cos(asin(sinDec))
    local cosH = (cos(zenith) - (sinDec * sin(latitude))) / (cosDec * cos(latitude)) -- Calculate the Sun^s local hour angle
    if rising and cosH > 1 then return -1 --"N/R" -- The sun never rises on this location on the specified date
    elseif cosH < -1 then return -1 end --"N/S" end -- The sun never sets on this location on the specified date
    
    local H -- Finish calculating H and convert into hours
    if rising then H = 360 - acos(cosH)
    else H = acos(cosH) end
    H = H / 15
    local T = H + RA - (0.06571 * t) - 6.622 -- Calculate local mean time of rising/setting
    local UT = fit_into_range(T - lng_hour, 0, 24) -- Adjust back to UTC
    local LT = UT + local_offset -- Convert UT value to local time zone of latitude/longitude
    ---@diagnostic disable-next-line: missing-fields
    return os.time({day = date.day,month = date.month,year = date.year,hour = floor(LT),min = math.modf(frac(LT) * 60)})
  end
  
  ---@diagnostic disable-next-line: param-type-mismatch
  local function getTimezone() local now = os.time() return os.difftime(now, os.time(os.date("!*t", now))) end
  
  function lib.sunCalc(time)
    local hc3Location = api.get("/settings/location")
    local lat = hc3Location.latitude or 0
    local lon = hc3Location.longitude or 0
    local utc = getTimezone() / 3600
    local zenith,zenith_twilight = 90.83, 96.0 -- sunset/sunrise 90°50′, civil twilight 96°0′
    
    local date = os.date("*t",time or os.time())
    if date.isdst then utc = utc + 1 end
    local rise_time = os.date("*t", sunturnTime(date, true, lat, lon, zenith, utc))
    local set_time = os.date("*t", sunturnTime(date, false, lat, lon, zenith, utc))
    local rise_time_t = os.date("*t", sunturnTime(date, true, lat, lon, zenith_twilight, utc))
    local set_time_t = os.date("*t", sunturnTime(date, false, lat, lon, zenith_twilight, utc))
    local sunrise = fmt("%.2d:%.2d", rise_time.hour, rise_time.min)
    local sunset = fmt("%.2d:%.2d", set_time.hour, set_time.min)
    local sunrise_t = fmt("%.2d:%.2d", rise_time_t.hour, rise_time_t.min)
    local sunset_t = fmt("%.2d:%.2d", set_time_t.hour, set_time_t.min)
    return sunrise, sunset, sunrise_t, sunset_t
  end

  local function dateTest(dateStr0)
    local days = {sun=1,mon=2,tue=3,wed=4,thu=5,fri=6,sat=7}
    local months = {jan=1,feb=2,mar=3,apr=4,may=5,jun=6,jul=7,aug=8,sep=9,oct=10,nov=11,dec=12}
    local last,month = {31,28,31,30,31,30,31,31,30,31,30,31},nil

    local function seq2map(seq) local s = {} for _,v in ipairs(seq) do s[v] = true end return s; end

    local function flatten(seq,res) -- flattens a table of tables
      res = res or {}
      if type(seq) == 'table' then for _,v1 in ipairs(seq) do flatten(v1,res) end else res[#res+1] = seq end
      return res
    end

    local function _assert(test,msg,...) if not test then error(fmt(msg,...),3) end end

    local function expandDate(w1,md)
      local function resolve(id)
        local res
        if id == 'last' then month = md res=last[md] 
        elseif id == 'lastw' then month = md res=last[md]-6 
        else res= type(id) == 'number' and id or days[id] or months[id] or tonumber(id) end
        _assert(res,"Bad date specifier '%s'",id) return res
      end
      local step = 1
      local w,m = w1[1],w1[2]
      local start,stop = w:match("(%w+)%p(%w+)")
      if (start == nil) then return resolve(w) end
      start,stop = resolve(start), resolve(stop)
      local res,res2 = {},{}
      if w:find("/") then
        if not w:find("-") then -- 10/2
          step=stop; stop = m.max
        else step=(w:match("/(%d+)")) end
      end
      step = tonumber(step)
      _assert(start>=m.min and start<=m.max and stop>=m.min and stop<=m.max,"illegal date intervall")
      while (start ~= stop) do -- 10-2
        res[#res+1] = start
        start = start+1; if start>m.max then start=m.min end  
      end
      res[#res+1] = stop
      if step > 1 then for i=1,#res,step do res2[#res2+1]=res[i] end; res=res2 end
      return res
    end

    local function parseDateStr(dateStr) --,last)
      local map = table.map
      local seq = string.split(dateStr," ")   -- min,hour,day,month,wday
      local lim = {{min=0,max=59},{min=0,max=23},{min=1,max=31},{min=1,max=12},{min=1,max=7},{min=2000,max=3000}}
      for i=1,6 do if seq[i]=='*' or seq[i]==nil then seq[i]=tostring(lim[i].min).."-"..lim[i].max end end
      seq = map(function(w) return string.split(w,",") end, seq)   -- split sequences "3,4"
      local month0 = os.date("*t",os.time()).month
      seq = map(function(t) local m = table.remove(lim,1);
          return flatten(map(function (g) return expandDate({g,m},month0) end, t))
        end, seq) -- expand intervalls "3-5"
      return map(seq2map,seq)
    end
    local sun,offs,day,sunPatch = dateStr0:match("^(sun%a+) ([%+%-]?%d+)")
    if sun then
      sun = sun.."Hour"
      dateStr0=dateStr0:gsub("sun%a+ [%+%-]?%d+","0 0")
      sunPatch=function(dateSeq)
        local h,m = (fibaro.getValue(1,sun)):match("(%d%d):(%d%d)")
        dateSeq[1]={[(tonumber(h)*60+tonumber(m)+tonumber(offs))%60]=true}
        dateSeq[2]={[math.floor((tonumber(h)*60+tonumber(m)+tonumber(offs))/60)]=true}
      end
    end
    local dateSeq = parseDateStr(dateStr0)
    return function() -- Pretty efficient way of testing dates...
      local t = os.date("*t",os.time())
      if month and month~=t.month then dateSeq=parseDateStr(dateStr0) end -- Recalculate 'last' every month
      if sunPatch and (month and month~=t.month or day~=t.day) then sunPatch(dateSeq) day=t.day end -- Recalculate sunset/sunrise
      return
      dateSeq[1][t.min] and    -- min     0-59
      dateSeq[2][t.hour] and   -- hour    0-23
      dateSeq[3][t.day] and    -- day     1-31
      dateSeq[4][t.month] and  -- month   1-12
      dateSeq[5][t.wday] or false      -- weekday 1-7, 1=sun, 7=sat
    end
  end

  fibaro.dateTest = dateTest
end 

--------------- Event engine -------------------
local function createEventEngine()
  local self = {}
  local HANDLER = '%EVENTHANDLER%'
  local BREAK = '%BREAK%'
  self.BREAK = BREAK
  local handlers = {}
  local function isEvent(e) return type(e) == 'table' and type(e.type)=='string' end

  local function coerce(x,y) local x1 = tonumber(x) if x1 then return x1,tonumber(y) else return x,y end end
  local constraints = {}
  constraints['=='] = function(val) return function(x) x,val=coerce(x,val) return x == val end end
  constraints['<>'] = function(val) return function(x) return tostring(x):match(val) end end
  constraints['>='] = function(val) return function(x) x,val=coerce(x,val) return x >= val end end
  constraints['<='] = function(val) return function(x) x,val=coerce(x,val) return x <= val end end
  constraints['>'] = function(val) return function(x) x,val=coerce(x,val) return x > val end end
  constraints['<'] = function(val) return function(x) x,val=coerce(x,val) return x < val end end
  constraints['~='] = function(val) return function(x) x,val=coerce(x,val) return x ~= val end end
  constraints[''] = function(_) return function(x) return x ~= nil end end
  
  local function compilePattern2(pattern)
    if type(pattern) == 'table' then
      if pattern._var_ then return end
      for k,v in pairs(pattern) do
        if type(v) == 'string' and v:sub(1,1) == '$' then
          local var,op,val = v:match("$([%w_]*)([<>=~]*)(.*)")
          var = var =="" and "_" or var
          local c = constraints[op](tonumber(val) or val)
          pattern[k] = {_var_=var, _constr=c, _str=v}
        else compilePattern2(v) end
      end
    end
    return pattern
  end
  
  local function compilePattern(pattern)
    pattern = compilePattern2(copy(pattern))
    if pattern.type and type(pattern.id)=='table' and not pattern.id._constr then
      local m = {}; for _,id in ipairs(pattern.id) do m[id]=true end
      pattern.id = {_var_='_', _constr=function(val) return m[val] end, _str=pattern.id}
    end
    return pattern
  end
  self.compilePattern = compilePattern

  local function match(pattern0, expr0)
    local matches = {}
    local function unify(pattern,expr)
      if pattern == expr then return true
      elseif type(pattern) == 'table' then
        if pattern._var_ then
          local var, constr = pattern._var_, pattern._constr
          if var == '_' then return constr(expr)
          elseif matches[var] then return constr(expr) and unify(matches[var],expr) -- Hmm, equal?
          else matches[var] = expr return constr(expr) end
        end
        if type(expr) ~= "table" then return false end
        for k,v in pairs(pattern) do if not unify(v,expr[k]) then return false end end
        return true
      else return false end
    end
    return unify(pattern0,expr0) and matches or false
  end
  self.match = match

  local function invokeHandler(env)
    local t = os.time()
    env.last,env.rule.time = t-(env.rule.time or 0),t
    local status, res = pcall(env.rule.action,env) -- call the associated action
    if not status then
      --if type(res)=='string' and not debugFlags.extendedErrors then res = res:gsub("(%[.-%]:%d+:)","") end
      --fibaro.errorf(nil,"in %s: %s",env.rule.doc,res)
      env.rule._disabled = true -- disable rule to not generate more errors
      --em.stats.errors=(em.stats.errors or 0)+1
    else return res end
  end
  
  local toTime = self.toTime 
  function self.post(ev,t,log,hook,customLog)
    local now,isEv = os.time(),isEvent(ev)
    t = type(t)=='string' and toTime(t) or t or 0
    if t < 0 then return elseif t < now then t = t+now end
    if debugFlags.post and (type(ev)=='function' or not ev._sh) then
      if isEv and not getmetatable(ev) then setmetatable(ev,EventMT) end
      (customLog or fibaro.trace)(__TAG,fmt("Posting %s at %s %s",tostring(ev),os.date("%c",t),type(log)=='string' and ("("..log..")") or "")) 
    end
    if type(ev) == 'function' then
      return setTimeout(function() ev(ev) end,1000*(t-now),log),t
    elseif isEv then
      if not getmetatable(ev) then setmetatable(ev,EventMT) end
      return setTimeout(function() if hook then hook() end self.handleEvent(ev) end,1000*(t-now),log),t
    else
      error("post(...) not event or fun;"..tostring(ev))
    end
  end
  
  function self.cancel(id) clearTimeout(id) end
  
  local toHash,fromHash={},{}
  fromHash['device'] = function(e) return {"device"..e.id..e.property,"device"..e.id,"device"..e.property,"device"} end
  fromHash['global-variable'] = function(e) return {'global-variable'..e.name,'global-variable'} end
  fromHash['quickvar'] = function(e) return {"quickvar"..e.id..e.name,"quickvar"..e.id,"quickvar"..e.name,"quickvar"} end
  fromHash['profile'] = function(e) return {'profile'..e.property,'profile'} end
  fromHash['weather'] = function(e) return {'weather'..e.property,'weather'} end
  fromHash['custom-event'] = function(e) return {'custom-event'..e.name,'custom-event'} end
  fromHash['deviceEvent'] = function(e) return {"deviceEvent"..e.id..e.value,"deviceEvent"..e.id,"deviceEvent"..e.value,"deviceEvent"} end
  fromHash['sceneEvent'] = function(e) return {"sceneEvent"..e.id..e.value,"sceneEvent"..e.id,"sceneEvent"..e.value,"sceneEvent"} end
  toHash['device'] = function(e) return "device"..(e.id or "")..(e.property or "") end   
  
  toHash['global-variable'] = function(e) return 'global-variable'..(e.name or "") end
  toHash['quickvar'] = function(e) return 'quickvar'..(e.id or "")..(e.name or "") end
  toHash['profile'] = function(e) return 'profile'..(e.property or "") end
  toHash['weather'] = function(e) return 'weather'..(e.property or "") end
  toHash['custom-event'] = function(e) return 'custom-event'..(e.name or "") end
  toHash['deviceEvent'] = function(e) return 'deviceEvent'..(e.id or "")..(e.value or "") end
  toHash['sceneEvent'] = function(e) return 'sceneEvent'..(e.id or "")..(e.value or "") end
  
  
  local MTrule = { __tostring = function(self) return fmt("SourceTriggerSub:%s",self.event.type) end }
  function self.addEventHandler(pattern,fun,doc)
    if not isEvent(pattern) then error("Bad event pattern, needs .type field") end
    assert(type(fun)=='func'..'tion', "Second argument must be Lua func")
    local cpattern = compilePattern(pattern)
    local hashKey = toHash[pattern.type] and toHash[pattern.type](pattern) or pattern.type
    handlers[hashKey] = handlers[hashKey] or {}
    local rules = handlers[hashKey]
    local rule,fn = {[HANDLER]=cpattern, event=pattern, action=fun, doc=doc}, true
    for _,rs in ipairs(rules) do -- Collect handlers with identical patterns. {{e1,e2,e3},{e1,e2,e3}}
      if equal(cpattern,rs[1].event) then 
        rs[#rs+1] = rule
        fn = false break 
      end
    end
    if fn then rules[#rules+1] = {rule} end
    rule.enable = function() rule._disabled = nil return rule end
    rule.disable = function() rule._disabled = true return rule end
    return rule
  end
  
  function self.removeEventHandler(rule)
    local pattern,fun = rule.event,rule.action
    local hashKey = toHash[pattern.type] and toHash[pattern.type](pattern) or pattern.type
    local rules,i,j= handlers[hashKey] or {},1,1
    while j <= #rules do
      local rs = rules[j]
      while i <= #rs do
        if rs[i].action==fun then
          table.remove(rs,i)
        else i=i+i end
      end
      if #rs==0 then table.remove(rules,j) else j=j+1 end
    end
  end
  
  local callbacks = {}
  function self.registerCallback(fun) callbacks[#callbacks+1] = fun end
  
  function self.handleEvent(ev,firingTime)
    for _,cb in ipairs(callbacks) do cb(ev) end
    
    local hasKeys = fromHash[ev.type] and fromHash[ev.type](ev) or {ev.type}
    for _,hashKey in ipairs(hasKeys) do
      for _,rules in ipairs(handlers[hashKey] or {}) do -- Check all rules of 'type'
        local i,m=1,nil
        for j=1,#rules do
          if not rules[j]._disabled then    -- find first enabled rule, among rules with same head
            m = match(rules[i][HANDLER],ev) -- and match against that rule
            break
          end
        end
        if m then                           -- we have a match
          for j=i,#rules do                 -- executes all rules with same head
            local rule=rules[j]
            if not rule._disabled then 
              if invokeHandler({event = ev, time = firingTime, p=m, rule=rule}) == BREAK then return end
            end
          end
        end
      end
    end
  end

  -- This can be used to "post" an event into this QA... Ex. fibaro.call(ID,'RECIEVE_EVENT',{type='myEvent'})
  function QuickApp.RECIEVE_EVENT(_,ev)
    assert(isEvent(ev),"Bad argument to remote event")
    local time = ev.ev._time
    ev,ev.ev._time = ev.ev,nil
    setmetatable(ev,EventMT)
    if time and time+5 < os.time() then fibaro.warning(__TAG,fmt("Slow events %s, %ss",tostring(ev),os.time()-time)) end
    self.post(ev)
  end

  function self.postRemote(uuid,id,ev)
    if ev == nil then
      id,ev = uuid,id
      assert(tonumber(id) and isEvent(ev),"Bad argument to postRemote")
      ev._from,ev._time = plugin.mainDeviceId,os.time()
      fibaro.call(id,'RECIEVE_EVENT',{type='EVENT',ev=ev}) -- We need this as the system converts "99" to 99 and other "helpful" conversions
    else
      -- post to slave box in the future
    end
  end

  return self
end -- createEventEngine

local function quickVarEvent(d,_,post)
  local old={}; for _,v in ipairs(d.oldValue) do old[v.name] = v.value end 
  for _,v in ipairs(d.newValue) do
    if not equal(v.value,old[v.name]) then
      post({type='quickvar', id=d.id, name=v.name, value=v.value, old=old[v.name]})
    end
  end
end

-- There are more, but these are what I seen so far...

local EventTypes = { 
  AlarmPartitionArmedEvent = function(d,_,post) post({type='alarm', property='armed', id = d.partitionId, value=d.armed}) end,
  AlarmPartitionBreachedEvent = function(d,_,post) post({type='alarm', property='breached', id = d.partitionId, value=d.breached}) end,
  AlarmPartitionModifiedEvent = function(d,_,post) print(json.encode(d)) end,
  HomeArmStateChangedEvent = function(d,_,post) post({type='alarm', property='homeArmed', value=d.newValue}) end,
  HomeDisarmStateChangedEvent = function(d,_,post) post({type='alarm', property='homeArmed', value=not d.newValue}) end,
  HomeBreachedEvent = function(d,_,post) post({type='alarm', property='homeBreached', value=d.breached}) end,
  WeatherChangedEvent = function(d,_,post) post({type='weather',property=d.change, value=d.newValue, old=d.oldValue}) end,
  GlobalVariableChangedEvent = function(d,_,post) post({type='global-variable', name=d.variableName, value=d.newValue, old=d.oldValue}) end,
  GlobalVariableAddedEvent = function(d,_,post) post({type='global-variable', name=d.variableName, value=d.value, old=nil}) end,
  DevicePropertyUpdatedEvent = function(d,_,post)
    if d.property=='quickAppVariables' then quickVarEvent(d,_,post)
    else
      post({type='device', id=d.id, property=d.property, value=d.newValue, old=d.oldValue})
    end
  end,
  CentralSceneEvent = function(d,_,post) 
    d.id,d.icon = d.id or d.deviceId,nil
    post({type='device', property='centralSceneEvent', id=d.id, value={keyId=d.keyId, keyAttribute=d.keyAttribute}}) 
  end,
  SceneActivationEvent = function(d,_,post) 
    d.id = d.id or d.deviceId
    post({type='device', property='sceneActivationEvent', id=d.id, value={sceneId=d.sceneId}})     
  end,
  AccessControlEvent = function(d,_,post) 
    post({type='device', property='accessControlEvent', id=d.id, value=d}) 
  end,
  CustomEvent = function(d,_,post) 
    local value = api.get("/customEvents/"..d.name) 
    post({type='custom-event', name=d.name, value=value and value.userDescription}) 
  end,
  PluginChangedViewEvent = function(d,_,post) post({type='PluginChangedViewEvent', value=d}) end,
  WizardStepStateChangedEvent = function(d,_,post) post({type='WizardStepStateChangedEvent', value=d})  end,
  UpdateReadyEvent = function(d,_,post) post({type='updateReadyEvent', value=d}) end,
  DeviceRemovedEvent = function(d,_,post)  post({type='deviceEvent', id=d.id, value='removed'}) end,
  DeviceChangedRoomEvent = function(d,_,post)  post({type='deviceEvent', id=d.id, value='changedRoom'}) end,
  DeviceCreatedEvent = function(d,_,post)  post({type='deviceEvent', id=d.id, value='created'}) end,
  DeviceModifiedEvent = function(d,_,post) post({type='deviceEvent', id=d.id, value='modified'}) end,
  PluginProcessCrashedEvent = function(d,_,post) post({type='deviceEvent', id=d.deviceId, value='crashed', error=d.error}) end,
  SceneStartedEvent = function(d,_,post)   post({type='sceneEvent', id=d.id, value='started'}) end,
  SceneFinishedEvent = function(d,_,post)  post({type='sceneEvent', id=d.id, value='finished'})end,
  SceneRunningInstancesEvent = function(d,_,post) post({type='sceneEvent', id=d.id, value='instance', instance=d}) end,
  SceneRemovedEvent = function(d,_,post)  post({type='sceneEvent', id=d.id, value='removed'}) end,
  SceneModifiedEvent = function(d,_,post)  post({type='sceneEvent', id=d.id, value='modified'}) end,
  SceneCreatedEvent = function(d,_,post)  post({type='sceneEvent', id=d.id, value='created'}) end,
  OnlineStatusUpdatedEvent = function(d,_,post) post({type='onlineEvent', value=d.online}) end,
  ActiveProfileChangedEvent = function(d,_,post) 
    post({type='profile',property='activeProfile',value=d.newActiveProfile, old=d.oldActiveProfile}) 
  end,
  ClimateZoneChangedEvent = function(d,_,post) --ClimateZoneChangedEvent
    if d.changes and type(d.changes)=='table' then
      for _,c in ipairs(d.changes) do
        c.type,c.id='ClimateZone',d.id
        post(c)
      end
    end
  end,
  ClimateZoneSetpointChangedEvent = function(d,_,post) d.type = 'ClimateZoneSetpoint' post(d,_,post) end,
  NotificationCreatedEvent = function(d,_,post) post({type='notification', id=d.id, value='created'}) end,
  NotificationRemovedEvent = function(d,_,post) post({type='notification', id=d.id, value='removed'}) end,
  NotificationUpdatedEvent = function(d,_,post) post({type='notification', id=d.id, value='updated'}) end,
  RoomCreatedEvent = function(d,_,post) post({type='room', id=d.id, value='created'}) end,
  RoomRemovedEvent = function(d,_,post) post({type='room', id=d.id, value='removed'}) end,
  RoomModifiedEvent = function(d,_,post) post({type='room', id=d.id, value='modified'}) end,
  SectionCreatedEvent = function(d,_,post) post({type='section', id=d.id, value='created'}) end,
  SectionRemovedEvent = function(d,_,post) post({type='section', id=d.id, value='removed'}) end,
  SectionModifiedEvent = function(d,_,post) post({type='section', id=d.id, value='modified'}) end,
  QuickAppFilesChangedEvent = function(_) end,
  ZwaveDeviceParametersChangedEvent = function(_) end,
  ZwaveNodeAddedEvent = function(_) end,
  RefreshRequiredEvent = function(_) end,
  DeviceFirmwareUpdateEvent = function(_) end,
  GeofenceEvent = function(d,_,post) post({type='location',id=d.userId,property=d.locationId,value=d.geofenceAction,timestamp=d.timestamp}) end,
  DeviceActionRanEvent = function(d,e,post)
    if e.sourceType=='user' then  
      post({type='user',id=e.sourceId,value='action',data=d})
    elseif e.sourceType=='system' then 
      post({type='system',value='action',data=d})
    end
  end,
}

local aEventEngine = nil
class 'SourceTrigger'
function SourceTrigger:__init()
  self.refresh = RefreshStateSubscriber()
  self.eventEngine = createEventEngine()
  aEventEngine = self.eventEngine
  local function post(event,firingTime)
    setmetatable(event,eventMT)
    if debugFlags.sourceTrigger then fibaro.trace(__TAG,fmt("SourceTrigger: %s",tostring(event) // fibaro.settings.truncLog)) end
    self.eventEngine.handleEvent(event,firingTime) 
  end
  local function filter(ev) 
    if debugFlags.refreshEvents then 
      fibaro.trace(__TAG,fmt("RefreshEvent: %s:%s",ev.type,encode(ev.data)) // fibaro.settings.truncLog) 
    end
    return true 
  end
  local function handler(ev) 
    if EventTypes[ev.type] then 
      EventTypes[ev.type](ev.data,ev,post) 
    end 
  end
  self.refresh:subscribe(filter,handler)
end
function SourceTrigger:run() self.refresh:run() end
function SourceTrigger:subscribe(event,handler) --> subscription
  return self.eventEngine.addEventHandler(event,handler)
end
function SourceTrigger:unsubscribe(subscription)
  self.eventEngine.removeEventHandler(subscription)
end
function SourceTrigger:enableSubscription(subscription)
  subscription.enable()
end
function SourceTrigger:disableSubscription(subscription)
  subscription.disable()
end
function SourceTrigger:post(event,time,log,hook,customLog)
  return self.eventEngine.post(event,time,log,hook,customLog)
end
function SourceTrigger:registerCallback(fun)
  return self.eventEngine.registerCallback(fun)
end
function SourceTrigger:cancel(ref)
  return self.eventEngine.cancel(ref)
end
function SourceTrigger:postRemote(id,event)
  return self.eventEngine.postRemote(id,event)
end

--------------------- Pub/Sub ---------------------
do
  local debugFlags = fibaro.debugFlags
  local SUB_VAR = "TPUBSUB"
  local idSubs = {}
  local function DEBUG(...) if debugFlags.pubsub then fibaro.debug(__TAG,fmt(...)) end end
  local inited,initPubSub,match,compile
  local member,equal,copy = table.member,table.equal,table.copy
  
  function fibaro.publish(event)
    if not inited then initPubSub(quickApp) end
    assert(type(event)=='table' and event.type,"Not an event")
    local subs = idSubs[event.type] or {}
    for _,e in ipairs(subs) do
      if match(e.pattern,event) then
        for id,_ in pairs(e.ids) do 
          DEBUG("Sending sub QA:%s",id)
          fibaro.call(id,"SUBSCRIPTION",event)
        end
      end
    end
  end
  
  function fibaro.subscribe(events,handler)
    if not inited then initPubSub(quickApp) end
    if not events[1] then events = {events} end
    local subs = quickApp:getVariable(SUB_VAR)
    if subs == "" then subs = {} end
    for _,e in ipairs(events) do
      assert(type(e)=='table' and e.type,"Not an event")
      if not member(e,subs) then subs[#subs+1]=e end
    end
    DEBUG("Setting subscription")
    quickApp:setVariable(SUB_VAR,subs)
    if handler then
      fibaro.event(events,handler)
    end
  end
  
  --  idSubs = {
  --    <type> = { { ids = {... }, event=..., pattern = ... }, ... }
  --  }
  
  function match(...) return aEventEngine.match(...) end
  function compile(...) return aEventEngine.compile(...) end
  
  function QuickApp.SUBSCRIPTION(_,e)
    fibaro.post(e)
  end
  
  local function updateSubscriber(id,events)
    if not idSubs[id] then DEBUG("New subscriber, QA:%s",id) end
    for _,ev in ipairs(events) do
      local subs = idSubs[ev.type] or {}
      for _,s in ipairs(subs) do s.ids[id]=nil end
    end
    for _,ev in ipairs(events) do
      local subs = idSubs[ev.type]
      if subs == nil then
        subs = {}
        idSubs[ev.type]=subs
      end
      for _,e in ipairs(subs) do
        if equal(ev,e.event) then
          e.ids[id]=true
          goto nxt
        end
      end
      subs[#subs+1] = { ids={[id]=true}, event=copy(ev), pattern=compile(ev) }
      ::nxt::
    end
  end
  
  local function checkVars(id,vars)
    for _,var in ipairs(vars or {}) do 
      if var.name==SUB_VAR then return updateSubscriber(id,var.value) end
    end
  end
  
  function initPubSub(quickApp)
    -- At startup, check all QAs for subscriptions
    for _,d in ipairs(api.get("/devices?interface=quickApp") or {}) do
      checkVars(d.id,d.properties.quickAppVariables)
    end
    
    fibaro.event({type='quickvar',name=SUB_VAR},            -- If some QA changes subscription
    function(env) 
      local id = env.event.id
      DEBUG("QA:%s updated quickvar sub",id)
      updateSubscriber(id,env.event.value)                  -- update
    end) 
    
    fibaro.event({type='deviceEvent',value='removed'},      -- If some QA is removed
    function(env) 
      local id = env.event.id
      if id ~= quickApp.id then
        DEBUG("QA:%s removed",id)
        updateSubscriber(env.event.id,{})                   -- update
      end
    end)
    
    fibaro.event({
      {type='deviceEvent',value='created'},                 -- If some QA is added or modified
      {type='deviceEvent',value='modified'}
    },
    function(env)                                           -- update
      local id = env.event.id
      if id ~= quickApp.id then
        DEBUG("QA:%s created/modified",id)
        checkVars(id,api.get("/devices/"..id).properties.quickAppVariables)
      end
    end)
  end
end

----------- QuickApp Startup -----------
local _init,_onInit = QuickApp.__init,nil

function QuickApp:setVersion(model,serial,version)
  local m = model..":"..serial.."/"..version
  if __fibaro_get_device_property(self.id,'model') ~= m then
    quickApp:updateProperty('model',m) 
  end
end
local function initQA(selfv)
  local dev = __fibaro_get_device(selfv.id)
  if not dev.enabled then
    if fibaro.__disabled then pcall(fibaro.__disabled,selfv) end -- Hook if you want to do something when your QA is disabled
    selfv:debug("QA ",selfv.name," disabled")
  else
    quickApp = selfv
    if _onInit then _onInit(selfv) end
  end
end

function QuickApp.__init(self,...) -- We hijack the __init methods so we can control users :onInit() method
  _onInit = self.onInit
  self.onInit = initQA
  _init(self,...)
end

------------- Exports --------------
fibaro.toTime,fibaro.midnight,fibaro.getWeekNumber,fibaro.now = lib.toTime,lib.midnight,lib.getWeekNumber,lib.now