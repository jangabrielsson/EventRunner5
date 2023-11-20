fibaro.__ER  = fibaro.__ER or { modules={} }

function fibaro.__ER.modules.utilities(ER)
  
  ER.utilities = {}
  local Utils = ER.utilities
  local extraSetups = {}
  
  local toTime,midnight,encodeFast = fibaro.toTime,fibaro.midnight,json.encodeFast
  local fmt = string.format
  
  function Utils.evOpts(...) for _,v in pairs({...}) do if not v then return false end end return true end
  
  function Utils.stack()
    local p,px,st,self=0,0,{},{}
    function self.push(v) p=p+1 st[p]=v px=p end
    function self.pop(n) n = n or 1; p=p-n; px=p return st[p+n] end
    function self.pop2() local b,a = self.pop(),self.pop() return a,b end
    function self.popn(n,v) v = v or {}; if n > 0 then local p0 = self.pop(); self.popn(n-1,v); v[#v+1]=p0 end return v end 
    function self.peek(n) return st[p-(n or 0)] end
    function self.lift(n) local s = {} for i=1,n do s[i] = st[p-n+i] end self.pop(n) return s end
    function self.liftc(n) local s = {} for i=1,n do s[i] = st[p-n+i] end return s end
    function self.isEmpty() return p<=0 end
    function self.size() return p end    
    function self.setSize(np) p=np; px=p end
    function self.push0(v) px=px+1 st[px]=v end
    function self.p2px(v) p=px end
    function self.popm(n) n=n or 1; local r ={} for i=p-n+1,px do r[#r+1]=st[i] end p=p-n; px=p return r end
    function self.get(i) return st[i] end
    function self.dump() for i=1,p do print(string.format("S%02d: %s",i,json.encode(st[i]))) end end
    function self.clear() p,px,st=0,0,{} end
    return self
  end
  
  function Utils.stream(tab)
    local p,self=0,{ stream=tab, eof={type='eof', value='', from=tab[#tab].from, to=tab[#tab].to} }
    function self.next() p=p+1 local r = p<=#tab and tab[p] or self.eof; return r end
    function self.last() return tab[p] or self.eof end
    function self.prev() return tab[p-1] or self.eof end
    function self.peek(n) return tab[p+(n or 1)] or self.eof end
    function self.containsOp(op) for _,t in ipairs(tab) do if t.opval == op then return true end end end
    return self
  end
  
  local floor = math.floor
  
  local function htmlify(str)
    local cols,i = {},0
    str = str:gsub("(<font .->)",function(c) cols[#cols+1]=c return "#CCC#" end)
    --str = str:gsub(" ","&nbsp;")
    str = str:gsub("\n","</br>")
    return str:gsub("(#CCC#)",function(c) i=i+1 return cols[i] end)
  end
  
  local function LOGGER(df,f,...)
    if #{...} > 0 then
      local msg = f:format(...)
      msg = htmlify(msg)
      df(ER.settings.systemLogTag or __TAG,msg)
    else 
      f = htmlify(f)
      df(ER.settings.systemLogTag or __TAG,f) 
    end
  end
  
  function Utils.LOG(f,...) LOGGER(fibaro.trace,f,...) end
  function Utils.LOGERR(f,...) LOGGER(fibaro.error,f,...) end
  
  local LOG = Utils.LOG
  local LOGERR = Utils.LOGERR
  
  function Utils.PrintBuffer(...)
    local self = { buff = {...} }
    local buff = self.buff
    function self:printf(...) buff[#buff+1] = string.format(...) end
    function self:add(v) buff[#buff+1] = tostring(v) end
    function self:print(...)
      local r={} for _,v in ipairs({...}) do r[#r+1] = tostring(v) end
      buff[#buff+1] = table.concat(r," ")
    end
    function self:tostring(div) return table.concat(buff,div or "\n") end
    return setmetatable(self,{__tostring=function(obj) return obj:tostring() end})
  end
  
  local function maxLen(list) local m = 0 for _,e in ipairs(list) do m=math.max(m,e:len()) end return m end
  if hc3_emulator then 
    function Utils.htmlTable(list,opts)
      opts = opts or {}
      local pr,cols,rows=Utils.PrintBuffer(),{},{}
      for i,e in ipairs(list) do list[i]=type(e)=='table' and e or {e} end
      for i=1,#list do
        for j=1,#list[i] do
          local e = list[i][j]
          local s = e:split("\n")
          list[i][j]=s
          cols[j]=math.max(cols[j] or 0,maxLen(s))
          rows[i]=math.max(rows[i] or 0,#s)
        end
      end
      local s = "+"
      for j=1,#cols do s=s..("-"):rep(cols[j]+2).."+" end -- Create line divider
      pr:add(s)
      for i=1,#list do  -- rows
        for r=1,rows[i] do
          local l = {}
          for j=1,#list[i] do -- cols
            local ll = list[i][j][r] or ""
            l[#l+1]=ll..(" "):rep(cols[j]-ll:len())
            --sp=" |"
          end
          pr:add("| "..table.concat(l," | ").." |")
        end
        pr:add(s)
      end
      return "\n"..pr:tostring("\n")
    end
  else
    function Utils.htmlTable(list,opts)
      opts = opts or {}
      local pr = Utils.PrintBuffer()
      pr:printf("<table %s>",opts.table or "")
      for _,l in ipairs(list) do
        pr:printf("<tr %s>",opts.tr or "")
        l = type(l)=='table' and l or {l}
        for _,e in ipairs(l) do
          pr:printf("<td %s>",opts.td or "") pr:add(tostring(e)) pr:add("</td>") 
        end
        pr:add("</tr>")
      end
      pr:add("</table>")
      return pr:tostring("")
    end
  end
  
  function Utils.strPad(str,args,ch,w)
    ch,w=ch or "-",w or 100
    str = fmt(str,table.unpack(args or {}))
    str = #str % 2 == 1 and str.." " or str
    local n = #str+2
    local l2=100/2-n/2
    return string.rep(ch,l2).." "..str.." "..string.rep(ch,l2)
  end
  
  function Utils.makeBanner(str,args,ch,w) return Utils.strPad(str,args,ch,w) end
  if fibaro.fibemu then
    function Utils.printBanner(str,args,col,ch,w) LOG('\n<font color="%s">%s</font>',col or "orange",Utils.makeBanner(str,args,ch,w)) end
  else
    function Utils.printBanner(str,args,col,ch,w)
      col=col or ER.settings.bannerColor or "orange"
      str = fmt("<font color='black'>%s</font>",str)
      LOG(Utils.htmlTable({fmt(str,table.unpack(args or {}))},{table="width='100%' border=1 bgcolor='"..col.."'",td="align='center'"}))
    end
  end
  
  local function table2str(t)
    if type(t) == 'table' and not getmetatable(t) then
      return encodeFast(t)
    else return tostring(t) end
  end
  function Utils.argsStr(...)
    local args = {...}
    local n = table.maxn(args)
    if n == 0 then return "nil" end
    local r = {} for i=1,n do r[i] = table2str(args[i]) end
    return table.concat(r,",")
  end
  
  local function shallowCopy(t) local r = {}; for k,v in pairs(t) do r[k]=v end; return r end
  function Utils.eventStr(ev)
    ev = shallowCopy(ev)
    ev._trigger = nil
    ev._sh = nil
    local s = encodeFast(ev)
    return fmt("#%s{%s}",ev.type,s:match(",(.*)}") or "")
  end
  
  function Utils.errorMsg(err)
    err.class = err.type
    err.type = 'error'
    if err.src then err.srcInfo = err.srcInfo or Utils.errorLine(err.src,err.from,err.to) end
    setmetatable(err,{__tostring=function(self)
      local e = string.format("%s %s: %s",self.rule and self.rule.longName or "Expr",self.class,self.msg)
      if err.srcInfo then e = e.."\n"..err.srcInfo end
      return e
    end})
    return err
  end
  
  function Utils.isErrorMsg(e) return type(e)=='table' and e.type == 'error' end
  
  function Utils.xerror(m,level) ER._lastErr = m error(m,level) end
  
  function Utils.pcall(f,...)
    local stat = {pcall(f,...)}
    if not stat[1] and ER._lastErr then
      stat[3]=stat[2]
      stat[2]=ER._lastErr
      ER._lastErr = nil
    end
    return table.unpack(stat)
  end
  
  function Utils.errorLine(str,from,to)
    if not str:find("\n") then 
      if not(from or to) then return nil end
      local msg = str.."\n"
      msg = msg..string.rep(" ",from-1)..string.rep("^",to-from+1)
      return msg
    else
      if not(from or to) then return nil end
      local n = 0
      local lines = str:split("\n")
      for _,l in ipairs(lines) do
        if from >=n and from <= n+#l+1 then
          from = from-n
          to = to-n
          local msg = l.."\n"
          msg = msg..string.rep(" ",from-1)..string.rep("^",to-from+1)
          return msg
        end
        n = n+#l+1
      end
    end
  end
  
  local MTevent = { __tostring = Utils.eventStr }
  
  local _customEvent = {
    daily = { __tostring=function(self) return fmt("#daily{%s}",self.id) end},
    ['%interval%'] = { __tostring=function(self) return fmt("#interv{%s}",self.id) end},
    ['global-variable'] = { __tostring=function(self) return fmt("#GV{%s=%s}",self.name,self.value // 30) end},
    ['trigger-variable'] = { __tostring=function(self) return fmt("#TV{%s=%s}",self.name,tostring(self.value) // 30) end},
  }
  function Utils.eventCustomToString(event)
    if _customEvent[event.type] then return setmetatable(event,_customEvent[event.type]) end
    return setmetatable(event,MTevent)
  end
  function ER.eventToString(type,fun)
    _customEvent[type] = { __tostring=fun }
  end
  
  local _marshalBool={['true']=true,['True']=true,['TRUE']=true,['false']=false,['False']=false,['FALSE']=false}
  
  function Utils.marshallFrom(v) 
    if not ER.settings.marshall then return v elseif v==nil then return v end
    local fc = v:sub(1,1)
    if fc == '[' or fc == '{' then local s,t = pcall(json.decode,v); if s then return t end end
    if tonumber(v) then return tonumber(v)
    elseif _marshalBool[v ]~=nil then return _marshalBool[v ] end
    if v=='nil' then 
      return nil 
    end
    local test = v:match("^[0-9%$s]")
    if not test then return v end
    local s,t = pcall(toTime,v,true); return s and t or v 
  end
  
  local function safeEncode(s) local stat,res = pcall(encodeFast,s) return stat and res or nil end
  function Utils.marshallTo(v) 
    if not ER.settings.marshall then return tostring(v) end
    if type(v)=='table' then return safeEncode(v) else return tostring(v) end
  end
  
  ------- Patch fibaro.call to track manual switches -------------------------
  local lastID,switchMap = {},{}
  local oldFibaroCall = fibaro.call
  function fibaro.call(id,action,...)
    if ({turnOff=true,turnOn=true,on=true,toggle=true,off=true,setValue=true})[action] then lastID[id]={script=true,time=os.time()} end
    if action=='setValue' and switchMap[id]==nil then
      local actions = (__fibaro_get_device(id) or {}).actions or {}
      switchMap[id] = actions.turnOff and not actions.setValue
    end
    if action=='setValue' and switchMap[id] then return oldFibaroCall(id,({...})[1] and 'turnOn' or 'turnOff') end
    return oldFibaroCall(id,action,...)
  end
  
  local function lastHandler(ev)
    if ev.type=='device' and ev.property=='value' then
      local last = lastID[ev.id]
      local _,t = fibaro.get(ev.id,'value')
      --if last and last.script then print("T:"..(t-last.time)) end
      if not(last and last.script and t-last.time <= 2) then
        lastID[ev.id]={script=false, time=t}
      end
    end
  end
  
  extraSetups[#extraSetups+1] = function()
    fibaro.registerSourceTriggerCallback(lastHandler)
  end
  
  function QuickApp:lastManual(id)
    local last = lastID[id]
    if not last then return -1 end
    return last.script and -1 or os.time()-last.time
  end
  
  -------------------------------------
  local equations = {}
  function equations.linear(t, b, c, d) return c * t / d + b; end
  function equations.inQuad(t, b, c, d) t = t / d; return c * (t ^ 2) + b; end
  function equations.inOutQuad(t, b, c, d) t = t / d * 2; return t < 1 and c / 2 * (t ^ 2) + b or -c / 2 * ((t - 1) * (t - 3) - 1) + b end
  function equations.outInExpo(t, b, c, d) return t < d / 2 and equations.outExpo(t * 2, b, c / 2, d) or equations.inExpo((t * 2) - d, b + c / 2, c / 2, d) end
  function equations.inExpo(t, b, c, d) return t == 0 and b or c * (2 ^ (10 * (t / d - 1))) + b - c * 0.001 end
  function equations.outExpo(t, b, c, d) return t == d and  b + c or c * 1.001 * ((2 ^ (-10 * t / d)) + 1) + b end
  function equations.inOutExpo(t, b, c, d)
    if t == 0 then return b elseif t == d then return b + c end
    t = t / d * 2
    if t < 1 then return c / 2 * (2 ^ (10 * (t - 1))) + b - c * 0.0005 else t = t - 1; return c / 2 * 1.0005 * ((2 ^ (-10 * t)) + 2) + b end
  end
  
  function Utils.dimLight(id,sec,dir,step,curve,start,stop)
    assert(tonumber(sec), "Bad dim args for deviceID:%s",id)
    local f = curve and equations[curve] or equations['linear']
    dir,step = dir == 'down' and -1 or 1, step or 1
    start,stop = start or 0,stop or 99
    quickApp:post({type='%dimLight',id=id,sec=sec,dir=dir,fun=f,t=dir == 1 and 0 or sec,start=start,stop=stop,step=step,_sh=true})
  end
  
  extraSetups[#extraSetups+1] = function()
    fibaro.event({type='%dimLight'},function(env)
      local e = env.event
      local ev,currV = e.v or -1,tonumber(fibaro.getValue(e.id,"value"))
      if not currV then
        quickApp:warningf("Device %d can't be dimmed. Type of value is %s",e.id,type(fibaro.getValue(e.id,"value")))
      end
      if e.v and math.abs(currV - e.v) > 2 then return end -- Someone changed the lightning, stop dimming
      e.v = math.floor(e.fun(e.t,e.start,(e.stop-e.start),e.sec)+0.5)
      if ev ~= e.v then fibaro.call(e.id,"setValue",e.v) end
      e.t=e.t+e.dir*e.step
      if 0 <= e.t and  e.t <= e.sec then quickApp:post(e,os.time()+e.step) end
    end)
  end
  ----------------------------
  local sunInfo = {}
  local lastDay = ""
  function Utils.sunData()
    local today = os.date("%x")
    if lastDay ~= today then
      sunInfo.sunriseHour,sunInfo.sunsetHour,sunInfo.dawnHour,sunInfo.duskHour=fibaro.utils.sunCalc()
      ---@diagnostic disable-next-line: cast-local-type
      lastDay = today
    end
    return sunInfo
  end
  
  local emulatedDevices = {}
  do
    local oldCall,oldGet = fibaro.call,__fibaro_get_device_property
    function fibaro.call(id,...) 
      if emulatedDevices[id] then return emulatedDevices[id]:call(...) end
      return oldCall(id,...) 
    end
    function __fibaro_get_device_property(id,prop)
      if emulatedDevices[id] then return {value=emulatedDevices[id]:get(prop),modified=emulatedDevices[id].modified} end
      return oldGet(id,prop)
    end
    Utils.emulatedDevices = emulatedDevices
  end

  local traceCalls = { 'call', 'getVariable', 'setVariable','alarm','alert', 'emitCustomEvent', 'scene','profile' }
  local nonSpeedCalls = { 'call','alarm','alert', 'scene', 'profile' }
  local nonSpeedApis = { 'put','delete' }
  for _,name in ipairs(traceCalls) do
    local fun = fibaro[name]
    fibaro[name] = function(...)
      local stat = {true}
      local virt = name=='call' and emulatedDevices[({...})[1] or ""]
      if virt or (not nonSpeedCalls[name]) or (not ER.__speedTime) then
        stat = {pcall(fun,...)}
      end
      if not stat[1] then error(stat[2]) end
      if ER.settings.logFibaro then
        local args = {...}
        local str = string.eformat("Fibaro call: fibaro.%s(%l) = %l",name,args,{table.unpack(stat,2)})
        LOG(str)
      end
      return table.unpack(stat,2)
    end 
  end
  
  for _,name in ipairs({'get','post','put','delete'}) do
    local fun = api[name]
    api[name] = function(...)
      local stat = {true,{},200}
      if not nonSpeedApis[name] or not ER.__speedTime then
        stat = {pcall(fun,...)}
      end
      if not stat[1] then error(stat[2]) end
      if ER.settings.logApi then 
        local args = {...}
        for i=1,#args do if type(args[i])=='table' then args[i]=json.encode(args[i]) end end
        local str = string.eformat("API call: api.%s(%l) = %,40l",name,args,{json.encode(stat[2]),tostring(stat[3])})
        LOG(str) 
      end
      return table.unpack(stat,2)
    end 
  end
  
  local timeOffset = 0

  local oldTime,oldDate = os.time,os.date

  function os.time(t) return t and oldTime(t) or oldTime()+timeOffset end
  function os.date(s,b) return (not b) and oldDate(s,os.time()) or oldDate(s,b) end

  function Utils.setTime(str) -- str = "mm/dd/yyyy-hh:mm:ss"
    local function tn(s, v) return tonumber(s) or v end
    local d, hour, min, sec = str:match("(.-)%-?(%d+):(%d+):?(%d*)")
    local month, day, year = d:match("(%d*)/?(%d*)/?(%d*)")
    local t = os.date("*t")
    t.year, t.month, t.day = tn(year, t.year), tn(month, t.month), tn(day, t.day)
    t.hour, t.min, t.sec = tn(hour, t.hour), tn(min, t.min), tn(sec, 0)
    local t1 = os.time(t)
    local t2 = os.date("*t", t1)
    if t.isdst ~= t2.isdst then
        t.isdst = t2.isdst
        t1 = oldTime(t)
    end
    timeOffset = t1 - oldTime()
  end

  local runTimers,speedHours = nil,0
  function Utils.speedTime(hours)
    speedHours = hours
    local startTime = os.time()*1000
    timeOffset = 0
    local endTime = startTime + hours*60*60*1000
    local function milliseconds() return startTime+timeOffset end
    function os.time(t) return t and oldTime(t) or math.floor(0.5+milliseconds()/1000) end
    function os.date(s,b) return (not b) and oldDate(s,os.time()) or oldDate(s,b) end
    local oldSetTimeout,oldSetInterval = setTimeout,setInterval
    local timerQueue = {}
    function setTimeout(f,t)
      t = milliseconds() + t
      local ref = {f=f,t=t}
      for i,e in ipairs(timerQueue) do
        if e.t >  t then table.insert(timerQueue,i,ref) return ref end
      end
      timerQueue[#timerQueue+1] = ref
      return ref
    end
    function runTimers()
      local now = milliseconds()
      while timerQueue[1] and timerQueue[1].t <= now do
        local e = table.remove(timerQueue,1)
        e.f()
      end
      if now > endTime then
        fibaro.warning(__TAG," SpeedTime ended")
        timerQueue = {}
        ER.__speedTime = false
        os.time,os.date = oldTime,oldDate
        setTimeout,setInterval = oldSetTimeout,oldSetInterval
        ER.startMidnightScheduler()
        return
      end
      if #timerQueue > 0 then
        local t = timerQueue[1].t - now
        if t < 0 then t = 0 end
        timeOffset = timeOffset + t
        oldSetTimeout(runTimers,0)
      else
        oldSetTimeout(runTimers,10)
      end
    end
    function clearTimeout(ref)
      for i,e in ipairs(timerQueue) do
        if e == ref then table.remove(timerQueue,i) return end
      end
    end
    ER.startMidnightScheduler()
    ER.__speedTime = true
  end
  Utils.runTimers = function() 
    fibaro.warningf(__TAG," SpeedTime started (%shours)",speedHours)
    runTimers() 
  end
  ------------------------------------------------------
  
  ER.utilities.export = {
    Utils.stack, Utils.stream, Utils.errorMsg, Utils.isErrorMsg, Utils.xerror, Utils.pcall, Utils.errorLine,
    Utils.marshallFrom, Utils.marshallTo, toTime, midnight, encodeFast, Utils.argsStr, Utils.eventStr,
    Utils.PrintBuffer, Utils.sunData, Utils.LOG, Utils.LOGERR, Utils.htmlTable, Utils.evOpts, Utils.eventCustomToString,
    string.eformat
  }
  for _,f in ipairs(extraSetups) do f() end
  
  
  -- stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  -- marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
  -- PrintBuffer,sunData,LOG,LOGERR,htmlTable,evOpts,eventCustomToString,formatt =
  -- table.unpack(ER.utilities.export)
  
end