--%%include=Include.lua
--%%name=EventRunner5
--%%remote=alarms/v1/partitions:1
--%%remote=devices:*
--%%u1={label='title',text='EventRunner5'}
--%%u2={{button='listRules',text='List rules', onReleased='listRules'},{button='listRulesExt',text='List rules ext.', onReleased='listRulesExt'}}
--%%u3={{button='listTimers',text='List timers', onReleased='listTimers'},{button='listVars',text='List variables', onReleased='listVariables'}}
--%%u4={{button='test1',text='Test1', onReleased='test1'},{button='test2',text='Test2', onReleased='test2'}}

function QuickApp:main(er) -- Main function, place to define rules
    local rule,eval,var,triggerVar,Util = er.eval,er.eval,er.variables,er.triggerVariables,er
    self:enableTriggerType({"device","global-variable","custom-event","profile","alarm","weather","location","quickvar","user"}) -- types of events we want

    local HT = { -- Test Home Table with "fake" devices - create your own...
        keyfob = 46, 
        doorSensor = er.createBinaryDevice(),
        temp = er.createMultilevelDevice(),
        lux = er.createMultilevelDevice(),
        roomlight = er.createMultilevelDevice(),
        gardenlight = er.createBinaryDevice(),
        frontlight = er.createBinaryDevice(),
    }

    a = fibaro.get(48,"batteryLevel")
    er.defvars(HT) -- Make HomeTable variables available as variables in rules. 
    er.reverseMapDef(HT)

    --er.setTime("12/01/2023 12:00:00") --mm/dd/yyyy-hh:mm:ss
    --er.speedTime(2*24) -- 24 hours

    rule("48:bat")
    rule([[#alarm{id='$id', property='breached'} =>  -- Log when a partition is breached
        fibaro.warning(__TAG,efmt('BREACHED partition:%s',env.event.id))
    ]])
    rule([[#alarm{property='homeBreached'} =>   -- Log when home is breached
        fibaro.warning(__TAG,efmt('BREACHED home'))
    ]])

    rule("keyfob:central.keyId == 1 => log('Keyfob button 1 pressed')")
    rule("wait(2); keyfob:sim_pressed=1") -- Fake key press

    local msgOpts = { evalResult=false, userLogColor='yellow' }
    rule("elog('Sunrise at %t, Sunset at %t',sunrise,sunset)",msgOpts)
    rule("log('Weather condition is %s',weather:condition)",msgOpts)
    rule("log('Temperature is %s°',weather:temperature)",msgOpts)
    rule("log('Wind is %sms',weather:wind)",msgOpts)

    var.i = 0 -- initialize ER variable
    rule("@@00:00:05 => i=i+1; log('ping: %s seconds',i*5)",{ruleTrue=false}) -- test rule, ping every 5 seconds

    -- At start, log all devices with battery < 50%
    rule("elog('Devices with <50 battery are %l',[_:bat&_:bat<50,fmt('%s:%s',_,_:name) in devices])",{silent=true})

    rule("@sunset+00:10 => log('Ok, sunset+00:10')")
    rule("@sunrise-00:10 => log('Ok, sunrise-00:10')")

    -- rule("log('Time:%s',http.get('http://worldtimeapi.org/api/timezone/Europe/Stockholm').datetime)")

    local ruleOpts = { silent=true }
    rule("#UI{cmd='listRules'} => listRules(false)",ruleOpts)
    rule("#UI{cmd='listRulesExt'} => listRules(true)",ruleOpts)
    rule("#UI{cmd='listVars'} => listVariables()",ruleOpts)
    rule("#UI{cmd='listTimers'} => listTimers()",ruleOpts)
    
    -- rule("#UI{cmd='test1'} => buttonCallback('test1')",ruleOpts)
    -- rule("#UI{cmd='test2'} => a.enable()",ruleOpts)
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

        -- Rule/expresion options, overrides global settings when passed to individual rules/expressions. nil means use global setting
        -- local expressionOptions = {
        --     listCode       = true,  -- list code when expression/rule is created
        --     trace          = false, -- trace code when expression/rule is run
        --     silent         = true,  -- don't log rule creation and rule results
        --     ruleTrigger    = true,  -- log rule being triggered 
        --     ruleTrue       = true,  -- log rule when condition succeeds
        --     ruleFalse      = true,  -- log rule when condition fails
        --     ruleResult     = true,  -- log result of rule return value
        --     evalResult     = true,  -- log result of expression evaluation
        --     userLogColor   = 'yellow',  -- if set, wraps user log messages in color
        -- }

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