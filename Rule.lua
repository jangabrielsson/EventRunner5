QuickApp.__ER  = QuickApp.__ER or { modules={} }

function QuickApp.__ER.modules.rule(ER)
  
  local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,PrintBuffer =
  table.unpack(ER.utilities.export)
  
  local stdPropObject,isPropObject = ER.stdPropObject,ER.isPropObject
  
  local fmt=string.format
  local vars,triggerVars = ER.ruleValues,ER.triggerVars
  local function now() local t = os.date("*t") return t.hour*3600+t.min*60+t.sec end
  
  local function printf(...) print(fmt(...)) end
  
  local function LOG(...) fibaro.trace(__TAG,fmt(...)) end
  
  -- {prop='value',operator='eq',value='value'}
  -- {gv='value',operator='eq',qv='value'}
  -- {qv='value',operator='eq',qv='value'}
  -- {event='value',operator='eq',qv='value'}
  -- {triggerVar='value',operator='eq',event='value'}
  -- {betw={from='value',to='value'},event='value'}
  -- {daily={from='value',to='value'},event='value'}
  -- {interv={from='value',to='value'},event='value'}
  
  local triggerHandlers={}
  local function triggerVar(name) return triggerVars[name] end
  
  local function compute(p) local c = ER:compile(p,{src = ER.__lastParsed}) return c() end
  local function compile(p) return ER:compile(p,{src = ER.__lastParsed}) end
  local function hms(t) return os.date("%H:%M:%S",t < 24*3600 and t+fibaro.midnight() or t) end -- TBD: move to Utils.lua
  local function trim(str,n) return #str <= n and str or str:sub(1,n).."..." end
  
  local function errorf(tk,fm,...)
    if tk.d then tk = tk.d end
    local err = errorMsg{type="Rule",msg=fmt(fm,...),from=tk.from,to=tk.to,src=ER.__lastParsed}
    e_error(err) 
  end
  
  local ruleCtx = {}
  function ruleCtx.get(name) return vars[name] or {_G[name]} end
  function ruleCtx.set(name,value) 
    local v,old = vars[name],nil
    if v then old=v[1] v[1]=value else vars[name]={value} end
    return true,old
  end
  function ruleCtx.post(event) fibaro.post(event) end
  function ruleCtx.setTimeout(p,fun,delay,descr) return p.rule._setTimeout(fun,delay,descr) end
  function ruleCtx.clearTimeout(p,ref) return p.rule._clearTimeout(ref) end
  ruleCtx.triggerVar = triggerVar
  function ruleCtx.print(...) print(...) end
  ER.ctx = ruleCtx
  
  local CATCHUP = math.maxinteger
  
  local userDeviceObjects = {}
  local function getDeviceObject(id)
    local f = tonumber(id)
    if f then stdPropObject.id = id return userDeviceObjects[f] or stdPropObject end
    if isPropObject(id) then return id end
  end
  ER.getDeviceObject = getDeviceObject
  
  function triggerHandlers.prop(p,t)
    local ids = compute(p.args[1])
    local prop,isTable,tn = p.args[2],false,0
    if type(ids) == 'table' then isTable = true else ids = {ids} end
    local n = table.maxn(ids)
    if n == 0 then errorf(p.args[1],"No devices found for :%s, must be defined when rule is defined",prop) end
    for i = 1,n do
      local dev = getDeviceObject(ids[i]) 
      ids[i] = {dev,ids[i]}
      if not dev then errorf(p,"%s is not a valid device",tostring(dev)) end
      if not dev:isProp(prop) then errorf(p,":%s is not a valid device property",prop) end
      tn = tn + (dev:isTrigger(prop) and 1 or 0)
    end
    if tn == 0 then return end -- no triggers, ignore
    for _,id in ipairs(ids) do
      t.srct[prop..tostring(id)] = id[1]:getTrigger(id[2],prop)
    end
  end
  function triggerHandlers.var(p,t) if triggerVar(p.name) then t.srct["TV:"..p.name]={type='trigger-variable', name=p.name} end end
  function triggerHandlers.gv(p,t) t.srct["GV:"..p.name]={type='global-variable', name=p.name} end
  function triggerHandlers.qv(p,t) t.srct["QV:"..p.name]={type='quickvar', name=p.name} end
  local eid = 0
  function triggerHandlers.table(p,t)
    local ev = compute(p)
    if ev.type then eid = eid+1 t.srct["EV:"..eid]=compute(p) end
  end
  function triggerHandlers.const(p,t)
    ---@diagnostic disable-next-line: undefined-field
    if type(p.value)=='table' and p.value.type then 
      local evid = "EV:"..eid
      eid = eid+1 t.srct[evid]=p.value
      p.type = 'eventm'
      p.evid = evid
      p.event = p.value
      p.value = 0
    end
  end
  function triggerHandlers.betw(p,t)
    t.timers[#t.timers+1] = compile(p.args[1]); 
    t.timers[#t.timers+1] = compile({type='op',op='add',args={{type='num',value=1,},p.args[2]}}) 
  end
  function triggerHandlers.daily(p,t)   -- collect daily expressions, @10:00, @{$mytime,$othertime+10:00}
    assert(t.daily==nil,"Only one @daily in a rule is supported")
    t.daily = compile(p.args[1])
    local times = t.daily()
    if type(times) == 'table' then
      for _,time in ipairs(times) do
        if time == CATCHUP then t.catchup = true; break end
      end
    end
  end 
  function triggerHandlers.interv(p,t)  -- collect interval expressions, @@00:05, @{$mytime,$othertime+00:01}
    assert(t.interv==nil,"Only one @@interval in a rule is supported")
    t.interv = compile(p.args[1])
  end
  
  local function getTriggers(p,t)
    if type(p) == 'table' then
      if p[1] then 
        for _,v in ipairs(p) do getTriggers(v,t) end
      else
        local h = triggerHandlers[p.type] or triggerHandlers[p.op or ""]
        if h then h(p,t)
        else 
          for _,v in pairs(p) do getTriggers(v,t) end 
        end
      end
    end
  end
  
  local ruleID = 0
  local function setupDailys(rule,catchup)
    rule._clearDailyTimers()  -- clear any previous outstanding daily timer
    local scheduled,n = {},now()
    for _,texpr in ipairs(rule.dailys) do
      local v = texpr() v = type(v)=='table' and v or {v}
      local flag = false
      for _,t in ipairs(v) do
        if t < n and rule.catchup and catchup then -- time passed and catchup is on
          rule._addDailyTimer(0,t)               -- run rule 
          catchup = false                        -- but only once
        elseif t >= n and t ~= CATCHUP then      -- schedule timer for later
          if not scheduled[t] then               -- Don't schedule same timer twice
            scheduled[t] = true
            rule._addDailyTimer(t-n,t)
          end
        end
      end
    end
  end
  
  local rules =  {}
  
  local function ruleNameStr(r) return r.rname end
  local function ruleDescriptionStr(d,rule) return fmt("%s description:\n%s",rule.rname,tostring(rule.triggers)) end
  local function ruleTriggersStr(tr,rule)
    local s = {fmt("%s triggers:",rule.rname)} for k,t in pairs(tr) do s[#s+1] = "->Event:"..eventStr(t) end
    for _,t in ipairs(rule.dailys) do
      local v = t()
      if type(v)=='table' then 
        for _,t in ipairs(v) do s[#s+1] = fmt("->Timer:%s",hms(t)) end
      else s[#s+1] = fmt("->Timer:%s",hms(v)) end
    end
    return table.concat(s,"\n")
  end
  local function ruleInfoStr(_,rule)
    local s = {fmt("%s timers:",rule.rname)} for ref,doc in pairs(rule._timers) do 
      s[#s+1] = fmt("->'%s':%s",doc[1],os.date("%c",doc[2]))
    end
    return table.concat(s,"\n")
  end
  local function ruleProcessStr(_,rule)
    local res = {fmt("%s processes:",rule.rname)}
    for co,stat in pairs(rule.runners) do res[#res+1]= fmt("%s => %s (%s)",rule.rname,stat,co) end
    return table.concat(res,"\n")
  end
  
  function ER.listRules()
    local pr,n = PrintBuffer(),0
    pr:printf("\nRules:")
    for i,r in pairs(rules) do
      n = n+1
      pr:printf("%d:%-60s [%s]",i,r.longName,r._enabled and "enabled" or "disabled")
    end 
    pr:printf("Number of rules: %d",n)
    print(pr:tostring())
  end
  
  function ER.listVariables(name)
    name = name or ".*"
    local pr,n = PrintBuffer(),0
    pr:printf("\nVariables:")
    for vn,v in pairs(vars) do
      if vn:match(name) then
        pr:printf("%s = %s",vn,encodeFast(v) // 60)
        n = n+1
      end
    end 
    pr:printf("Number of variables: %d",n)
    print(pr:tostring())
  end
  
  local midnightFuns = {}
  local function midnightScheduler(fun) midnightFuns[#midnightFuns+1] = fun end
  local midnxt = (os.time() // 3600 +1)*3600
  local function midnightLoop()
    for _,f in ipairs(midnightFuns) do f() end
    midnxt = midnxt+3600
    setTimeout(midnightLoop,(midnxt-os.time())*1000)
  end
  setTimeout(midnightLoop,(midnxt-os.time())*1000)
  
  function ER:createRule(cond,action,ctx,p)
    local rule = {type='%RULE%'}
    ruleID = ruleID+1
    rule.id = ruleID
    rule._name = p.co.options.name or tostring(rule.id)
    rule._ltag = p.co.options.ltag -- or er.logtag?
    rule.instance = 0
    rule._enabled = true
    rule.src = ER.__lastParsed
    local tostring = fibaro._orgToString
    
    local function nameRule()
      rule.rname = fmt("[Rule:%s]",rule._name)
      rule.longName = fmt("[Rule:%s:%s]",rule._name,trim(rule.src,40))
    end
    nameRule()
    
    LOG("Defining [Rule:%s:%s]...",rule._name,trim(rule.src,40))
    local triggers = { daily=nil, interv=nil, timers={}, srct={} }
    getTriggers(cond,triggers)
    local trs = triggers.srct
    
    rule.triggers = trs
    rule.catchup = triggers.catchup
    rule.dailys = {}         -- daily times and between times
    rule._dailyTimers = {}    -- refs to emitted daily timers (for cancellation)
    rule._timers = {}         -- refs to emitted timers, ex posts (for cancellation)
    rule.evhandlers = {}
    
    ER._lastRule = rule
    rule.fun = compile({type='rule_action',cond=cond,action=action})
    
    assert(next(trs) or triggers.daily or triggers.interv or #triggers.timers>0,"No triggers in rule")
    assert(not(triggers.daily and triggers.interv),"Only one @daily or @@interval in a rule is supported")
    
    local dailys = triggers.timers
    if triggers.daily then table.insert(dailys,1,triggers.daily) end
    rule.dailys = dailys
    
    if triggers.interv then
    end
    
    for evid,t in pairs(trs) do
      local fun = function(env) return rule.start(env.event,evid,env.p) end
      local handler = fibaro.event(t,fun)
      rule.evhandlers[t] = {fun,handler}
    end
    
    -- public rule functions
    function rule.name(name) rule._name = name; nameRule() return rule end
    function rule.rtag(tag) rule._rtag = tag; return rule end
    function rule.ltag(tag) rule._ltag = tag; return rule end
    function rule.enable() 
      if rule._enabled then return end
      rule._enabled = true
      for _,eh in pairs(rule.evhandlers) do
        eh[2].enable()
      end
      return rule 
    end
    function rule.disable()
      if not rule._enabled then return end
      rule._enabled = false
      rule.stop()
      for _,eh in pairs(rule.evhandlers) do
        eh[2].disable()
      end
      return rule 
    end
    function rule.isEnabled() return rule._enabled end
    function rule.print() print(self) return rule end
    function rule.delete()
      rule.disable()
      for event,eh in pairs(rule.evhandlers) do
        fibaro.removeEvent(event,eh[1])
      end
    end
    function rule.processes()
      local res = {fmt("%s processes:",rule.rname)}
      for co,stat in pairs(rule.runners) do res[#res+1]= fmt("-> %s (%s)",stat,co) end
      return table.concat(res,"\n")
    end
    function rule.stop()
      rule._clearDailyTimers() 
      rule._clearTimers() 
      return rule
    end
    function rule.recompile() -- recompile rule code, replacing old rule with new rule
      rule.stop()
      local nr = rule.compile(rule.src)
      local nrid = nr.id
      nr._trace = rule._trace
      nr.id = rule.id
      nr.name = rule.name
      rules[rule.id] = nr
      rules[nrid] = nil
    end
    ------------------- public rule variables ----------------------
    -- rule.trace = boolean        -- if true, trace rule execution (VM)
    -- rule.id = number            -- assigned by ER when rule is created
    -- rule.tag = <string>         -- allows for grouping rules (ex. for enable/disable)
    -- rule.rname = <string>       -- "[Rule:<id>:_name]"
    -- rule.longName = <string>    -- "[Rule:<id>:_name:<short source>]"
    -- rule.description = <string> -- shortName + triggers
    -- rule.info = <string>        -- shortName + current timers
    -- rule.src = <string>         -- rule source definition
    -- rule.code == <string>       -- compiled rule code
    
    
    rule.fun.ctx = ruleCtx
    rule.runners = {}
    local coroutine = ER.coroutine 
    local runCoroutine = ER.runCoroutine
    
    function rule.start(ev,id,vars)
      local co = coroutine.create(rule.fun)
      rule.instance = rule.instance+1
      local instname = fmt("[Rule:%s:%s]",rule._name,rule.instance)
      co.name = setmetatable({},{__tostring = function() return instname end})
      co.rtd.rule = rule
      rule.runners[co] = 'running'
      local env = {event=ev,evid=id,vars=vars,rule=rule,name=co.name,co=co}
      local locals = co.rtd.env -- local variables
      locals.push('env',env)
      for k,v in pairs(vars or {}) do locals.push(k,v) end
      
      function co._action(ok,msg)
        co.LOG("condition %s",ok and "true - action" or "false - cancelled")
      end
      function co.LOG(...) LOG("%s>> %s",co.name,fmt(...)) end
      
      local options = {
        trace=rule._trace,debug=rule._debug,ctx=rule.fun.ctx,
      }
      
      local suspendMsg = {
        ['%wait%'] = function(delay,msg) return fmt("wait %s %s",hms(delay/1000),msg or "") end,
        ['%callback%'] = function(delay,msg) end,
      }
      
      function options.suspended(success,typ,...)
        rule.runners[co] = 'suspended'
        local sm = suspendMsg[typ]
        if sm then co.LOG("suspended %s - %s",success and "action" or "triggered",sm(...))
        else
          co.LOG("=> %s [%s,suspended]",argsStr(typ,...),success)
        end
      end
      
      function options.success(success,...)
        rule.runners[co] = nil
        local a = {}
        if success then co.LOG("result %s",co.name,argsStr(...)) end
        if rule.resultHook then rule.resultHook(success,...) end
      end
      
      function options.error(err) rule.runners[co] = nil fibaro.error(__TAG,err) end
      
      co.LOG("triggered %s",trim(eventStr(ev),40))
      local res = {runCoroutine(co,options,env)}
      if res[1] then options.success(table.unpack(res,2)) end
      return rule
    end
    
    -- Internal rule housekeeping functions
    function rule._setTimeout(fun,delay,descr) 
      local ref = setTimeout(fun,delay)
      rule._timers[ref] = {descr or "timer",os.time()+delay}
      return ref
    end
    function rule._clearTimeout(ref)
      local doc = rule._timers[ref]
      if doc then clearTimeout(ref) end
    end
    function rule._clearDailyTimers() 
      for t,_ in pairs(rule._dailyTimers) do clearTimeout(t) end
      rule._dailyTimers = {}
    end
    function rule._clearTimers() 
      for ref,doc in pairs(rule._timers) do clearTimeout(ref) end
      rule._timers = {}
    end
    function rule._addDailyTimer(delay,time)
      local ref
      LOG("%s>> scheduling %sdaily for %s",rule.rname,delay==0 and "and running/catchup " or "",hms(midnight()+time))
      ref = setTimeout(function()
        rule.start({type='daily',id=rule.id,time=time})
        rule._dailyTimers[ref]=nil
      end,delay*1000)
      rule._dailyTimers[ref]=true
    end
    function rule._setupDailys(catch) setupDailys(rule,catch) end
    
    if #dailys>0 then rule._setupDailys(true) end
    
    function rule.evalPrint() nameRule() LOG(rule.rname.." defined") end
    setmetatable(rule,{__tostring = ruleNameStr})
    setmetatable(rule.triggers,{__tostring = function(t) return ruleTriggersStr(t,rule) end })
    rule.description = setmetatable({},{__tostring = function(d) return ruleDescriptionStr(d,rule) end })
    rule.info = setmetatable({},{__tostring = function(d) return ruleInfoStr(d,rule) end })
    rule.processes = setmetatable({},{__tostring = function(d) return ruleProcessStr(d,rule) end })   
    
    rules[rule.id] = rule
    return rule
  end
  
end