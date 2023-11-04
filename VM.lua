fibaro.__ER  = fibaro.__ER or { modules={} }

function fibaro.__ER.modules.vm(ER)
  
  local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
  PrintBuffer,sunData,LOG,LOGERR,htmlTable,evOpts,eventCustomToString =
  table.unpack(ER.utilities.export)
  
---@diagnostic disable-next-line: deprecated
  local maxn = table.maxn
  local coerce = fibaro.EM.coerce
  local vars,triggerVars = ER._vars,ER._triggerVars
  local fmt = string.format
  local settings = ER.settings

  local function errorf(p,fm,...)
    local dbg = p.fun.dbg[p.fun.code[p.pc]]
    dbg = dbg and dbg.d or {}
    local err = errorMsg{type="Runtime",msg=fmt(fm,...),from=dbg.from,to=dbg.to,src=p.fun.src,rule=p.rule}
    e_error(err) 
  end
  
  local function Environment()
    local self = { }
    local vars = {}
    function self.popframe() vars = vars.__next or {} end              -- pop frame
    function self.pushframe() vars.__next = {} vars = vars.__next end  -- add frame
    function self.get(v)  -- lookup var in nested environments
      local vf = vars 
      while vf.__next do if vf[v] then return vf[v] end vf = vf.__next end
      return vf[v] 
    end
    function self.push(v,val) vars[v] = {val} end                      -- push var in current environment
    function self.set(v,val) -- set var in nested environments
      local vf = vars 
      while vf.__next do if vf[v] then vf[v][1]=val; return true end vf = vf.__next end
      if vf[v] then vf[v][1]=val; return true else return false end
    end 
    return self
  end
  
  local Script = {}
  local _DflSc = { 
    _post = function(ev,t,dscr,p) return fibaro.post(ev,t) end, 
    _cancelPost = function(ref) return fibaro.cancel(ref) end, 
    _setTimeout = function(fun,delay,descr) return setTimeout(fun,delay) end,
    _clearTimeout = function(ref) return clearTimeout(ref) end,
  } -- default script context, delas with variables timers etc for rules, coroutines, and plain functions
  function Script.get(name) return vars[name] or {_G[name]} end
  function Script.set(name,value) 
    local v,old = vars[name],nil
    if v then old=v[1] v[1]=value else vars[name]={value} end
    return true,old
  end
  function Script.post(p,event,time,descr) return (p.rule or p.co or _DflSc)._post(event,time,descr,p) end
  function Script.cancel(p,event,time,descr) return (p.rule or p.co or _DflSc)._cancelPost(event) end
  function Script.setTimeout(p,fun,time,descr) return (p.rule or p.co or _DflSc)._setTimeout(fun,time,descr) end
  function Script.clearTimeout(p,ref) return (p.rule or p.co or _DflSc)._clearTimeout(ref) end
  function Script.print(...) print(...) end
  ER.Script = Script

  local instr,ilog,errh = {},{},{}
  local PA = {}
  function instr.push(i,st)     st.push(i[3]) end
  function instr.pop(i,st)      st.pop() end
  function instr.jmp(i,st,p)    p.pc = p.pc + i[3]-1 end
  function instr.jmpp(i,st,p)   st.pop(); p.pc = p.pc + i[3]-1 end
  function instr.jmpf(i,st,p)  local v = st.peek() if not v then p.pc = p.pc + i[3]-1 else st.pop() end end
  function instr.jmpfip(i,st,p)local v = st.peek() if not v then p.pc = p.pc + i[3]-1 st.pop() end end
  function instr.jmpfp(i,st,p) local v = st.pop() if not v then p.pc = p.pc + i[3]-1 end end
  function instr.jmpt(i,st,p)  local v = st.peek() if v then p.pc = p.pc + i[3]-1 else st.pop() end end
  function instr.add(i,st)     local b,a = st.pop(),st.pop() PA={a,b} st.push(a+b) end 
  function instr.sub(i,st)     local b,a = st.pop(),st.pop() PA={a,b} st.push(a-b) end 
  function instr.mul(i,st)     local b,a = st.pop(),st.pop() PA={a,b} st.push(a*b) end
  function instr.div(i,st)     local b,a = st.pop(),st.pop() PA={a,b} st.push(a/b) end 
  function instr.mod(i,st)     local b,a = st.pop(),st.pop() PA={a,b} st.push(a%b) end 
  function instr.eq(i,st)      local b,a = st.pop(),st.pop() PA={a,b} st.push(a==b) end 
  function instr.neq(i,st)     local b,a = st.pop(),st.pop() PA={a,b} st.push(a~=b) end 
  function instr.lt(i,st)      local b,a = coerce(st.pop(),st.pop()) PA={a,b} st.push(a<b) end 
  function instr.lte(i,st)     local b,a = coerce(st.pop(),st.pop()) PA={a,b} st.push(a<=b) end 
  function instr.gt(i,st)      local b,a = coerce(st.pop(),st.pop()) PA={a,b} st.push(a>b) end 
  function instr.gte(i,st)     local b,a = coerce(st.pop(),st.pop()) PA={a,b} st.push(a>=b) end 
  function instr.f_not(i,st)   local a = st.pop() st.push(not a) end
  function instr.conc(i,st)    local b,a = st.pop(),st.pop() st.push(tostring(a) .. tostring(b)) end
  function instr.neg(i,st)     local a = st.pop() PA={a} st.push(-a) end
  function instr.t_today(i,st) local o = st.pop() PA={o} st.push(midnight()+o) end
  function instr.t_next(i,st)  local t = st.pop() PA={t} t=t+midnight(); st.push(t >= os.time() and t or t+24*3600) end
  function instr.t_plus(i,st)  local t = st.pop() PA={t} st.push(os.time()+t) end
  function instr.gv(i,st)      
    local name = i[3]; PA={name} st.push(marshallFrom(fibaro.getGlobalVariable(name)))
  end
  function instr.qv(i,st)      local name = i[3]; PA={name}   st.push(quickApp:getVariable(name)) end
  function instr.var(i,st,p)   local name = i[3]; PA={name}   st.push((p.env.get(name) or Script.get(name) or {})[1]) end
  instr['local'] = function(i,st,p) local name = i[3]; PA={name} p.env.push(name,nil) end

  function ER.returnMultipleValues(st,v0,...)
    st.push(v0)
    local args = {...}
    for i=1,maxn(args) do st.push0(args[i]) end
    return 'multiple_values' 
  end
  
  function instr.call(i,st,p)
    local args = st.popm(i[4])
    local name,f = i[3],nil
    if name then 
      PA={name}
      f = (p.env.get(name) or Script.get(name) or {})[1]
      if type(f)~="function" then errorf(p,"'%s' is not a function",name) end
    else 
      f = st.pop()
      if type(f)~="function" then errorf(p,"'%s' is not a function",tostring(f)) end
    end
    local res = {pcall(f,table.unpack(args))}
    if not res[1] then errorf(p,res[2]) end
    if res[2] == '%magic_suspend%' then  -- Ok, this is the way to signal that the fun is async...
      local cb,msg = res[3],res[5]
      p.yielded = true;
      local timeout,tref = res[4] or settings.asyncTimeout,nil  -- default timeout in milliseconds
      cb[1] = function(...)                     -- second value returned is a basket we put the callback function in
        cb[2]=true
        if tref == nil then return end          -- ignore callback if timeout has expired
        Script.clearTimeout(p,tref)
        ER.runCoroutine(p.co,nil,...)           -- no one interested in return result...
      end
      tref = Script.setTimeout(p,function() --  timeout handler
        cb[2] = true
        tref = nil
        p.co.options.error(fmt("Timeout for function '%s'",name or tostring(f)))
      end,
      timeout) 
      st.push('%callback%'); return true -- ToDo add msg
    end
    st.push(res[2])
    if #res > 2 then for i=3,#res do st.push0(res[i]) end end
  end
  
  function instr.return0(i,st,p) st.push(nil) return true end
  function instr.return1(i,st,p) 
    local s = st.popm(1) -- get ev. multiple values
    if #s>1 then st.push(s) return 'multiple_values' else st.push(s[1]) return true end 
  end
  function instr.returnm(i,st,p) st.push(st.popm(i[3])) return 'multiple_values' end
  function instr.table(i,st)  -- Create table and push on stack
    local keys = i[3]
    local i,n = 1,#keys     -- ['%comp%','%value%',...] for computed indexes, [<key1>,<key2>,...] for named or integer indexes
    local args = st.lift(n) -- Values on stack in same order as keys. Note that computed indexes have 2 consecutive entries on stack
    local t = {}
    while i <= n do
      local k = keys[i]
      if k == '%comp%' then
        k = args[i]
        i=i+1
      end
      t[k] = args[i]
      i = i+1
    end
    st.push(t)
  end
  function instr.mvstart(i,st,p) p.mvs = p.mvs or {} p.mvs[i[3]] = st.size() end
  function instr.mvend(i,st,p) 
    st.p2px()
    local ss = p.mvs[i[3]]; 
    p.mvs[i[3]] = {ss,st.size()} 
  end
  function instr.mv(i,st,p)
    local tag,id,size = i[3],i[4],i[5]
    local sf = p.mvs[tag]
    local vp = sf[1]+id
    -- st.dump()
    -- print(sf[2],sf[1],id,vp,size)
    local v = vp <= sf[2] and st.get(vp) or nil            -- get value from stack
    if i[6] then p.mvs[tag] = nil st.setSize(sf[1]) end    -- last mv, trim away extra values
    st.push(v)
  end
  
  function instr.setvar(i,st,p) 
    local name,const,pop,v = i[3],i[4],i[5],nil
    if const then v = const[1] if not pop then st.push(v) end
  elseif pop then v=st.pop()
  else v = st.peek() end
  if p.env.set(name,v) then return end -- set in (rule) local environment
  local flag,old = Script.set(name,v)   -- set in (rule) global environment
  if flag and v~=old and triggerVars[name] then    -- trigger variable, emit event
    local ev = eventCustomToString({type='trigger-variable',name=name,value=v,old=old})
    Script.post(p,ev,0,"trigger variable")
  end
