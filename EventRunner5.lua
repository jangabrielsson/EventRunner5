--%%include=Include.lua
--%%name=EventRunner5
--%%remote=alarms/v1/partitions:1
--%%var=x:5
--%%var=y:6
-- %%id=1249
--%%u1={label='title',text='EventRunner5'}
--%%u2={{button='listRules',text='List rules', onReleased='listRules'},{button='listRulesExt',text='List rules ext.', onReleased='listRulesExt'}}
--%%u3={{button='listTimers',text='List timers', onReleased='listTimers'},{button='listVars',text='List variables', onReleased='listVariables'}}
--%%u4={{button='test1',text='Test1', onReleased='test1'},{button='test2',text='Test2', onReleased='test2'}}

function QuickApp:main(er)
    local rule,eval,var,triggerVar,Util = er.eval,er.eval,er.variables,er.triggerVariables,er
    self:enableTriggerType({"device","global-variable","custom-event","profile","alarm","weather","location","quickvar","user"}) -- types of events we want
    
    -- Rule/expresion options, overrides global settings when passed to individual rules/expressions. nil means use global setting
    -- local expressionOptions = {
    --     listCode       = true,  -- list code when expression/rule is created
    --     trace          = false, -- trace code when expression/rule is run
    --     silent         = true,  -- don't log rule creation
    --     ruleTrigger    = true,  -- log rule being triggered 
    --     ruleTrue       = true,  -- log rule when condition succeeds
    --     ruleFalse      = true,  -- log rule when condition fails
    --     ruleResult     = true,  -- log result of rule return value
    --     evalResult     = true,  -- log result of expression evaluation
    --     userLogColor   = 'yellow',  -- if set, wraps user log messages in color
    -- }
    
    if fibaro.fibemu then -- Running in emulator, create 2 fake devices to play with...
        var.bs = fibaro.fibemu.create.binarySwitch().id
        var.bs2 = fibaro.fibemu.create.binarySwitch().id
        var.ms = fibaro.fibemu.create.multilevelSwitch().id
    end

    local HT = { 
        keyfob = 46, 
        motion= 87,
        temp = 22,
        lux = 23,
        gardenlight =24
    }

    er.defvars(HT)
    er.reverseMapDef(HT)

    --er.setTime("12/01/2023 12:00:00") --mm/dd/yyyy-hh:mm:ss
    --er.speedTime(2*24) -- 24 hours

    -- rule("0:tryArm")
    -- rule([[#alarm{property='delayed'} =>
    --     for p,d in pairs(env.event.value) do
    --         fibaro.warning(__TAG,efmt('Partition %s breached, devices %l',p,d))
    --     end;
    --     fibaro.warning(__TAG,efmt('Disarming'));
    --     0:armed=false
    -- ]])
    -- rule([[#alarm{id='$id', property='breached'} =>  
    --     fibaro.warning(__TAG,efmt('BREACHED partition:%s',env.event.id))
    -- ]])
    -- rule([[#alarm{property='homeBreached'} => 
    --     fibaro.warning(__TAG,efmt('BREACHED home'))
    -- ]])

    local msgOpts = { evalResult=false, userLogColor='yellow' }
    rule("elog('Sunrise at %t, Sunset at %t',sunrise,sunset)",msgOpts)
    rule("log('Weather condition is %s',weather:condition)",msgOpts)
    rule("log('Temperature is %s°',weather:temperature)",msgOpts)
    rule("log('Wind is %sms',weather:wind)",msgOpts)

    var.i = 0
    er.ruleOpts.tag = 'test'
    rule("@@00:00:05 => i=i+1; log('ping: %s seconds',i*5)",{ruleResult=false,ruleTrue=false})
    rule("elog('Devices with <50 battery are %l',[_:bat&_:bat<50,fmt('%s:%s',_,_:name) in devices])",{silent=true})
    triggerVar.sunoffs = 10*60 -- 10 minutes
    rule("@sunset+sunoffs => log('Ok, sunset+00:10')").info()

    -- var.buttonCallback = nil
    -- function var.async.getButton(cb)
    --     var.buttonCallback = cb
    --     return 100*1000 -- Timeout
    -- end
    -- rule("while true do btn = getButton(); if btn then log('Button %s pressed',btn) end end")

    -- function var.async.myFun(cb,x,y)
    --     setTimeout(function() cb(x+y) end,1000)
    --     return 2000
    -- end

    -- rule("log('myFun returned %s',myFun(3,4))")
    -- rule("for _,qa in ipairs(sort([true,_:name++fmt(':%d',_) in quickapps])) do log(qa) end") -- Log all QAs in alphabetic order
    -- a = rule("@14:00 | #foo => log('foo:%s started',env.instance); wait(00:00:30); log('foo:%s ended',env.instance)").mode("killSelf")
    -- rule("post(#foo); wait(2); post(#foo)")
    
    -- --rule("wait(1); post(#info)")
    
    -- function var.async.waitFor(cb,event,timeout)
    --     local h
    --     h = fibaro.event(event,function() fibaro.removeEvent(event,h) cb(true) end)
    --     return (timeout or 10)*1000 -- Timeout
    -- end
    -- rule("#foo3 => log('foo3'); waitFor(#foo4); log('foo4')")
    -- rule("wait(2); post(#foo3); wait(4); post(#foo4)")

    -- rule("log('Time:%s',http.get('http://worldtimeapi.org/api/timezone/Europe/Stockholm').data.datetime)")

    local ruleOpts = { silent=true }
    rule("#UI{cmd='listRules'} => listRules(false)",ruleOpts)
    rule("#UI{cmd='listRulesExt'} => listRules(true)",ruleOpts)
    rule("#UI{cmd='listVars'} => listVariables()",ruleOpts)
    rule("#UI{cmd='listTimers'} => listTimers()",ruleOpts)
    
    -- rule("#UI{cmd='test1'} => buttonCallback('test1')",ruleOpts)
    --rule("#UI{cmd='test2'} => a.enable()",ruleOpts)
