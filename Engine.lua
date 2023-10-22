---@diagnostic disable: undefined-global
QuickApp.__ER  = QuickApp.__ER or { modules={} }

function QuickApp.__ER.modules.engine(ER)
  
  local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
    marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr =
    table.unpack(ER.utilities.export)
  
  local fmt= string.format
  
  local function createProps(getProps,setProps,helpers)   
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
    function PropObject:__tostring(obj) return obj.__str end
    
    function ER.definePropClass(name)
      class(name)(PropObject)
      local cl = _G[name]
      cl.getProp,cl.setProp,cl.trigger,cl.map={},{},{},{}
    end
    
    ER.definePropClass('StdPropObject')
    function StdPropObject:__init(id)
      PropObject.__init(self)
      self.id = id
    end
    function StdPropObject:__tostring() return "device:"..tostring(self.id) end
    for gp,map in pairs(getProps) do
      local m = map
      StdPropObject.getProp[gp] = function(id,prop,event) return m[1](id.id,m[2],event)  end-- fun(id,prop,event)
      if m[4] then 
        StdPropObject.trigger[gp] = function(self,id,gp) return {type='device', id=id, property=m[2]} end
      else StdPropObject.trigger[gp] = true end
      if m[3] then StdPropObject.map[gp] = m[3] end
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
  local vars,triggerVars = ER.ruleValues,ER.triggerVars
  local reverseVarTable = {}
  function ER.defVar(name,init) vars[name] = {init} end
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
  -- options = { success = function(success,...), error = function(err), suspended = function(success,...), trace = bool, ctx=... }
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
            co.rtd.ctx.setTimeout(co.rtd,runner,stat[3])
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
    str = trim(str)
    ER._lastRule = nil
    local coroutine = ER.coroutine
    options = options or {}
    options.error = options.error or function(err) return false,fibaro.error(__TAG,err) end
    options.src = str
    local tkns = ER:tokenize(str)
    if tkns.containsOp('rule') then print("ISRULE") end
    local p = ER:parse(tkns,options)
    local fun = ER:compile(p,options)
    if fun == nil then error("can't compile "..str) end
    if options.listCode then print(fun.codeList()) end
    local co = coroutine.create(fun)
    return runCoroutine(co,options,table.unpack(options.args or {})) -- resume with handling of waits etc...
  end
  ER.eval = eval
    
  createProps(ER.setupProps())
end
----------------------------------------------------------------------------------
-- Setup engine and call main function 
function QuickApp:EventRunnerEngine()
  quickApp = self
  
  local ER,er = QuickApp.__ER,{}
  ER.er = er
  ER.localDefVars = {}
  ER.ruleValues = {}   -- Rule variables are stored here. These variables are shared between rules but not visible outside the rules.
  ER.triggerVars = {}  -- Trigger variables are marked here. 
  ER.builtins = {}
  ER.builtinArgs = {}

  local function multiLine(str) 
    if not str:find("\n") then return "'"..str.."'" end
    return "\n"..str
  end

  function QuickApp:enableTriggerType(triggers) fibaro.enableSourceTriggers(triggers) end

  ER.modules.utilities(ER) -- setup utilities, needed by all modules
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
        print(fmt("%s > %s [done]",multiLine(str),argsStr(...)))
      end
    end
    
    local stat = {pcall(function()
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
  
  for k,v in pairs(ER.localDefVars) do ER.defVar(k,v) end
  ER.localDefVars = nil
  
  er.ctx = ER.ctx
  er.defTriggerVar = ER.defTriggerVar
  er.deftriggervar = ER.defTriggerVar
  er.rule = er.eval
  er.defvar = ER.defVar
  er.defvars = ER.defvars
  er.reverseMapDef = ER.reverseMapDef
  er.coroutine = ER.coroutine
  er.listRules = ER.listRules
  er.listVariables = ER.listVariables
  er.pcall = e_pcall
  er.xerror = e_error
  er._utilities = ER.utilities
  
  function er.compile(str,options)
    options = options or {}
    options.src = str
    local p = ER:parse(str,options)
    return ER:compile(p,options)
  end
  
  for c,f in pairs(ER.constants) do ER:addInstr(c,f,"%s/%s") end
  for c,f in pairs(ER.builtins) do ER:addInstr(c,f,"%s/%s") end
  
  if self.main then self:main(er)
  else self:debug("No main function") end
  
  return ER
end