end
function instr.setgv(i,st,p) 
  local name,const,pop,v = i[3],i[4],i[5],nil
  if const then 
    v = const[1] 
    if not pop then st.push(v) end
  elseif pop then v=st.pop()
  else v = st.peek() end
  fibaro.setGlobalVariable(name,marshallTo(v))
end
function instr.setqv(i,st,p) 
  local name,const,pop,v = i[3],i[4],i[5],nil
  if const then 
    v = const[1] 
    if not pop then st.push(v) end
  elseif pop then v=st.pop()
  else v = st.peek() end
  quickApp:setVariable(name,v)
end
function instr.aref(i,st,p) 
  local key; if i[4] then key = i[4][1] else key = st.pop() end
  local tab = st.pop()
  if key == nil then errorf(p,"key is nil for arrray index") end
  if tab == nil then errorf(p,"table is nil for array reference") end
  ---@diagnostic disable-next-line: need-check-nil
  st.push(tab[key])
end
function instr.aset(i,st)
  local key,const,pop,var,v = i[3],i[4],i[5],i[6],nil
  if const then v = const[1] else v = st.pop() end
  if key==nil then key = st.pop() end
  local tab = st.pop() tab[key] = v
  if not pop then st.push(v) end
end
function instr.eventm(i,st,p)
  local env = p.args[1]
  st.push(i[3]==env.evid)
