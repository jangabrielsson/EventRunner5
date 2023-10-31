---@diagnostic disable: undefined-global
fibaro.__ER  = fibaro.__ER or { modules={} }
local version = 0.012
QuickApp.E_SERIAL,QuickApp.E_VERSION,QuickApp.E_FIX = "UPD896846032517892",version,"N/A"

local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
PrintBuffer,sunData,LOG,htmlTable,evOpts

local fmt = string.format
local function trim(str) return str:gsub("^[%s%c]*(.-)[%s%c]*$","%1") end


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
      if not stat[1] then 
        return options.error(stat[2])
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
      e_error(err)
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
  fibaro.debugFlags.onaction=false
  
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
  PrintBuffer,sunData,LOG,htmlTable,evOpts =
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
  function er.compile(str,options)
    options = options or {}
    options.src = str
    local p = ER:parse(str,options)
    return ER:compile(p,options)
  end
  function er.eval(name,str,options)         -- top-level eval for expressions - used by rule(...)
    if type(name)=='string' and type(str)=='string' then
      options = options or {}
      options.name = name
    else str,options = name,str end
    options = options or {}
    
    function options.suspended(...)         -- expression waits - log nothing
      --local res = {...}
      --pr:print(name,">",argsStr(table.unpack(res,2)),"[suspended]")
      return nil
    end
    
    function options.success(success,...)   -- expression succeeded - log results
      local res = {...}
      if #res==1 and type(res[1])=='table' and res[1].evalPrint then -- result is a table with evalPrint method
        res[1].evalPrint(res[1],str)                                 --- let object control its own print
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
  
  er.variable = ER.vars
  er.triggerVar = ER.triggerVars
  function er.defvar(name,init) ER.vars[name]=init end
  
  er.defTriggerVar = ER.defTriggerVar
  er.deftriggervar = ER.defTriggerVar
  er.rule = er.eval
  er.defvars = function(t) for k,v in pairs(t) do er.defvar(k,v) end end
  er.reverseMapDef = ER.reverseMapDef
  er.coroutine = ER.coroutine
  er.pcall = e_pcall
  er.xerror = e_error
  er._utilities = ER.utilities
  er.debug,er.settings = ER.debug,ER.settings
  
  for k,v in pairs({
    listRules= ER.listRules,listVariables=ER.listVariables,listTimers=ER.listTimers,
  }) do er[k] = v; ER.vars[k]=v end
  ER.vars.rule = function(i) return ER.rules[i] end

  er.Util = {
    defTriggerVar = ER.defTriggerVar,
    defVar = er.defvar,
    defvars = er.defvars,
    reverseMapDef = ER.reverseMapDef
  }
  
  for c,f in pairs(ER.constants) do ER:addInstr(c,f,"%s/%s") end
  for c,f in pairs(ER.builtins) do ER:addInstr(c,f,"%s/%s") end
  
  function er.defmacro(name,str) -- Simple macro functions with optional arguments
    local pattern,params = "([%w_]+)",{}
    if name:find("%(") then pattern = pattern.."(%b())" end
    local a,b = name:match(pattern)
    if not a then error("Bad macro name") end
    if b then
      params = b:sub(2,-2):split(",")
    end
    return function(code)
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
  end
  
  local uiHandler = self.UIHandler -- Handles button presses from ER QA UI
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
  
  function self:eval(str) -- Terminal eval function
    str = trim(str)
    local opt = {}
    if str=="" then return end
    local r,o = str:match("(.*)///(.*)")
    if r then
      local stat,err = e_pcall(function()
        opt = er.eval(o,{silent=true})
      end)
      if type(opt)~='table' or not stat then self:error("///option",err) end
      str=r
    end
    local stat,err = e_pcall(function()
      er.eval(str,opt)
    end)
    err = tostring(err)
    err = err:gsub("\n","</br>")
    err = err:gsub(" ","&nbsp;")
    if not stat then self:error(err) end
  end
  
  return ER
end