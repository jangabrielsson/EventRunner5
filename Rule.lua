fibaro.__ER  = fibaro.__ER or { modules={} }

function fibaro.__ER.modules.rule(ER)
  
  local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
  PrintBuffer,sunData,LOG,LOGERR,htmlTable,evOpts,eventCustomToString =
  table.unpack(ER.utilities.export)

  local settings,debug = ER.settings,ER.debug

  local ruleID,rules = 0,{}
  ER.rules,ER.ruleID = rules,0
  local Rule = ER.Rule
  local stdPropObject,isPropObject = ER.stdPropObject,ER.isPropObject
  local htmlTable = ER.utilities.htmlTable
  
  local fmt=string.format
  local function hms(t) return os.date("%H:%M:%S",t < 24*3600 and t+fibaro.midnight() or t) end -- TBD: move to Utils.lua
  local vars,triggerVars = ER._vars,ER._triggerVars
  local function now() local t = os.date("*t") return t.hour*3600+t.min*60+t.sec end

  ER.ruleStats = {runs=0,errors=0,successes=0,fails=0,last={}}
  local ruleStats = ER.ruleStats

  local tableOpts = {table="width='100%' border=1 bgcolor='"..settings.listColor.."'",td="align='left'"}
  local tableOptUI = {table="width='100%' border=1 bgcolor='white'",td="align='left'"}


  function ER.createRuleStats(htmlTable,len,opts)
    opts = opts or tableOpts
    len = len or 100
    local pr = PrintBuffer()
    pr:printf("Invocations: %s",ER.ruleStats.runs)
    pr:printf("Sucesses: %s",ER.ruleStats.successes)
    pr:printf("Fails: %s",ER.ruleStats.fails)
    pr:printf("Errors: %s",ER.ruleStats.errors)
    pr:add(("-"):rep(75))
    pr:add("Recent rules:")
    for i=1,len do
      local c = ER.ruleStats.last[i]
      if not c then break end
      pr:printf("%s %s (%s,%s)",os.date("%H:%M:%S",c.start),c.name,c.status,os.date("%H:%M:%S",c.time))
    end
    return htmlTable({pr:tostring()},opts)
  end

  local function addRuleStats(c) table.insert(ruleStats.last,1,c) end

  function ER.listRuleStats() LOG(ER.createRuleStats(htmlTable)) end
  local function updateRuleStats()
    local pr = PrintBuffer('<p align="left">')
    pr:printf("Invocations: %s",ER.ruleStats.runs)
    pr:printf("Sucesses: %s",ER.ruleStats.successes)
    pr:printf("Fails: %s",ER.ruleStats.fails)
    pr:printf("Errors: %s",ER.ruleStats.errors)
    pr:add(("-"):rep(75))
    for i=1,10 do
      local c = ER.ruleStats.last[i]
      if not c then break end
       pr:printf("%s %s (%s,%s)",os.date("%H:%M:%S",c.start),c.name,c.status,os.date("%H:%M:%S",c.time))
    end
    pr:add("</p>")
    quickApp:updateView("stats","text",pr:tostring())
  end

  function ER.listRules(extended)
    local pr,n = PrintBuffer(),0
    pr:printf("Rules:")
    for i,r in pairs(rules) do
      n = n+1
      if extended then
        pr:printf("%s",r.description)
      else
        pr:printf("%d:%-60s [%s]",i,r.longName,r._enabled and "enabled" or "disabled")
      end
    end 
    pr:printf("Number of rules: %d",n)
    LOG(htmlTable({pr:tostring()},tableOpts))
  end

  function ER.listTimers()
    local pr,n = PrintBuffer(),0
    local timers = {}
    pr:printf("Timers:")
    for id,r in pairs(rules) do
      for _,t in pairs(r._timers) do
        local time = t[2]
        timers[time] = timers[time] or {}
        timers[time][#timers[time]+1] = fmt("%s%s",t[1],r)
      end
      for _,t in pairs(r._dailyTimers) do
        local time = t[2]
        timers[time] = timers[time] or {}
        timers[time][#timers[time]+1] = fmt("@%s",r)
      end
    end
    for time,rs in pairs(timers) do
      pr:print(hms(time),"->",table.unpack(rs))
    end
    LOG(htmlTable({pr:tostring()},tableOpts))
  end
  
  function ER.listVariables(name)
    name = name or ".*"
    local pr,n = PrintBuffer(),0
    pr:printf("Variables:")
    for vn,v in pairs(vars) do
      if vn:match(name) then
        pr:printf("%s = %s",vn,encodeFast(v) // settings.truncLog)
        n = n+1
      end
    end 
    pr:printf("Number of variables: %d",n)
    LOG(htmlTable({pr:tostring()},tableOpts))
  end
  
  -- {prop='value',operator='eq',value='value'}
  -- {gv='value',operator='eq',qv='value'}
  -- {qv='value',operator='eq',qv='value'}
  -- {event='value',operator='eq',qv='value'}
  -- {triggerVar='value',operator='eq',event='value'}
  -- {betw={from='value',to='value'},event='value'}
  -- {daily={from='value',to='value'},event='value'}
  -- {interv={from='value',to='value'},event='value'}
  
  local triggerHandlers={}
  
  local function compute(p,opts) local c = ER:compile(p,opts) return c() end
  local function compile(p,opts) return ER:compile(p,opts) end
  
  local function errorf(rule,tk,fm,...)
    if tk.d then tk = tk.d end
    local err = errorMsg{type="Rule",msg=fmt(fm,...),from=tk.from,to=tk.to,rule=rule,src=rule.src}
    e_error(err) 
  end
  
  local CATCHUP = math.maxinteger
  
  local userDeviceObjects = {}
  local function getDeviceObject(id)
    local f = tonumber(id)
    if f then stdPropObject.id = id return userDeviceObjects[f] or stdPropObject end
    if isPropObject(id) then return id end
  end
  ER.getDeviceObject = getDeviceObject
  local getTriggers

  function triggerHandlers.prop(p,t)
    getTriggers(p.args[1],t)
    local ids,ids2 = compute(p.args[1],t.opts),{}
    local prop,isTable,tn = p.args[2],false,0
    if ER.propFilters[prop] then
      if not ER.propFilterTriggers[prop] then return  -- filters don't generate triggers themselfs...
      else                                            -- unless they are marked as triggerGenerators, like GV and QV
        local v = compute(p,t.opts)
        getTriggers(v,t)
      end
    end
    if type(ids) == 'table' then isTable = true else ids = {ids} end
    local n = table.maxn(ids)
    if n == 0 then errorf(t.opts.rule,p.args[1],"No devices found for :%s, must be defined when rule is defined",prop) end
    for i = 1,n do
      local dev = getDeviceObject(ids[i])
      ids2[i] = {dev,ids[i]}
      if not dev then errorf(t.opts.rule,p,"%s is not a valid device",tostring(dev)) end
      if not dev:isProp(prop) then errorf(t.opts.rule,p,":%s is not a valid device property",prop) end
      tn = tn + (dev:isTrigger(prop) and 1 or 0)
    end
    if tn == 0 then return end -- no triggers, ignore
    for _,id in ipairs(ids2) do
      local s = tostring(id[2])
      local tr = id[1]:getTrigger(id[2],prop)
      local trk = encodeFast(tr) 
      --t.srct[prop..tostring(id[2])] = tr
      t.srct[trk] = tr
    end
  end
  function triggerHandlers.var(p,t) 
    if triggerVars[p.name] then 
      local evn = "TV:"..p.name
      if t.cd then t.dt[evn] = true end
      t.srct[evn]={type='trigger-variable', name=p.name} 
    end
  end
  function triggerHandlers.gv(p,t) 
    local evn = "GV:"..p.name
    if t.cd then t.dt[evn] = true end
    t.srct[evn]={type='global-variable', name=p.name} 
  end
  function triggerHandlers.qv(p,t) 
    local evn = "QV:"..p.name
    if t.cd then t.dt[evn] = true end
    t.srct[evn]={type='quickvar', name=p.name} 
  end
  local eid = 0
  function triggerHandlers.table(p,t)
    getTriggers(p.value,t)
    local ev = compute(p,t.opts)
    if ev.type then eid = eid+1 t.srct["EV:"..eid]=compute(p,t.opts) end
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
    t.cd = true
    getTriggers(p.args,t)
    t.cd = false
    t.timers[#t.timers+1] = compile(p.args[1],t.opts); 
    t.timers[#t.timers+1] = compile({type='op',op='add',args={{type='num',value=1,},p.args[2]}},t.opts) 
  end
  function triggerHandlers.daily(p,t)   -- collect daily expressions, @10:00, @{$mytime,$othertime+10:00}
    if t.daily~=nil then errorf(t.opts.rule,p,"Only one @daily in a rule is supported") end
    t.cd = true
    getTriggers(p.args[1],t)
    t.cd = false
    t.daily = compile(p.args[1],t.opts)
    local times,n = t.daily(),0
    if type(times) == 'table' then
      for _,time in ipairs(times) do
        if time == CATCHUP then t.catchup = true else n=n+1 end
      end
      if n < 1 then errorf(t.opts.rule,p,"No valid times in @daily expression") end
    end
  end 
  function triggerHandlers.interv(p,t)  -- collect interval expressions, @@00:05, @{$mytime,$othertime+00:01}
    if t.interv~=nil then errorf(t.opts.rule,p,"Only one @@interval in a rule is supported") end
    t.interv = compile(p.args[1],t.opts)
  end
  
  function getTriggers(p,t)
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
  
  local function setupDailys(rule,catchup)
    rule._clearDailyTimers()  -- clear any previous outstanding daily timer
    local scheduled,n = {},now()
    for _,texpr in ipairs(rule.dailys) do
      local v = texpr() v = type(v)=='table' and v or {v}
      local flag = false
      for _,t in ipairs(v) do
        if not tonumber(t) then errorf(rule,{},"Invalid daily time: %s",tostring(t)) end
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
  
  ER.midnightScheduler(function()  -- Reschedule all dailys at midnight
    for _,rule in pairs(rules) do
      if rule.isEnabled() then
        setupDailys(rule,true)
      end
    end
  end)

  local function printInfo(rule)
    local s = {fmt("%s info:",rule.rname)} for k,t in pairs(rule.triggers) do s[#s+1] = "->Event:"..eventStr(t) end
    for _,t in ipairs(rule.dailys) do
      local v = t()
      if type(v)=='table' then 
        for _,t in ipairs(v) do if t ~= math.maxinteger then s[#s+1] = fmt("->Dailys:%s",hms(t)) end end
      else s[#s+1] = fmt("->Timer:%s",hms(v)) end
    end
    for _,t in pairs(rule._timers) do
      s[#s+1] = fmt("->Timer:%s%s",t[1],hms(t[2]))
    end
    for _,t in pairs(rule._dailyTimers) do
      s[#s+1] = fmt("->Timer:@%s",hms(t[2]))
    end
    return LOG(table.concat(s,"\n"))
  end
  local function printProcesses(rule)
    local res = {}
    if not next(rule.runners) then
      res = {fmt("%s processes: No processes running",rule.rname)}
    else
      res = {fmt("%s processes:",rule.rname)}
      for co,stat in pairs(rule.runners) do res[#res+1]= fmt("%s => %s (%s)",rule.rname,stat,co) end
    end
    return LOG(table.concat(res,"\n"))
  end

  local function nameRule(rule)
    rule.rname = fmt("[Rule:%s]",rule._name)
    rule.longName = fmt("[Rule:%s:%s]",rule._name,rule.src:gsub("[%s%c]+"," ") // settings.truncStr)
  end

  local function runRuleLogFun(co,rule,ok,event)
    co.LOG("condition %s",ok and "true - action" or "false - cancelled") 
  end

  function ER:createRuleObject(options)
    local rule = {type='%RULE%'}
    ruleID = ruleID+1; ER.ruleID = ruleID
    rule.id = ruleID
    rule._name = options.name or tostring(rule.id)
    rule._ltag = options.log 
    rule._rtag = options.tag 
    rule.src = options.src
    nameRule(rule)
    setmetatable(rule,{__tostring = function(rule) return rule.rname end})
    return rule
  end

  function ER:createRule(cond,action,p)
    local options = table.copyShallow(p.co.options or {})
    local rule = options.rule
    if rule==nil then errorf(rule,p,"No rule object") end
    assert(rule)
    options.rule = nil
    rule.instance = 0
    rule._enabled = true
  
    nameRule(rule)
    
    local triggers = { daily=nil, interv=nil, timers={}, srct={}, dt = {}, opts = { src = rule.src, rule = rule } }
    getTriggers(cond,triggers)
    local trs = triggers.srct
    
    rule.triggers = trs
    rule.catchup = triggers.catchup
    rule.dailys = {}          -- daily times and between times
    rule._dailyTimers = {}    -- refs to emitted daily timers (for cancellation)
    rule._timers = {}         -- refs to emitted timers, ex posts (for cancellation)
    rule.evhandlers = {}
    
    rule.fun = compile({type='rule_action',cond=cond,action=action},triggers.opts)
    
    if not (next(trs) or triggers.daily or triggers.interv or #triggers.timers>0) then errorf(rule,cond,"No triggers in rule") end
    if not (not(triggers.daily and triggers.interv)) then errorf(rule,cond,"Only one @daily or @@interval in a rule is supported") end
    
    local dailys = triggers.timers
    if triggers.daily then table.insert(dailys,1,triggers.daily) end
    rule.dailys = dailys
    
    if triggers.interv then
      if options.ruleTrigger==nil then options.ruleTrigger=false end
      local ev = {type='%interval%',id=rule.id,_sh=true}
      local fun = function(env) return rule.start0(env.event,nil,env.p) end
      local handler = fibaro.event(ev,fun)
      rule.evhandlers[ev] = {fun,handler}
      rule.autostart = function()
        local t,delay = triggers.interv(),0
        if t < 0 then t=-t delay = (os.time() // t + 1)*t - os.time() end
        setTimeout(function() rule._post(ev,delay,"@@") end,0)
        return rule
      end
      if rule._enabled then rule.autostart() end
    else -- interval trigger disables all other triggers for rule
      for evid,t in pairs(trs) do
        local fun = function(env) 
          if triggers.dt[evid] then rule._setupDailys(false) end
          return rule.start0(env.event,evid,env.p) 
        end
        local handler = fibaro.event(t,fun)
        rule.evhandlers[t] = {fun,handler}
      end
    end

    -- public rule functions
    function rule.start(...) local args = {...} setTimeout(function() rule.start0(table.unpack(args)) end,1) return rule end
    function rule.name(name) rule._name = name; nameRule(rule) return rule end
    function rule.tag(tag) rule._rtag = tag; return rule end
    function rule.log(tag) rule._ltag = tag; return rule end
    function rule.mode(mode) rule._mode = mode; return rule end -- 'killOthers', 'killSelf'
    function rule.enable() 
      if rule._enabled then return end 
      if not evOpts(options.silent,debug.silent,false) then LOG("%s %s",ER.color("lightgreen","Enabled"),rule.rname) end
      rule._enabled = true
      for _,eh in pairs(rule.evhandlers) do eh[2].enable() end
      return rule.autostart and rule.autostart() or rule
    end
    function rule.disable()
      if not rule._enabled then return end
      if not evOpts(options.silent,debug.silent,false) then LOG("%s %s",ER.color("salmon","Disabled"),rule.rname) end
      rule._enabled = false
      rule.stop()
      for _,eh in pairs(rule.evhandlers) do eh[2].disable() end
      return rule 
    end
    function rule.isEnabled() return rule._enabled end
    function rule.print() print(self) return rule end
    function rule.delete()
      rule.disable()
      for event,eh in pairs(rule.evhandlers) do
        fibaro.removeEvent(event,eh[1])
      end
      rules[rule.id] = nil
    end
    function rule.stop()
      rule._clearDailyTimers() 
      rule._clearTimers() 
      return rule
    end
    function rule.processes() printProcesses(rule) return rule end
    function rule.info() printInfo(rule) return rule end

    function rule.recompile() -- recompile rule code, replacing old rule with new rule
      rule.stop()
      local nr = rule.compile(rule.src,triggers.opts)
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
    
    rule.runners = {}
    local coroutine = ER.coroutine 
    local runCoroutine = ER.runCoroutine

    function rule.start0(ev,id,vars)
      ev = ev or {type='start'}
      ruleStats.runs = ruleStats.runs + 1
      rule.last = os.time()
      --if rule._mode == 'killOthers' then rule.stop() -- moved to success/fail
      --elseif
      if rule._mode == 'killSelf' and  next(rule.runners) then return rule end

      if not getmetatable(ev) then eventCustomToString(ev) end 

      local co = coroutine.create(rule.fun)
      rule.instance = rule.instance+1
      local instname = fmt("[Rule:%s:%s]",rule._name,rule.instance)
      co.name = setmetatable({},{__tostring = function() return instname end})
      co.rtd.rule = rule
      rule.runners[co] = 'running'
      co._stats = { name = co.name }
      co._stats.status,co._stats.time = 'started',os.time(); updateRuleStats()
      co._stats.start = os.time()
      addRuleStats(co._stats)
      if #ruleStats.last > 80 then table.remove(ruleStats.last,81) end -- keep last 10

      local env = {event=ev,evid=id or '%%START%%',vars=vars,rule=rule,name=co.name,co=co,instance=rule.instance}
      local locals = co.rtd.env -- local variables
      locals.push('env',env)
      for k,v in pairs(vars or {}) do locals.push(k,v) end
      
      local conditionSucceeded = false
      function co._action(ok,msg)
        conditionSucceeded = ok
        co._stats.status,co._stats.time = "true" or "fail",os.time(); updateRuleStats()
        if ok then ruleStats.successes = ruleStats.successes + 1
          if rule._mode == 'killOthers' then rule.stop() end
        else ruleStats.fails = ruleStats.fails + 1 end

        local log = false
        if ok then log = evOpts(options.ruleTrue,debug.ruleTrue)
        else log = evOpts(options.ruleFalse,debug.ruleFalse) end
        if log then
          local logf = options.runRuleLogFun or settings.runRuleLogFun or runRuleLogFun
          logf(co,rule,ok,ev)
        end
      end
      function co.LOG(...) LOG("%s>> %s",co.name,fmt(...)) end
      function co.ERROR(...) 
        co._stats.status,co._stats.time = 'error',os.time(); updateRuleStats()
        rule.errors=(rule.errors or 0)+1
        ruleStats.errors = ruleStats.errors + 1
        local errMsg = LOGERR("%s>> %s",co.name,fmt(...))
        fibaro.post({type='ERerror',id=rule.id,msg=errMsg,_sh=true})
        if rule.errors > 2 then
          rule.disable()
          LOGERR("%s>> Too many errors (3), rule disabled",co.name)
        end
      end

      options.trace=rule._trace
      options.debug=rule._debug
      
      local suspendMsg = {
        ['%wait%'] = function(delay,msg) return fmt("wait %s %s",hms(delay/1000),msg or "") end,
        ['%callback%'] = function(delay,msg) return msg or "callback" end,
      }
      
      function options.suspended(typ,...)
        co._stats.status,co._stats.time = 'suspended',os.time(); updateRuleStats()
        rule.runners[co] = 'suspended'
        local sm = suspendMsg[typ]
        if sm then co.LOG("suspended %s - %s",conditionSucceeded and "action" or "triggered",sm(...))
        else
          co.LOG("=> %s [%s,suspended]",argsStr(typ,...),conditionSucceeded)
        end
      end
      
      function options.success(...)
        rule.runners[co] = nil
        co._stats.status,co._stats.time = conditionSucceeded and 'done' or 'fail',os.time(); updateRuleStats()
        if evOpts(conditionSucceeded,options.ruleResult,debug.ruleResult) then co.LOG("result %s",co.name,argsStr(...)) end
        if rule.resultHook then rule.resultHook(conditionSucceeded,...) end
      end
      
      function options.error(err) rule.runners[co] = nil co.ERROR("%s",err) end
      
      if evOpts(options.ruleTrigger,debug.ruleTrigger) then co.LOG("triggered %s",tostring(ev) // settings.truncStr) end
      co._env = env
      runCoroutine(co,options,env)
      return rule
    end -- start
    
    -- Internal rule housekeeping functions
    function rule._setTimeout(fun,time,descr) 
      local ref = setTimeout(fun,time)
      rule._timers[ref] = {descr or "timer",os.time()+time/1000}
      return ref
    end
    function rule._clearTimeout(ref)
      local doc = rule._timers[ref]
      if doc then clearTimeout(ref) end
    end

    --local function postLog(_,str) co.LOG(str) end

    function rule._post(ev,time,descr,p)
      local ref,t = nil,nil
      ref,t = fibaro.post(ev,time,descr,function() if ref then rule._timers[ref]=nil end end,function(_,str) p.co.LOG(str) end)
      if ref then 
        rule._timers[ref] = {descr or "post",t} 
      end
    end
    function rule._cancelPost(ref)
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
        rule.start0({type='daily',id=rule.id,time=time})
        rule._dailyTimers[ref]=nil
      end,delay*1000)
      rule._dailyTimers[ref]={'daily',time}
    end
    function rule._setupDailys(catch) setupDailys(rule,catch) end
    
    if #dailys>0 then rule._setupDailys(true) end
    
    function rule.evalPrint() nameRule(rule) if not options.silent then LOG("%s %s %s",ER.color("lightgreen","Defined"),rule.rname,rule.src:gsub("\n[%s%c]*","") // settings.truncLog) rule.evalPrint=nil end end

    rules[rule.id] = rule
    return rule
  end
  
end