end
function instr.prop(i,st,p)
  local ids,prop,env = st.pop(),i[3],p.args[1] or {}
  local isTable,n,mapf,v = type(ids) == 'table',1,nil,nil
  if isTable then n = maxn(ids) end
  if ids==nil or n == 0 then errorf(p.args[1] or p,"No devices found for :%s",prop) end
  local function itemFun(e) 
    local dev = ER.getDeviceObject(e)
    if not dev then errorf(p,"%s is not a valid device",tostring(dev)) end
    if not dev:isProp(prop) then errorf(p,":%s is not a valid device property for %s",prop,dev) end
    return dev.getProp[prop](dev,prop,env.event or {})
  end
  if ER.propFilters[prop] then
    local filter = ER.propFilters[prop]
    ids = isTable and ids or {ids}
    st.push(filter(ids))
    return
  end
  if isTable then
    local dev0 = ER.getDeviceObject(ids[1]) -- first item decides map function
    local mapf = dev0 and dev0.map[prop] or function(f,l) local r={} for i=1,n do r[#r+1]= f(l[i]) end return r end
    v = mapf(itemFun,ids)
  else v = itemFun(ids) end
  st.push(v)
end

function instr.putprop(i,st,p)
  local value,ids,prop = st.pop(),st.pop(),i[3]
  local isTable,n,v = type(ids) == 'table',1,nil
  if isTable then n = maxn(ids) end
  if ids==nil or n == 0 then errorf(p.args[1] or p,"No devices found for :%s",prop) end
  local function itemFun(e) 
    local dev = ER.getDeviceObject(e)
    if not dev then errorf(p,"%s is not a valid device",tostring(dev)) end
    if not dev:isProp(prop) then errorf(p,":%s is not a valid device property for %s",prop,dev) end
    return dev.setProp[prop](dev,prop,value)
  end
  if isTable then
    for i=1,n do v = itemFun(ids[i]) end
  else v = itemFun(ids) end
  st.push(v)
end
function instr.betw(i,st,p)
  local t2,t1,time=tonumber(st.pop()),tonumber(st.pop()),os.time()
  if t1 == nil then errorf(p,"Bad first argument to between '..' - not a number") end
  if t2 == nil then errorf(p,"Bad second argument to between '..' - not a number") end
  if t1  > 24*60*60 then
    st.push(t1 <= time and t2 >= time)
  else
    local midnight = midnight()
    local now = time-midnight
    --print(os.date("%H:%M:%S",t1+midnight),os.date("%H:%M:%S",time),os.date("%H:%M:%S",t2+midnight))
    if t1<=t2 then st.push(t1 <= now and now <= t2) else st.push(now >= t1 or now <= t2) end 
  end
end
function instr.betwo(i,st) end
function instr.daily(i,st,p) 
  local env = p.args[1]
  st.push(env.event.type == 'daily' and env.event.id == env.rule.id)
end
function instr.interv(i,st,p)
  local t = math.abs(st.pop())
  Script.post(p,{type='%interval%',id=p.rule.id,_sh=true},t,'@@')
  st.push(true)
end
function instr.match(i,st) end
function instr.assign(i,st) end
function instr.addto(i,st) local v = st.pop(); PA={v}; st.push(v+i[3]) end
function instr.subto(i,st) local v = st.pop(); PA={v}; st.push(i[4] and v-i[3] or i[3]-v) end
function instr.multo(i,st) local v = st.pop(); PA={v}; st.push(v*i[3]) end
function instr.divto(i,st) local v = st.pop(); PA={v}; st.push(i[4] and v/i[3] or i[3]/v) end 
function instr.modto(i,st) local v = st.pop(); PA={v}; st.push(i[4] and v%i[3] or i[3]%v) end

--function instr.redaily(i,st)      st.push(Rule.restartDaily(st.pop())) end
function instr.eval(i,st)           st.push(ER.eval(st.pop(),{silent=true})) end

function instr.rule(i,st,p) st.push(ER:createRule(i[3],i[4],p)) end
function instr.rule_action(i,st,p)
  local cond = st.popm(1)
  if cond[1] then
    p.co._action(true,cond[2])
  else
    p.co._action(false,cond[2])
    st.push(false)
    return true
  end 
end

---------------------------------------------------------------------------------------------------
-- setup debug formats for instructions
for i,_ in pairs(instr) do ilog[i] = "%s/%s" end
for i,n in pairs({
  push=1,var=1,gv=1,qv=1,jmp=1,jmpf=1,jmpt=1,jmpfp=1,jmpfip=1,jmpp=1,eventm=1,prop=1,mvstart=1,mvend=1,
  setvar=3,aset=3,call=2,callexpr=1,collect=2,mv=4,aref=1,addto=2,subto=2,multo=2,divto=2,modto=2,['local']=1,
  setgv=3,setqv=3,
}) do ilog[i] = "%s/%s "..string.rep("%s",n," ") end

-- setup error handlers for instructions
for _,i in ipairs({'add','sub','mul','div','mod'}) do
  errh[i] = function(i) 
    if not tonumber(PA[1]) then return fmt("%s expected number as first argument, got %s",i,type(PA[1])) end
    if not tonumber(PA[2]) then return fmt("%s expected number as second argument, got %s",i,type(PA[2])) end
  end
end
for _,i in ipairs({'addto','subto','multo','divto','modto'}) do
  errh[i] = function(i) 
    if not tonumber(PA[1]) then return fmt("%s expected number as first argument, got %s",i,type(PA[1])) end
  end
end
for _,i in ipairs({'call','callexpr','callobj',}) do
  errh[i] = function(i,err)
    local name = PA[1]
    if not (name and _G[name]) then return fmt("undefined function %s",tostring(name)) end
    return fmt("error executing function %s - %s",name,err)
    end
  end
  ------------- VM -------------
  local function encodeArgs(t) 
    local r={} for _,v in ipairs(t) do r[#r+1]=type(v)=='table' and encodeFast(v) or v end return table.unpack(r) 
  end
  local function instr2str(i)
    -- local s = i[1]
    -- local str = ilog[i[1]] or "%s/%s"
    -- local args = {encodeArgs(i)}
    return fmt(ilog[i[1]] or "%s/%s",encodeArgs(i))
  end
  
  local function traceInstr(pc,i,size,oldValue,newValue)
    return fmt("PC:%03d ST:%02d %-20s %s->%s",pc,size,instr2str(i),encodeFast(oldValue):sub(1,20),encodeFast(newValue):sub(1,20))
  end
  
  local function run2(fun,rtd,...)
    if rtd._inited then ER.returnMultipleValues(rtd.stack,table.unpack(rtd.args or {})) end
    for _,v in ipairs({...}) do rtd.stack.push0(v) end
    local code,codeLen = fun.code,#fun.code
    local p,st = rtd,rtd.stack
    local stat,res
    local trace = rtd.trace or fun.trace
    while p.pc <= codeLen and stat==nil do
      local i = code[p.pc]
      if trace then
        local prevStack,pc2,ss = st.peek(),p.pc,st.size()
        stat,res = instr[i[1]](i,st,p)
        Script.print(traceInstr(pc2,i,ss,prevStack,st.peek()))
      else
        stat,res = instr[i[1]](i,st,p)
      end
      p.pc = p.pc+1
    end
    stat = stat==nil and true or stat
    return stat,table.unpack(st.popm(1))
  end
  
  local function run(fun,rtd,...)
    ER.runningFun = fun
    ER.runningRule = rtd.rule
    rtd.args = {...}
    rtd.fun = fun
    local stat = {e_pcall(run2,fun,rtd,...)}
    if not stat[1] then
      if isErrorMsg(stat[2]) then e_error(stat[2]) end
      local pc = rtd.pc
      local i = fun.code[pc]
      local dbg = fun.dbg[i]
      local err = errh[i[1]] and errh[i[1]](i[1],stat[2]) or (stat[2].." "..i[1])
      local d = dbg and dbg.d or {}
      ER.runningFun,ER.runningRule = nil,nil
      e_error(errorMsg{type="Runtime",msg=err,from=d.from,to=d.to,rule=rtd.rule,src=fun.src})
    end
    --assert(rtd.stack.size()==0,"stack not empty")
    ER.runningFun,ER.runningRule = nil,nil
    if rtd.trace or fun.trace then print(fmt("Exit:%s %s",rtd.stack.size(),json.encode(stat))) rtd.stack.dump() end
    if stat[2] == true then return table.unpack(stat,3) end
    if stat[2] == 'multiple_values' then return table.unpack(stat[3]) end
  end
  
  function ER:addInstr(name,fn,log)
    instr[name] = fn
    ilog[name] = log or "%s %s"
  end
  
  function ER:createFun(codestr,options)
    options = options or {}
    local fun = {
      code = codestr.code,
      dbg = codestr.dbg,
      src = codestr.src,
      name = codestr.name,
    }
    function fun:run(rtd,...)
      rtd = rtd or {
        pc = 1,
        stack = stack(),
        env = Environment(), -- local vars
      }
      return run(self,rtd,...) 
    end
    
    function fun.codeList()
      local res = {}
      for pc,i in pairs(fun.code) do
        res[#res+1] = fmt("%03d: %s",pc,instr2str(i))
      end
      return table.concat(res,"\n")
    end
    setmetatable(fun,{
      __call=function(... ) return fun:run(nil,...) end,
      __tostring=function(f) return fmt("[fun %s,size:%s]",f.name,#f.code) end
    })
    return fun
  end
  
  --------- ER coroutine support ---------
  -- works like Lua coroutines
  
  ER.coroutine = {}
  function ER.coroutine.create(efun)
    local co = {
      fun = efun,
      status = 'suspended',
      rtd = {
        pc = 1,
        stack = stack(),
        env = Environment(),
        _inited = false,
      }
    }
    setmetatable(co,{
      __tostring=function(co) return fmt("[co %s,pc:%s,st:%s]",co.fun,co.rtd.pc,co.rtd.stack.size()) end
    })
    return co
  end
  function ER.coroutine.status(co) return co.status end
  function ER.coroutine.resume(co,...)
    if co.status =='dead' then return false,"cannot resume dead coroutine" end
    co.status = 'running'
    local stat = {e_pcall(run,co.fun,co.rtd,...)}
    if stat[1] == false then
      co.status = 'dead'
      return false,stat[2]
    end
    if co.rtd.yielded then
      co.status = 'suspended'
      co.rtd.yielded = false
      co.rtd._inited = true
    else
      co.status = 'dead'
    end
    return true,table.unpack(stat,2)
  end
  
  --function ER.coroutines.yield(...) end -- only called from within code
  
end