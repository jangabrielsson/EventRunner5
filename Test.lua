--%%include=Include.lua
--%%name=EventRunner5

function QuickApp:main(er)
  fibaro.debugFlags.post = true
  fibaro.debugFlags.sourceTrigger = true
  
  local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
  PrintBuffer,sunData =
  table.unpack(er._utilities.export)
  
  local function prbuff()
    local self = {}
    local buff = {}
    function self:printf(...) buff[#buff+1] = string.format(...) end
    function self:print(...)
      local r={} for _,v in ipairs({...}) do r[#r+1] = tostring(v) end
      buff[#buff+1] = table.concat(r," ")
    end
    function self:tostring() return table.concat(buff,"\n") end
    return self
  end
  
  local ctx,vars = {},{}
  function ctx.get(name) return vars[name] or {_G[name]} end
  function ctx.set(name,value) local old; local v = vars[name] if v then old = v[1] v[1]=value else vars[name]={value} end  return true,old end
  function ctx.post(event) fibaro.post(event) end
  function ctx.triggerVar(name) return false end
  function ctx.setTimeout(p,fun,delay) return setTimeout(fun,delay) end
  function ctx.clearTimeout(p,ref) return clearTimeout(ref) end
  function ctx.print(...) ctx._pr:print(...) end
  
  if false then -- test coroutines
    function multval() return 1,2,3 end
    local fun = er.compile("x,y = _args; log('values %s %s',x,y); log(7); yield(2); z = yield(3); return 3+z,88")
    print(fun)
    print("\n"..fun.codeList())
    local co = er.coroutine.create(fun)
    fun.trace = true
    local res,stat
    repeat
      res = {er.coroutine.resume(co,4,5)}
      stat = er.coroutine.status(co)
      print(table.unpack(res)) 
      print(stat)
    until stat == 'dead'
    local a = 0
  end
  
  local function argsStr(...)
    local args = {...}
    local r = {} for i=1,table.maxn(args) do r[i] = tostring(args[i]) end
    return table.concat(r,",")
  end
  
  local function runExpr(expr,opts)
    local testf = opts.test or table.equal
    local r = expr
    local pr = prbuff()
    ctx._pr = pr
    local str = r[1]
    local answer = r[2]
    local name = string.format("%s",str)
    local options = {ctx=opts.ctx or ctx,codeList=true,trace=opts.trace}
    
    function options.suspended(...)
      local res = {...}
      pr:print(name,">",argsStr(table.unpack(res,2)),"[suspended]")
      return nil
    end
    
    function options.success(success,...)
      local res = {...}
      pr:print(name,">",argsStr(res),"[done]")
      if testf(res,answer) then print("OK",str)
      else fibaro.error(__TAG,"FAIL",pr:tostring()) end
    end
    
    function options.error(err) 
      pr:print(name,">",err)
      fibaro.error(__TAG,pr:tostring())
    end
    
    local stat,err = pcall(function()
      local res = {er.eval0(str,options)}
      if res[1] then options.success(table.unpack(res,2)) end
    end)
    if not stat then 
      print(pr:tostring())
      print(err)
    end
  end
  
  local function runExprs(exprs) for i,r in ipairs(exprs) do runExpr(r,{}) end end
  
  local function runRules(exprs)
    local rules = {}
    for i,r in ipairs(exprs) do
      local rule
      local function test(res,answer) if type(res)=='table' and er.isRule(res[1]) then rule = res[1] return true else return false end end
      runExpr(r,{ctx=er.ctx,test=test})
      if rule==nil then 
        --fibaro.error(__TAG,"rule did not compile")
      else
        --rule.trace(true)
        rules[rule] = {}
        local pr = prbuff()
        print("rule",rule,"defined")
        rule.resultHook = function(success,...)
          local res = {success,...}
          if table.equal({success,...},r[2]) then 
            print("OK",rule,">>",...)
            rules[rule][1] = true
          else fibaro.error(__TAG,"FAIL",rule,json.encode(res)) print(pr:tostring()) end
        end
        local events = r[3] or {}
        for _,e in ipairs(events) do 
          if type(e)=='table' then 
            setTimeout(function() fibaro.post(e) end,0)
          elseif type(e)=='function' then 
            setTimeout(function() e() end,0)
          elseif type(e)=="string" then
            setTimeout(function() er.eval(e,{ctx=er.ctx}) end,0)
          end
        end
      end
      setTimeout(function()
        local flag = true
        for rule,stat in pairs(rules) do
          if not stat[1] then flag=false fibaro.error(__TAG,"FAIL",rule) end
        end
        if flag then print("All rules OK") end
      end,10*1000)
    end
  end
  
  function Fun1(a,b) return a+b,9,10 end
  ms1 = fibaro.fibemu.create.multilevelSwitch().id
  ms2 = fibaro.fibemu.create.multilevelSwitch().id
  ms3 = fibaro.fibemu.create.multilevelSwitch().id
  bs1 = fibaro.fibemu.create.binarySwitch().id
  bs2 = fibaro.fibemu.create.binarySwitch().id
  api.post("/globalVariables", {name="rt1",value="_"})  -- create global variable
  fibaro.event({type='device'},function() end)
  fibaro.sleep(100)
  er.defTriggerVar("tv1",nil)
  function Foo() return 7 end
  local exprs1 = {
    {"Foo()-4",{3}},
    {"5* -4",{-20}},
    {"7;8;9",{9}},
    {"a=8",{8}},
    {"a",{8}},
    {"3-4",{-1}},
    {"3*4",{12}},
    {"4/2",{2}},
    {"5 % 3",{2}},
    {"3+5*7",{38}},
    {"3+5*(1+2)",{18}},
    {"5* -4",{-20}},
    {"1+20/4",{6}},
    {"1 < 3",{true}},
    {"1 <= 3",{true}},
    {"3 > 1",{true}},
    {"3 >= 1",{true}},
    {"3 < 1",{false}},
    {"3 <= 1",{false}},
    {"1 > 3",{false}},
    {"1 >= 2",{false}},
    {"true & false",{false}},
    {"true | false",{true}},
    {"true & false | true",{true}},
    {"false | false | true",{true}},
    {"a = 8",{8}},
    {"a = 8; b = 9;c=10",{10}},
    {"a = {1,2}",{{1,2}}},
    {"a={b=8,cd=9}",{{b=8,cd=9}}},
    {"a.b",{8}},
    {"a['b']",{8}},
    {"a['c'++'d']",{9}},
    {"a.b=88;a.b",{88}},
    {"a['b']=99;a.b",{99}},
    {"a['b']=99;a['b']-4",{95}},
    {"Fun1(3,4)",{7,9,10}},
    {"return Fun1(3,4)",{7,9,10}},
    {"return 2,Fun1(3,4)",{2,7,9,10}},
    {"return Fun1(Fun1(3,4))",{16,9,10}},
    {"x,y = Fun1(3,4); return x,y",{7,9}},
    {"if true then 42 end",{42}},
    {"if false then 42 end",{false}},
    {"if false then 42 elseif true then 55 end",{55}},
    {"if false then 42 elseif 1>2 then 55 end",{false}},
    {"if true then 42 else 34 end",{42}},
    {"if false then 42 else 34 end",{34}},
    {"if false then 42 elseif true then 34 else 55 end",{34}},
    {"if false then 42 elseif 1>2 then 34 else 55 end",{55}},
    {"a,b=5,0; while a > 0 do a=a-1; b=b+1 end; b",{5}},
    {"a,b=5,0; repeat a=a-1; b=b+1  until a < 1; b",{5}},
    {"ms1:value",{0}},
    {"ms1:value=33; wait(1); ms1:value",{33}},
    {"sunset",{toTime(sunData().sunsetHour)}},
    {"sunrise",{toTime(sunData().sunriseHour)}},
    {"dawn",{toTime(sunData().dawnHour)}},
    {"dusk",{toTime(sunData().duskHour)}},
    {"midnight",{fibaro.midnight()}},
    {"now == ostime()-midnight",{true}},
    {"wnum",{fibaro.getWeekNumber(os.time())}},
    {"average({2,2,8})",{4}},
    {"sum({2,2,8})",{12}},
    {"min({2,-1,8})",{-1}},
    {"max({2,20,8})",{20}},
    {"sign(-4)",{-1}},
    {"sign(0)",{1}},
    {"sign(6)",{1}},
    {"sort({4,3,2})",{{2,3,4}}},
    {"round(3.5)",{4}},
    {"fmt('%d-%d',4,5)",{"4-5"}},
    {"x=0; for i=1,5 do x = x+1 end; x",{5}},
    {"x=0; for k,v in ipairs({2,3,4}) do x = x+v end; x",{9 }},
  }
  
  runExprs(exprs1)
  
  local errorExprs = {
    "a = = 3",
    "+ 8",
    "8 8",
    "$33"
  }
  
  --runExprs(errorExprs) -- should fail
  
  local function GV(name,value) return function() fibaro.setGlobalVariable(name,tostring(value)) end end
  local function QV(name,value) return function() quickApp:setVariable(name,value) end end
  
  er.definePropClass("MyObj")
  function MyObj:__init(id) PropObject.__init(self) self.id = id; self.val=55 end
  function MyObj.getProp.hello(id,prop,event) return self.val end
  function MyObj.setProp.hello(id,prop,value) 
    if self.val == value then return end
    self.val = value;
    fibaro.post({type='hello', value=self.val})
    return self.val 
  end
  function MyObj.trigger.hello(id,prop) return {type='hello', value=self.val} end
  myObj = MyObj(99)
  
  function asyncfun(a,b) 
    local fun={}
    setTimeout(function() 
      fun[1](a+b) 
    end,2000)
    return '%magic_suspend%',fun
  end
  
  local rules3 = {
    -- {"$rt1=='x' => 55",{true,55},{GV('rt1','x')}},
    -- {"$rt1=='y' => 55",{false,false},{GV('rt1','x')}},
    -- {"$$qv1=='x' => 56",{true,56},{QV('qv1','x')}},
    -- {"tv1==2 => 44",{true,44},{"tv1=2"}},
    -- {"@now+1 => log('ENV:%s',env.test);42",{true,42}},
    -- {"#foo1 => 77",{true,77},{{type='foo1'}}},
    -- {"#foo2{a='$x'} => x",{true,88},{{type='foo2',a=88}}},
    -- {"ms1:value==33 => 99",{true,99},{"ms1:value=33"}},
    -- {"myObj:hello==33 => 99",{true,99},{"myObj:hello=33"}},
    -- {"{bs1,bs2}:isOn => 101",{true,101},{"bs2:on"}},
    -- {"ms2:value => wait(1); {ms2,ms3}:value",{true,{19,0}},{"ms2:value=19"}},
    {"@{catch,10:00} => 66",{true,66}},
    --{"@now+1 => a = asyncfun(2,3);a",{true,5}},
  }
  
  -- print(er.eval("@{02:00,03:00} & ms1:value & 01:00..02:00 => 99").description)
  -- local r = er.eval("@now+4 => wait(2); 66")--.trace(true)
  -- print(r)
  -- setTimeout(function() runRules(rules3) end,1000)
  
  --er.defVar('fopp',function() print("fopp") end)
  local rulesError = {
    -- {"noid:value => 55",{true,55}},
    -- {"noid:foo => 55",{true,55}},
    -- {"#foo => 55:onIfOff; 55",{true,55},{{type='foo'}}},
    {"#foo2 => fopp(); 55",{true,55},{{type='foo2'}}},   
  }
  --runRules(rulesError)
  -- er.eval("log('Hello %s',42)")
  -- local a = er.eval("#foo => wait(10:00); log('OK')")
  -- print(a)
  -- print(a.description)
  -- fibaro.post({type='foo'},1)
  -- fibaro.post({type='foo'},2)
  -- setTimeout(function() print(a.processes) end,3000)
  --[[
  function stdPropObject.getProp.onIfOff(id,prop,event) print("On if off") return true end
  
  definePropObject('MyObj')
  function MyObj:__init(id) PropObj.__init(self) self.id = id end
  function MyObj.getProp.hello(id,prop,event) return self.id..":"..prop end
  function MyObj.setProp.hello(id,prop,value) return self.id..":"..prop end
  function MyObj.trigger.hello(id,prop) return self.id..":"..prop end
  --]]
end

function QuickApp:onInit()
  quickApp = self
  self:debug("onInit")
  self.ER = self:EventRunnerEngine()
end