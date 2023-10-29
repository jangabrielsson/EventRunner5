---@diagnostic disable: undefined-global
fibaro.__ER  = fibaro.__ER or { modules={} }
local version = 0.01
QuickApp.E_SERIAL,QuickApp.E_VERSION,QuickApp.E_FIX = "UPD896846032517892",version,"N/A"

  local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
  PrintBuffer,sunData,LOG
local fmt = string.format

function fibaro.__ER.modules.engine(ER)
  local Script = ER.Script
  local fmt= string.format
  
  local function createProps(getProps,setProps,helpers)    
    ER.definePropClass('StdPropObject')
    function StdPropObject:__init(id)
      PropObject.__init(self)
      self.id = id
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
  end
  
  ------- Rule variables -----------------------------------
  local vars,triggerVars = ER.vars,ER.triggerVars
  local reverseVarTable = {}
  function ER.defVar(name,init) vars[name] = init end
  function ER.defTriggerVar(name,init) ER.defVar(name,init) triggerVars[name] = true end
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
    local level = 0
    local function runner(...)
      level = level+1
      local stat = {coroutine.resume(co,...)}
      if not stat[1] then return options.error(stat[2])
      else
        if coroutine.status(co)=='suspended' then
          options.suspended(co.success==true,table.unpack(stat,2))
          local action = stat[2]
          if action == '%wait%' then
            Script.setTimeout(co.rtd,runner,stat[3])
          end -- ignore 'callback'
          return false,co.success==true,table.unpack(stat,2)
        else
          if level > 1 then options.success(co.success==true,table.unpack(stat,2))
          else return true,co.success==true,table.unpack(stat,2) end
        end
      end
    end
    co.options = options
    co.rtd.trace = options.trace
    co.rtd.co = co
    return runner(...)
  end
  ER.runCoroutine = runCoroutine
  
  local function trim(str) return str:gsub("^[%s%c]*(.-)[%s%c]*$","%1") end
  local function eval(str,options)
    assert(type(str)=='string',"first argument to eval must be a string (eventscript)")
    local str2 = str:gsub("(\xC2\xA0)","<*>")
    if str2 ~= str and not ER.settings.ignoreInvisibleChars then 
      error("String contains illegal chars: "..str2) 
    end
    str = trim(str)
    ER._lastRule = nil
    local coroutine = ER.coroutine
    options = options or {}
    options.src = str
    local tkns = ER:tokenize(str)
    local defRule =  tkns.containsOp('rule')
    options.error = options.error or function(err)
      if defRule and type(err)=='table' then 
        err.rule = err.rule or { rname = fmt("Defining [Rule:%s]",ER.nextRuleID())}
      end
      error(err)
      return false,fibaro.error(__TAG,err) 
    end
    local p = ER:parse(tkns,options)
    local fun = ER:compile(p,options)
    if fun == nil then error("can't compile "..str) end
    if options.listCode then print(fun.codeList()) end
    local co = coroutine.create(fun)
    function co._post(ev,t,dscr) return fibaro.post(ev,t) end
    function co._cancelPost( ) return fibaro.cancel(ref) end
    function co._setTimeout(fun,delay,descr) return setTimeout(fun,delay) end
    function co._clearTimeout(ref) return clearTimeout(ref) end
    return runCoroutine(co,options,table.unpack(options.args or {})) -- resume with handling of waits etc...
  end
  ER.eval = eval
    
  createProps(ER.setupProps())
end

