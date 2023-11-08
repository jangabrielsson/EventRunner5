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
      LOG(Utils.htmlTable({fmt(str,table.unpack(args or {}))},{table="width='100%' border=1 bgcolor='"..col.."'",td="align='center'"}))
    end
  end
  
  getmetatable("").__idiv = function(str,len) return (#str < len or #str < 4) and str or str:sub(1,len-2)..".." end
  
  function Utils.argsStr(...)
    local args = {...}
    local n = table.maxn(args)
    if n == 0 then return "nil" end
    local r = {} for i=1,n do r[i] = tostring(args[i]) end
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
      local e = string.format("%s %s: %s",self.rule and self.rule.rname or "Expr",self.class,self.msg)
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
    local s,t = pcall(toTime,v); return s and t or v 
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
    quickApp:event({type='%dimLight'},function(env)
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
    function Utils.format(fmt,...)
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
      for _,f in ipairs(forms) do strs[f.i],n = f.f(args[i],i,args) i=i+n end
      local str = table.concat(strs)
      if globs[1] then
        for _,g in ipairs(globs) do str = g(str) end
      else return str end
    end
  end
  ------------------------------------------------------
  
  ER.utilities.export = {
    Utils.stack, Utils.stream, Utils.errorMsg, Utils.isErrorMsg, Utils.xerror, Utils.pcall, Utils.errorLine,
    Utils.marshallFrom, Utils.marshallTo, toTime, midnight, encodeFast, Utils.argsStr, Utils.eventStr,
    Utils.PrintBuffer, Utils.sunData, Utils.LOG, Utils.LOGERR, Utils.htmlTable, Utils.evOpts, Utils.eventCustomToString,
    Utils.format
  }
  for _,f in ipairs(extraSetups) do f() end
  
  
  -- stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  -- marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
  -- PrintBuffer,sunData,LOG,LOGERR,htmlTable,evOpts,eventCustomToString,formatt =
  -- table.unpack(ER.utilities.export)
  
end