--%%include=Include.lua
--%%name=EventRunner5
--%%remote=alarms/v1/partitions:1
--%%var=x:5
--%%var=y:6
--%%id=1249
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
    -- }
    
    if fibaro.fibemu then -- Running in emulator, create 2 fake devices to play with...
        var.bs = fibaro.fibemu.create.binarySwitch().id
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

    var.i = 0
    rule("@@00:00:05 => i=i+1; log('5 seconds %s',i)",{ruleResult=false,ruleTrue=true})
    
    -- a = rule("@14:00 | #foo => log('foo:%s started',env.instance); wait(00:00:30); log('foo:%s ended',env.instance)").mode("killSelf")
    -- rule("post(#foo); wait(2); post(#foo)")
    -- local msgOpts = { silent=true }
    -- rule("log('Weather condition is %s',weather:condition)",msgOpts)
    -- rule("log('Temperature is %s°',weather:temperature)",msgOpts)
    -- rule("log('Wind is %sms',weather:wind)",msgOpts)
    
    -- --rule("wait(1); post(#info)")
    
    local ruleOpts = { silent=true }
    rule("#UI{cmd='listRules'} => listRules(false)",ruleOpts)
    rule("#UI{cmd='listRulesExt'} => listRules(true)",ruleOpts)
    rule("#UI{cmd='listVars'} => listVariables()",ruleOpts)
    rule("#UI{cmd='listTimers'} => listTimers()",ruleOpts)
    
    rule("#UI{cmd='test1'} => a.disable()",ruleOpts)
    rule("#UI{cmd='test2'} => a.enable()",ruleOpts)
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
        -- er.settings.bannerColor = "orange"         -- color of banner in log, defaults to "orange"      
        -- er.settings.listColor = "purple"           -- color of list log (list rules etc), defaults to "purple"
        -- er.settings.statsColor = "green"           -- color of statistics log, defaults to "green"  
        -- er.settings.userLogFunction = function(rule,tag,str) return fibaro.debug(tag,str) end -- function to use for user log(), defaults to fibaro.debug if nil
        
        local TRUE = er.color("lightgreen","TRUE")
        local FALSE = er.color("lightred","FALSE")
        function er.settings.runRuleLogFun(co,rule,ok,event)
            co.LOG("%s %s -> %s",ok and TRUE or FALSE,tostring(event) // 20,rule.src // 40)
        end
        
        function er.settings.userLogFunction(rule,tag,str) -- custom user log function with color and tag support,  #C:color# and #T:tag#
            local color = nil
            str = str:gsub("(#T:)(.-)(#)",function(_,t) tag=t return "" end)
            str = str:gsub("(#C:)(.-)(#)",function(_,c) color=c return "" end)
            if color then str=string.format("<font color=%s>%s</font>",color,str) end
            fibaro.trace(tag,str);
            return str
        end
        
        self:main(er) -- Call main function to setup rules
    end
)
end