end

function QuickApp:onInit()
    self:EventRunnerEngine( -- Create EventRunner engine and pass callback function 
    function(er)
        -- Settings
        
        -- Global debug flags, can be overridden by ruleOptions
        er.debug.ruleTrigger    = false -- log rules being triggered 
        er.debug.ruleTrue       = true  -- log rules with condition succeeding
        er.debug.ruleFalse      = true  -- log rules with condition failing
        er.debug.ruleResult     = false -- log results of rules running
        er.debug.evalResult     = true  -- log results of evaluations
        er.debug.post           = true  -- log events being posted
        er.debug.sourceTrigger  = false  -- log incoming sourceTriggers
        er.debug.refreshEvents  = false  -- log incoming refreshEvents
        
        -- Global settings
        er.settings.marshall       = true          -- autoconvert globalVariables values to numbers, booleans, tables when accessed
        er.settings.systemLogTag   = "ER"..self.id -- log tag for ER system messages, defaults to __TAG
        er.settings.ignoreInvisibleChars = false   -- Check code for invisible characters (xC2xA0) before evaluating
        er.settings.truncLog       = 100           -- truncation of log output
        er.settings.truncStr       = 80            -- truncation of log strings
        -- er.settings.logFibaro      = true          -- log to fibaro.call, fibero.setVariable, etc.
        -- er.settings.logApi         = true          -- log all api.* calls
        -- er.settings.bannerColor = "orange"         -- color of banner in log, defaults to "orange"      
        -- er.settings.listColor = "purple"           -- color of list log (list rules etc), defaults to "purple"
        -- er.settings.statsColor = "green"           -- color of statistics log, defaults to "green"  
        -- er.settings.userLogFunction = function(rule,tag,str) return fibaro.debug(tag,str) end -- function to use for user log(), defaults to fibaro.debug if nil
        
        local TRUE = er.color("lightgreen","TRUE")
        local FALSE = er.color("lightred","FALSE")
        function er.settings.runRuleLogFun(co,rule,ok,event)
          co.LOG("%s %s -> %s",ok and TRUE or FALSE,tostring(event) // 20,rule.src:gsub("\n","") // 40)
        end

        function er.settings.userLogFunction(rule,tag,str) -- custom user log function with color and tag support,  #C:color# and #T:tag#
          local color = nil
          str = str:gsub("(#T:)(.-)(#)",function(_,t) tag=t return "" end)
          str = str:gsub("(#C:)(.-)(#)",function(_,c) color=c return "" end)
          if color then str=string.format("<font color=%s>%s</font>",color,str) end
          fibaro.debug(tag,str);
          return str
        end
        
        self:main(er) -- Call main function to setup rules
    end
)
end