local function setup(ER)

  local midnightFuns = {}
  function ER.midnightScheduler(fun) midnightFuns[#midnightFuns+1] = fun end
  local midnxt = (os.time() // 3600 +1)*3600
  local function midnightLoop()
    for _,f in ipairs(midnightFuns) do f() end
    midnxt = midnxt+3600
    setTimeout(midnightLoop,(midnxt-os.time())*1000)
  end
  setTimeout(midnightLoop,(midnxt-os.time())*1000)

  class 'PropObject'
  local ftype = 'func'..'tion' -- fool the autoindetation...
  
  function ER.isPropObject(o) return type(o)=='userdata' and o.__type == '%PropObject%' end
  function PropObject:__init() 
    self.__type = '%PropObject%'
    -- self.getProp = self.getProp or {}
    -- self.setProp = self.setProp or {}
    -- self.trigger = self.trigger or {}
    self.__str="PropObject:"..fibaro._orgToString({}):match("(%d.*)")
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
end

----------------------------------------------------------------------------------
-- Setup engine and call main function 
function QuickApp:EventRunnerEngine()
  quickApp = self
  self:setVersion("EventRunner5",self.E_SERIAL,self.E_VERSION)
  fibaro.debugFlags.html = true
  local ER,er = fibaro.__ER,{}
  ER.er = er
  local vars = {}
  ER._vars = vars
  ER.vars = setmetatable({},
  {
    __index = function(t,k) return vars[k] end,
    __newindex = function(t,k,v) vars[k] = {v} end
  })
  ER.triggerVars = {}  -- Trigger variables are marked here. 
  ER.builtins = {}
  ER.builtinArgs = {}
  ER.propFilters = {}
  ER.debug = {}
  ER.settings = {}

  local function multiLine(str) 
    if not str:find("\n") then return "'"..str.."'" end
    return "\n"..str
  end

  function QuickApp:enableTriggerType(triggers) fibaro.enableSourceTriggers(triggers) end

  ER.modules.utilities(ER) -- setup utilities, needed by all modules
  stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
  PrintBuffer,sunData,LOG =
  table.unpack(ER.utilities.export)

  ER.utilities.printBanner("%s, deviceId:%s, version:%s",{self.name,self.id,self.E_VERSION})

  setup(ER)

  ER.modules.tokenizer(ER) 
  ER.modules.parser(ER) 
  ER.modules.vm(ER) 
  ER.modules.builtins(ER) 
  ER.modules.engine(ER)
  ER.modules.rule(ER) 
  ER.modules.compiler(ER)
  
  local eval = ER.eval 

  -- Define user functions available in main from the er.* table
  function er.runFun(str,options) return er.compile(str,options or {})() end
  function er.eval0(str,options) return eval(str,options or {}) end
  function er.eval(name,str,options)
    if type(name)=='string' and type(str)=='string' then
      options = options or {}
      options.name = name
    else str,options = name,str end
    options = options or {}
    
    function options.suspended(...)
      --local res = {...}
      --pr:print(name,">",argsStr(table.unpack(res,2)),"[suspended]")
      return nil
    end
    
    function options.success(success,...)
      local res = {...}
      if #res==1 and type(res[1])=='table' and res[1].evalPrint then
        res[1].evalPrint(res[1],str)
      else
        if not options.silent then LOG(fmt("%s > %s [done]",multiLine(str),argsStr(...))) end
      end
    end
    
    local stat = {e_pcall(function()
      local res = {eval(str,options)}
      if res[1] then options.success(table.unpack(res,2)) end
      return table.unpack(res,3)
    end)}
    if stat[1] then return table.unpack(stat,2) end
    options.error(stat[2])
    
  end
  er.runCoroutine = ER.runCoroutine
  function er.parse(str,options) return ER:parse(str,options or {}) end
  function er.isRule(p) return type(p)=='table' and p.type=='%RULE%' end
  er.definePropClass = ER.definePropClass
  
  er.defTriggerVar = ER.defTriggerVar
  er.deftriggervar = ER.defTriggerVar
  er.rule = er.eval
  er.defvar = ER.defVar
  er.defvars = ER.defvars
  er.reverseMapDef = ER.reverseMapDef
  er.coroutine = ER.coroutine
  er.listRules,er.listVariables,er.listTimers = ER.listRules, ER.listVariables,ER.listTimers
  er.pcall = e_pcall
  er.xerror = e_error
  er._utilities = ER.utilities
  er.debug,er.settings = ER.debug,ER.settings
  
  function er.compile(str,options)
    options = options or {}
    options.src = str
    local p = ER:parse(str,options)
    return ER:compile(p,options)
  end
  
  for c,f in pairs(ER.constants) do ER:addInstr(c,f,"%s/%s") end
  for c,f in pairs(ER.builtins) do ER:addInstr(c,f,"%s/%s") end
  
  local uiHandler = self.UIHandler
  function self:UIHandler(event)
    if event.deviceId == quickApp.id then
      self:post({type='UI',cmd=event.elementName,value=event.values[1]}) -- cmd is buttonID
    elseif uiHandler then uiHandler(self,event) end
  end

  if self.main then
    LOG("Setting up rules...")
    local t0 = os.clock()
    local stat,err = pcall(function() self:main(er) end)
    if not stat then 
      print(err) 
      print("Rule setup error(s) - fix & restart...")
      return
    end
    local startupTime = os.clock()-t0
    ER.utilities.printBanner("Rules setup time: %.3f seconds",{startupTime})
  else self:debug("No main function") end
  
  return ER
end