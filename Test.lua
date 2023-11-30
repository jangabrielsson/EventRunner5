--%%include=Include.lua
--%%name=EventRunner5
--%%debug=refresh:false
--%%u1={label='title',text='EventRunner5'}

function QuickApp:main(er)
  local ER = fibaro.__ER
  fibaro.debugFlags.post = true
  fibaro.debugFlags.sourceTrigger = true
  
  er.debug.ruleResult     = false -- log results of rules running
  er.debug.evalResult     = false -- log results of evaluations
  er.debug.ruleTrigger    = false -- log rules being triggered
  er.debug.ruleTrue       = false -- log rules with condition succeeding
  er.debug.ruleFalse      = false -- log rules with condition failing
  er.debug.refreshEvents  = false -- log refresh of states
  er.debug.sourceTrigger  = false -- log refresh of devices

  local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
  PrintBuffer,sunData,LOG,LOGERR,htmlTable,evOpts =
  table.unpack(ER.utilities.export)
  
  local HT = { 
    keyfob = 46, 
    motion= 87,
    temp = 22,
    lux = 23,
    gardenlight =24
  }

  er.defvars(HT)
  er.reverseMapDef(HT)

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
  
  local function runExpr(expr,opts)
    local testf = opts.test or table.equal
    local r = expr
    local pr = PrintBuffer()
    local str = r[1]
    local answer = r[2]
    local name = string.format("%s",str)
    local options = {codeList=true,trace=opts.trace}
    for k,v in pairs(opts) do options[k]=v end
    
    function options.suspended(...)
      local res = {...}
      pr:print(name,">",argsStr(table.unpack(res,2)),"[suspended]")
      return nil
    end
    
    function options.success(...)
      local res = {...}
      if #res==1 and type(res[1])=='table' and res[1].evalPrint then -- result is a table with evalPrint method
        res[1].evalPrint(res[1],str)      
      end
      pr:print(name,">",argsStr(res),"[done]")
      if testf(res,answer) then print("OK",str)
      else fibaro.error(__TAG,"FAIL",pr:tostring()) end
    end
    
    function options.error(err) 
      pr:print(name,">",err)
      fibaro.error(__TAG,pr:tostring())
    end
    
    local res = {pcall(er.eval,str,options)}
    if not res[1] then 
      print(pr:tostring())
      print(res[2])
    end
  end
  
  local function runExprs(exprs) for i,r in ipairs(exprs) do runExpr(r,r[3] or {}) end end
  
  local function runRules(exprs)
    local rules = {}
    for i,r in ipairs(exprs) do
      local rule
      local function test(res,answer) if type(res)=='table' and er.isRule(res[1]) then rule = res[1] return true else return false end end
      runExpr(r,{test=test})
      if rule==nil then 
        --fibaro.error(__TAG,"rule did not compile")
      else
        --rule.trace(true)
        rules[rule] = {}
        local pr = PrintBuffer()
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
            setTimeout(function() er.eval(e) end,0)
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
    {"46:HTname",{'keyfob'}},
    {"a=2; a+=3; a",{5}},
    {"a=2; a-=3; a",{-1}},
    {"a=2; a*=3; a",{6}},
    {"$A=9",{9}},
    {"$$B = 9; $$B",{9}},
    {"QA:getVariable('B')",{9}}, -- foo:B(x)   aref foo,B
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
    {"a={b=8,cd=9,e={3,4}}",{{b=8,cd=9,e={3,4}}}},
    {"a.b",{8}},
    {"a['b']",{8}},
    {"a['c'++'d']",{9}},
    {"a.e[1]",{3}},
    {"a.e[a.e[1]-1]",{4}},
    {"a.b=88;a.b",{88}},
    {"a['b']=99;a.b",{99}},
    {"a.e[2]=5;a.e[2]",{5}},  
    {"a[true]=42;a[true]",{42}},  
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
    {"wait(1); 7",{7}},
    {"{1,2,3,4,5}:average",{3}},
    {"{1,2,3,4,5}:sum",{15}},
    {"{true,true,true}:allTrue",{true}},   
    {"{true,true,true}:someTrue",{true}},   
    {"{true,true,false}:someTrue",{true}},   
    {"{false,true,true}:allTrue",{false}},
    {"{false,false,false}:allFalse",{true}},   
    {"{true,false,true}:someFalse",{true}},   
    {"{true,true,false}:someFalse",{true}},   
    {"{false,false,true}:allFalse",{false}},   
    {"{false,false,true}:mostlyFalse",{true}},   
    {"{false,true,true}:mostlyTrue",{true}},   
    {"{true,false,true}:bin:sum",{2}}, 
    {"local a99,b = 8,9; b99=77; a99*b",{72}},     
    {"a99==nil & b99==77",{true}},              -- verify that local is removed, and er. global remains
    {"[_%2==0 in {2,7,4,8,1}]",{{2,4,8}}},
    {"[_%2==0,2*_ in {2,7,4,8,1}]",{{4,8,16}}}, 
    {"[_%2==0,2*_ in {2,7,4,8,1}]:sum",{28}}, 
    {"month('nov')",{true}}, 
    {"month('jun')",{false}}, 
  
  }
  
  runExprs(exprs1)
  
  local errorExprs = {
    {"a = = 3",nil},
    {"+ 8",nil},
    {"8 8",nil},
    {"$33",nil},
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
    -- {"@{catch,07:00} => 66",{true,66}},
    -- {"@now+1 => a = asyncfun(2,3);a",{true,5}},
    -- {"555:central.keyAttribute == 'Pressed' => 109",{true,109},{{type='device',id=555,property='centralSceneEvent',value={keyId=2,keyAttribute='Pressed'}}}},
    -- {"556:scene == S2.double => 110",{true,110},{{type='device',id=556,property='sceneActivationEvent',value={sceneId="24"}}}},
    --{"#myRemote => 543",{true,543},{"remote(QA.id,#myRemote)"}},
  }
  

  setTimeout(function() runRules(rules3) end,1000)
  
  --er.defVar('fopp',function() print("fopp") end)
  local rulesError = {
    {"foo noid:value => 55",{true,55}},
    {"noid:foo => 55",{true,55}},
    -- {"#foo => 55:onIfOff; 55",{true,55},{{type='foo'}}},
    -- {"#foo2 => fopp(); 55",{true,55},{{type='foo2'}}},   
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