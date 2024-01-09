--[[
Offical bughunters:
@Sjakie
@Neo Andersson
@ChristianSogaard
@Pica2017
--]]

---@diagnostic disable: undefined-global
fibaro.__ER  = fibaro.__ER or { modules={} }
local version = 1.01
QuickApp.E_SERIAL,QuickApp.E_VERSION,QuickApp.E_FIX = "UPD896846032517892",version,"N/A"

local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
PrintBuffer,sunData,LOG,LOGERR,htmlTable,evOpts

local fmt = string.format
local function trim(str) return str:gsub("^[%s%c]*(.-)[%s%c]*$","%1") end
local ER = fibaro.__ER

function fibaro.__ER.modules.engine(ER)
  local Script = ER.Script
  local fmt= string.format
  local debugf = ER.debug
  
  local function createProps(getProps,setProps,helpers)
    ER.definePropClass('StdPropObject')
    ER.propHelpers = helpers
    function StdPropObject:__init(id)
      PropObject.__init(self)
      self.id = id
      --setmetatable(self,{__tostring = function(t) return "device:"..tostring(self.id) end})
    end
    function StdPropObject:__tostring() return "device:"..tostring(self.id) end
    for gp,map in pairs(getProps) do
      local m = map
      StdPropObject.getProp[gp] = function(id,prop,event) return m[2](id.id,m[3],event)  end-- fun(id,prop,event)
      if m[5] then
        StdPropObject.trigger[gp] = function(self,id,gp) return {type=m[1], id=id, property=m[3]} end
      else StdPropObject.trigger[gp] = true end
      if m[4] then StdPropObject.map[gp] = m[4] end
    end
    for gp,map in pairs(setProps) do
      local m = map
      local sf,cmd = m[1],m[2]
      StdPropObject.setProp[gp] = function(id,prop,val) return sf(id.id,cmd,val) end
    end
    local stdPropObject = StdPropObject()
    ER.stdPropObject = stdPropObject
    
    local keyAttrMT = { 
      __tostring = function(t) return string.format("%s:%s",t.id,t.attr) end,
      __cmpVal = function(a) 
        return tostring(a)
      end 
    }
    function stdPropObject.getProp.key(id,prop,event)
      return setmetatable({id=event.value.keyId,attr=event.value.keyAttribute},keyAttrMT) 
    end
    function stdPropObject.trigger.key(self,id) return {type='device', id=id, property='centralSceneEvent'} end
  end
  
  ------- Rule variables -----------------------------------
  local vars,triggerVars = ER.vars,ER.triggerVars
  local reverseVarTable = {}
  function ER.defVar(name,init) vars[name] = init end
  function ER.defTriggerVar(name,init) triggerVars[name] = init end
  function ER.defvars(tab) for var,val in pairs(tab) do ER.defVar(var,val) end end
  function ER.reverseMapDef(table) ER._reverseMap({},table) end
  function ER._reverseMap(path,value)
    if type(value) == 'number' then reverseVarTable[tostring(value)] = table.concat(path,".")
    elseif type(value) == 'table' and not value[1] then
      for k,v in pairs(value) do table.insert(path,k); ER._reverseMap(path,v); table.remove(path) end
    end
  end
  function ER.reverseVar(id) return reverseVarTable[tostring(id)] or id end
  
  ----------------------------------------------------------------------------------
  -- Runnning a corutine with ER "behaviour" - waits, callbacks etc.
  -- options = { success = function(success,...), error = function(err), suspended = function(success,...), trace = bool }
  local function runCoroutine(co,options,...)
    options = options or co.options
    local coroutine = ER.coroutine
    local function runner(...)
      local stat = {coroutine.resume(co,...)}
      if not stat[1] then
        return options.error(stat[2])
      else
        if coroutine.status(co)=='suspended' then
          options.suspended(table.unpack(stat,2))
          local action = stat[2]
          if action == '%wait%' then
            Script.setTimeout(co.rtd,runner,stat[3])
            local msg = stat[4] or stat[2]
            return false,msg
          end -- ignore 'callback'
          return false,table.unpack(stat,2)
        else
          options.success(table.unpack(stat,2))
          return true,table.unpack(stat,2)
        end
        
      end
    end
    co.options = options
    co.rtd.trace = options.trace
    co.rtd.co = co
    return runner(...)
  end
  ER.runCoroutine = runCoroutine
  
  local function eval(str,options)
    assert(type(str)=='string',"first argument to eval must be a string (eventscript)")
    local str2 = str:gsub("(\xC2\xA0)","<*>")
    if str2 ~= str and not ER.settings.ignoreInvisibleChars then
      error("String contains illegal chars: "..str2)
    end
    str = trim(str)
    local coroutine = ER.coroutine
    options = options or {}
    options.src = str
    local stat,tkns = pcall(ER.tokenize,ER,str)
    if not stat then
      error(fmt("Token error in string '%s'\n%s",str,tkns))
    end
    local defRule =  tkns.containsOp('rule')
    if defRule then
      local rule = ER:createRuleObject(options)
      options.rule = rule
      --if not options.silent then LOG("Defining [Rule:%s:%s]...",rule._name,rule.src // settings.truncStr) end
    end
    local p = ER:parse(tkns,options)
    if options.listTree then print(json.encode(ER.simplifyParseTree(p))) end
    local fun = ER:compile(p,options)
    if fun == nil then error("can't compile "..str) end
    if options.listCode then print(fun.codeList()) end
    local co = coroutine.create(fun)
    function co._post(ev,t,descr) return fibaro.post(ev,t,descr) end
    function co._cancelPost( ) return fibaro.cancel(ref) end
    function co._setTimeout(fun,delay,descr) return setTimeout(fun,delay) end
    function co._clearTimeout(ref) return clearTimeout(ref) end
    return runCoroutine(co,options,table.unpack(options.args or {})) -- resume with handling of waits etc...
  end
  ER.eval = eval
  
  createProps(ER.setupProps())
  
  local er = ER.er
  function er.defmacro(name,str) -- Simple macro functions with optional arguments
    local pattern,params = "([%w_]+)",{}
    if name:find("%(") then pattern = pattern.."(%b())" end
    local a,b = name:match(pattern)
    if not a then error("Bad macro name") end
    if b then
      params = b:sub(2,-2):split(",")
    end
    local macro =  function(code)
      if not b then return code:gsub(a,str) end
      code = code:gsub(a.."(%b())",function(args)
        args = args:sub(2,-2):split(",")
        local subs = str
        for i,v in ipairs(params) do
          subs = subs:gsub("{{"..v.."}}",args[i])
        end
        return subs
      end)
      return code
    end
    macros[#macros+1] = macro
  end
  
  local vID = 10000
  function er.createBinaryDevice(id) 
    if not id then vID = vID + 1; id = vID end
    local d = VirtBinarySwitch(id)
    ER.utilities.emulatedDevices[id] = d
    return id
  end
  
  function er.createMultilevelDevice(id) 
    if not id then vID = vID + 1; id = vID end
    local d = VirtMultilevelSwitch(id)
    ER.utilities.emulatedDevices[id] = d
    return id
  end
end -- engine module

local function setup(ER)
  
  local midnightFuns = {}
  function ER.midnightScheduler(fun) midnightFuns[#midnightFuns+1] = fun end
  local mref = nil
  function ER.startMidnightScheduler() 
    if mref then clearTimeout(mref) end
    local d = os.date("*t")
    d.hour,d.min,d.sec = 24,0,0
    local midnxt = os.time(d)
    local function midnightLoop()
      for _,f in ipairs(midnightFuns) do f() end
      local d = os.date("*t")
      d.hour,d.min,d.sec = 24,0,0
      midnxt = os.time(d)
      mref = setTimeout(midnightLoop,(midnxt-os.time())*1000)
    end
    mref = setTimeout(midnightLoop,(midnxt-os.time())*1000)
  end
  ER.startMidnightScheduler()
  
  class 'PropObject'
  local ftype = 'func'..'tion' -- fool the autoindetation...
  
  function ER.isPropObject(o) return type(o)=='userdata' and o.__type == '%PropObject%' end
  function PropObject:__init()
    self.__type = '%PropObject%'
    -- self.getProp = self.getProp or {}
    -- self.setProp = self.setProp or {}
    -- self.trigger = self.trigger or {}
    self.__str="PropObject:"..tostring({}):match("(%d.*)")
  end
  function PropObject:isProp(prop) return self.getProp[prop] or self.setProp[prop] end
  function PropObject:isTrigger(prop) return self.trigger[prop] end
  function PropObject:getTrigger(id,prop)
    local t = self.trigger[prop]
    return t and type(t) == ftype and t(self,id,prop) or type(t) == 'table' or nil
  end
  function PropObject:__tostring() return self.__str end
  
  ER.PropObject = PropObject
  function ER.definePropClass(name)
    class(name)(PropObject)
    local cl = _G[name]
    cl.getProp,cl.setProp,cl.trigger,cl.map={},{},{},{}
  end
  
  class 'VirtDevice'
  function VirtDevice:__init(id) self.id = id self.modified=os.time() end
  function VirtDevice:call(method,...)
    local args = {...}
    if method=='turnOn' then self:turnOn() self:stateChange('state',true)
    elseif method=='turnOff' then self:turnOff() self:stateChange('state',false)
    elseif method=='setValue' then self:setValue(args[1])
    elseif method=='updateProperty' then self:updateProperty(args[1],args[2])
    else error("Unknown method "..method) end
  end
  function VirtDevice:turnOn() self:stateChange('value',true) end
  function VirtDevice:turnOff() self:stateChange('value',false) end
  function VirtDevice:setValue(value) self:stateChange('value',value) end
  function VirtDevice:updateProperty(prop,value) self:stateChange(prop,value) end
  function VirtDevice:__tostring() return self._name..tostring(self.id) end
  function VirtDevice:stateChange(prop,value)
    local old = self.props[prop]
    self.props[prop] = value
    if old ~= value then self.modified=os.time(); fibaro.post({type='device',id=self.id,property=prop,value=value,old=old}) end
  end
  function VirtDevice:get(prop) return self.props[prop] end
  
  class 'VirtBinarySwitch'(VirtDevice)
  function VirtBinarySwitch:__init(id) 
    VirtDevice.__init(self,id) self.props = {value=false,state=false} 
    self._name = "VirtBinaryDevice"
  end
  class 'VirtMultilevelSwitch'(VirtDevice)
  function VirtMultilevelSwitch:__init(id) 
    VirtDevice.__init(self,id) self.props = {value=0,state=false} 
    self._name = "VirtMultilevelDevice"
  end
  function VirtMultilevelSwitch:turnOn() self:stateChange('value',99) self:stateChange('state',true) end
  function VirtMultilevelSwitch:turnOff() self:stateChange('value',0) self:stateChange('state',true) end
end -- setup

function QuickApp:eval(str) -- Terminal eval function
  str = trim(str)
  local e_pcall = ER.utilities.e_pcall
  local opt = {}
  if str=="" then return end
  local r,o = str:match("(.*)///(.*)")
  if r then
    local stat,err = e_pcall(function()
      opt = ER.er.eval(o,{silent=true})
    end)
    if type(opt)~='table' or not stat then self:error("///option",err) end
    str=r
  end
  local stat,err = e_pcall(function()
    ER.er.eval(str,opt)
  end)
  err = tostring(err)
  err = err:gsub("\n","</br>")
  err = err:gsub(" ","&nbsp;")
  if not stat then self:error(err) end
end

----------------------------------------------------------------------------------
-- Setup engine and call main function
local EventRunnerEngineCont
function QuickApp:EventRunnerEngine(callback)
  self:debug("Initializing EventRunner5...")
  function self.initChildDevices() end
  local session = math.random(1000000)
  self:internalStorageSet('Session',session)
  setTimeout(function()
    if self:internalStorageGet('Session') ~= session then
      self:warning("Duplicate QA instance - disabling QA")
      if fibaro.doppelganger then fibaro.doppelganger() end
      fibaro.sleep(500)
      self:setEnabled(false)
      plugin.restart()
    else
      self:debug("EventRunner5 initialized")
      setInterval(function()
        self:internalStorageSet('Session',session)
      end, 2*10000)
      EventRunnerEngineCont(self,callback)
    end
  end,3*1000*(fibaro.fibemu and 0 or 1))
end
function EventRunnerEngineCont(self,callback)
  quickApp = self
  local dev = __fibaro_get_device(self.id)
  if not dev.enabled then self:debug("QA disabled"); return end
  self:setVersion("EventRunner5",self.E_SERIAL,self.E_VERSION)
  self:updateView('title','text',fmt("EventRunner5 v%0.3f",self.E_VERSION))
  local vp = api.get("/settings/info").currentVersion.version
  local a,b,c = vp:match("(%d+)%.(%d+)%.(%d+)")
  vp = tonumber(string.format("%03d%03d%03d",a,b,c))
  if vp < 5142083 then
    self:error("Sorry, EventRunner5 only works with FW v5.142.83 or later")
    return
  end
  
  local st = SourceTrigger()
  function fibaro.post(event,time,logStr,hook,customLog) return st:post(event,time,logStr,hook,customLog) end 
  function fibaro.event(event,fun) return st:subscribe(event,fun) end
  function fibaro.cancel(ref) clearTimeout(ref) end
  function fibaro.registerSourceTriggerCallback(fun) return st:registerCallback(fun) end
  function fibaro.postRemote(id,event) return st:postRemote(id,event) end
  st:run()
  
  fibaro.debugFlags.html = true
  fibaro.debugFlags.onaction=false
  
  local er = {}
  ER.settings = fibaro.settings or {}
  ER.debug = fibaro.debugFlags or {}
  -- Global debug flags, can be overridden by ruleOptions
  ER.debug.ruleTrigger    = true -- log rules being triggered
  ER.debug.ruleTrue       = true -- log rules with condition succeeding
  ER.debug.ruleFalse      = true -- log rules with condition failing
  ER.debug.ruleResult     = false -- log results of rules running
  ER.debug.evalResult     = true -- log results of evaluations
  ER.debug.post           = true -- log events being posted
  ER.debug.sourceTrigger  = true -- log incoming sourceTriggers
  ER.debug.refreshEvents  = true -- log incoming refreshEvents
  
  -- Global settings
  ER.settings.marshall       = true          -- autoconvert globalVariables values to numbers, booleans, tables when accessed
  ER.settings.systemLogTag   = nil           -- log tag for ER system messages, defaults to __TAG
  ER.settings.ignoreInvisibleChars = false   -- Check code for invisible characters (xC2xA0) before evaluating
  ER.settings.truncLog       = 100           -- truncation of log output
  ER.settings.truncStr       = 80            -- truncation of log strings
  ER.settings.bannerColor    = "orange"      -- color of banner in log, defaults to "orange"
  ER.settings.listColor      = "purple"      -- color of list log (list rules etc), defaults to "purple"
  ER.settings.statsColor     = "green"       -- color of statistics log, defaults to "green"
  ER.settings.logFunction = function(rule,tag,str) return fibaro.debug(tag,str) end -- function to use for user log(), defaults to fibaro.debug if nil
  ER.settings.asyncTimeout   = 10000         -- timeout for async functions, defaults to 10 seconds
  
  ER.er = er
  
  local vars = {}
  ER._vars = vars
  local async 
  ER.vars = setmetatable({},
  {
    __index = function(t,k) return k=='async' and async or vars[k] and vars[k][1] or nil end,
    __newindex = function(t,k,v) vars[k] = {v} end
  })
  async = setmetatable({},{
    __newindex = function(t,k,v) vars[k] = {er.async(v)} end
  })
  
  local triggerVars = {}  -- Trigger variables are marked here.
  class 'TVAL'
  function TVAL:__init(value) self.__tvvalue = value end
  ER._triggerVars = triggerVars
  ER.triggerVars = setmetatable({},
  {
    __index = function(t,k) return triggerVars[k] end,
    __newindex = function(t,k,v)
      local trig,old = false,false
      if type(v) == 'userdata' and v.__tvvalue then
        v,old,trig = v.__tvvalue,ER.vars[k],true
      end
      triggerVars[k]=true
      ER.vars[k]=v
      if trig and not table.equal(old,v) then 
        fibaro.post({type='trigger-variable',name=k,value=v,old=old,_sh=true})
      end
    end
  })
  local MTasyncCallback = {
    __call = function(cb,...)
      if not cb[1] then error("async callback not asyncronous called") end
      if not cb[2] then cb[1](...) end
    end
  }
  function ER.asyncFun(f)
    local function afun(...)
      local cb = setmetatable({},MTasyncCallback)
      local delay,msg = f(cb,...)
      return '%magic_suspend%',cb,tonumber(delay),msg
    end
    return afun
  end
  ER.builtins = {}
  ER.builtinArgs = {}
  ER.propFilters = {}
  
  local function multiLine(str)
    if not str:find("\n") then return "'"..str.."'" end
    return "\n"..str
  end
  
  function QuickApp:enableTriggerType(triggers) end
  
  ER.modules.utilities(ER) -- setup utilities, needed by all modules
  stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
  PrintBuffer,sunData,LOG,LOGERR,htmlTable,evOpts =
  table.unpack(ER.utilities.export)
  
  setup(ER)
  
  ER.modules.tokenizer(ER)
  ER.modules.parser(ER)
  ER.modules.vm(ER)
  ER.modules.builtins(ER)
  ER.modules.engine(ER)
  ER.modules.rule(ER)
  ER.modules.compiler(ER)
  
  ER.utilities.printBanner("%s, deviceId:%s, version:%s",{self.name,self.id,self.E_VERSION})
  local eval = ER.eval
  
  -- Define user functions available in main from the er.* table
  function er.runFun(str,options) return er.compile(str,options or {})() end
  function er.eval0(str,options) return eval(str,options or {}) end
  function er.compile(str,options)
    options = options or {}
    options.src = str
    local p = ER:parse(str,options)
    return ER:compile(p,options)
  end
  local macros = {}
  
  function er.eval(name,str,options)         -- top-level eval for expressions - used by rule(...)
    if type(name)=='string' and type(str)=='string' then
      options = options or {}
      options.name = name
    else str,options = name,str end
    
    for _,macro in ipairs(macros) do str = macro(str) end -- macro expand
    
    options = options and table.copy(options) or {}
    for k,v in pairs(er.ruleOpts) do if options[k]==nil then options[k]=v end end
    
    options.error = options.error or function(err)
      LOGERR("%s",err)
      e_error(err)
    end
    options.suspended = options.suspended or function(...) end       -- default, do nothing
    options.success = options.success or function(...)               -- expression succeeded - log results
      local res = {...}
      if #res==1 and type(res[1])=='table' and res[1].evalPrint then -- result is a table with evalPrint method
        res[1].evalPrint(res[1],str)                                 -- let object control its own print
      else
        if (not options.silent) and evOpts(options.evalResult,ER.debug.evalResult) then LOG(fmt("%s > %s [done]",multiLine(str),argsStr(...))) end
      end
    end
    
    local stat = {e_pcall(er.eval0,str,options)} -- This is a coroutine result; bool,bool,...
    if stat[1] then return table.unpack(stat,3) end
    e_error(stat[2])
    --options.error(stat[2])
  end
  
  er.runCoroutine = ER.runCoroutine
  function er.parse(str,options) return ER:parse(str,options or {}) end
  function er.isRule(p) return type(p)=='table' and p.type=='%RULE%' end
  ER.isRule = er.isRule
  er.definePropClass = ER.definePropClass
  
  er.variables = ER.vars
  er.triggerVariables = ER.triggerVars
  function er.defvar(name,init) ER.vars[name]=init end
  
  er.defTriggerVar = ER.defTriggerVar
  er.deftriggervar = ER.defTriggerVar
  er.rule = er.eval
  er.reverseMapDef = ER.reverseMapDef
  er.coroutine = ER.coroutine
  er.pcall = e_pcall
  er.xerror = e_error
  er._utilities = ER.utilities
  er.debug,er.settings = ER.debug,ER.settings
  er.eventToString = ER.eventToString
  function er.color(color,str) return "<font color="..color..">"..str.."</font>" end
  ER.color = er.color
  er.ruleOpts = {}
  er.startMidnightScheduler = ER.startMidnightScheduler
  er.speedTime = ER.utilities.speedTime
  er.setTime = ER.utilities.setTime
  
  for k,v in pairs({
    listRules= ER.listRules,listVariables=ER.listVariables,listTimers=ER.listTimers,
    listStats = ER.listRuleStats, stdProp = ER.stdPropObject,
    enable=ER.enable,disable=ER.disable,
    defvars = function(t) for k,v in pairs(t) do er.defvar(k,v) end end,
    async = ER.asyncFun,
  }) do er[k] = v; ER.vars[k]=v end
  ER.vars.rule = function(i) return ER.rules[i] end
  ER.vars.triggervar = ER.defTriggerVar
  
  er.Util = { 
    defTriggerVar = ER.defTriggerVar,
    defVar = er.defvar,
    defvars = er.defvars,
    reverseMapDef = ER.reverseMapDef,
  }
  
  for c,f in pairs(ER.constants) do ER:addInstr(c,f,"%s/%s") end
  for c,f in pairs(ER.builtins) do ER:addInstr(c,f,"%s/%s") end
  
  local uiHandler = self.UIHandler -- Handles button presses from ER QA UI
  function self:UIHandler(event)
    if event.deviceId == quickApp.id then
      fibaro.post({type='UI',cmd=event.elementName,value=event.values[1]}) -- cmd is buttonID
    elseif uiHandler then uiHandler(self,event) end
  end
  
  local uptime = os.time() - api.get("/settings/info").serverStatus
  local uptimeStr = fmt("%d days, %d hours, %d minutes",uptime // (24*3600),(uptime % 24*3600) // 3600, (uptime % 3600) // 60)
  ER.vars.uptimeStr = uptimeStr
  ER.vars.uptimeMinutes = uptime // 60
  
  local function starter()
    MODULES = MODULES or {}
    for _,m in ipairs(MODULES) do -- patch modules to set _inited flags
      local m0,l = m,m.loader
      m.loader = function(self,er) if not m0._inited then l(self,er) end m0._inited = true end
    end
    local main, _mainInited = self.main, false
    
    if main then -- patch main to only run once
      function self:main(er) if not _mainInited then main(self,er) _mainInited = true end end
    end
    if callback then callback(er) end -- this can add main and/or run modules
    if main and not _mainInited then  -- if we have main and not run by callback then add it to modules
      MODULES[#MODULES+1]={name='main',prio=0,loader=self.main}
    end
    table.sort(MODULES,function(a,b) return a.prio < b.prio end) -- Sort modules in priority order
    for _,m in ipairs(MODULES) do -- load modules if not already _inited
      if not m._inited then
        print("Loading rules from ",m.name)
        m.loader(self,er)
        m._inited = true
      end
    end
    return #MODULES>=1
  end
  
  LOG("Setting up rules...")
  local t0 = os.clock()
  local stat,err = pcall(starter)
  if not stat then
    fibaro.error(__TAG,"Rule setup error(s) - fix & restart...")
    fibaro.error(__TAG,"Last err:", err)
    for i,r in pairs(ER.rules) do r.disable() end
    return
  end
  if err == false then
    fibaro.error(__TAG,"No main/modules to load")
    return
  end
  local startupTime = os.clock()-t0
  ER.utilities.printBanner("Rules setup time: %.3f seconds (%s rules)",{startupTime,ER.ruleID})
  if ER.__speedTime then ER.utilities.runTimers() end
  
  return ER
end