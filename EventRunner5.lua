--%%include=Include.lua
--%%name=EventRunner5
--%%remote=alarms/v1/partitions:1
--%%id=1249
--%%u1={label='title',text='EventRunner5'}
--%%u2={{button='listRules',text='List rules', onReleased='listRules'},{button='listRulesExt',text='List rules ext.', onReleased='listRulesExt'}}
--%%u3={{button='listTimers',text='List timers', onReleased='listTimers'},{button='listVars',text='List variables', onReleased='listVariables'}}
--%%u4={{button='test1',text='Test1', onReleased='test1'},{button='test2',text='Test2', onReleased='test2'}}

function QuickApp:main(er)
    local rule,eval,var,Util = er.eval,er.eval,er.variable,er
    self:enableTriggerType({"device","global-variable","custom-event","profile","alarm","weather","location","quickvar","user"}) -- types of events we want

    -- Global debug flags, can be overridden by ruleOptions
    er.debug.ruleTrigger    = true -- log rules being triggered 
    er.debug.ruleTrue       = true -- log rules with condition succeeding
    er.debug.ruleFalse      = true -- log rules with condition failing
    er.debug.ruleResult     = true -- log results of rules running
    er.debug.evalResult     = true -- log results of evaluations
    er.debug.post           = true -- log events being posted
    er.debug.sourceTrigger  = true -- log incoming sourceTriggers
    er.debug.refreshEvents  = true -- log incoming refreshEvents

    -- Global settings
    er.settings.marshall       = true          -- autoconvert globalVariables values to numbers, booleans, tables when accessed
    er.settings.systemLogTag   = "ER"..self.id -- log tag for ER system messages, defaults to __TAG
    er.settings.ignoreInvisibleChars = false   -- Check code for invisible characters (xC2xA0) before evaluating
    er.settings.truncLog       = 100           -- truncation of log output
    er.settings.truncStr       = 80            -- truncation of log strings
    -- er.settings.bannerColor = "orange"         -- color of banner in log, defaults to "orange"      
    -- er.settings.listColor = "purple"           -- color of list log (list rules etc), defaults to "purple"
    -- er.settings.statsColor = "green"           -- color of statistics log, defaults to "green"  

    -- Rule/expresion options, overrides global settings when passed to individual rules/expressions. nil means use global setting
    local expressionOptions = {
        listCode       = true,  -- list code when expression/rule is created
        trace          = false, -- trace code when expression/rule is run
        silent         = true,  -- don't log rule creation
        ruleTrigger    = true,  -- log rule being triggered 
        ruleTrue       = true,  -- log rule when condition succeeds
        ruleFalse      = true,  -- log rule when condition fails
        ruleResult     = true,  -- log result of rule return value
        evalResult     = true,  -- log result of expression evaluation
    }

    if fibaro.fibemu then
        --bs = fibaro.fibemu.create.binarySwitch().id
    end

    local HT = { 
        keyfob = 46, 
        motion= 87,
        temp = 22,
        lux = 23,
        gardenlight =24
    }
    
    Util.defvars(HT)
    Util.reverseMapDef(HT)

    -- rule("3+3")

    -- local a = rule("@sunset => gardenlight:on").name("test")
    -- print("Name:",a)
    -- print("\n"..tostring(a.description))
    -- print("\n"..tostring(a.triggers))

    -- a = 99
    -- b = rule("myrule","@now+1 => log('%s OK',env.name); wait(1,'A'); post(#foo,10:00)")

    -- rule("wait(2); log(b.info)")
    --rule("a,b=5,0; while a > 0 do a=a-1; b=b+1 end; b",{trace=true,listCode=true})
    --rule("a=4; while (a=a-1) > 0 do log('a=%s',a) end; log('X')",{trace=false,listCode=true})
    -- rule([[@midnight =>
    --     || false uck >> 6
    --     || false >> 8
    --     || 9 >> 10
    -- ]],{listCode=true})
    --rule("http.get('http://worldtimeapi.org/api/timezone/Europe/Stockholm').data.datetime")
    --rule("for i=2,5,2 do log('Value:%s',i) end")
    --rule("for k,v in pairs(t) do k end")
    -- rule("trueFor(00:00:05,bs:isOn) => log('Light is on for %s seconds',5*again())")
    -- rule("@{catch,sunset+00:10} => gardenlight:on")
    -- rule("wait(00:00:03,'abc'); log('RUN'); bs:on")
    -- a = rule("1:armed~=nil => log('Partition 1 is %s',1:armed)")
    -- rule("PIN='1111';1:tryArm")
    -- rule("#alarm{id=1,property='armDelayed'} => 1:armed=false; log('ALARM:%s',env.event)")
    -- print(a.description)

    -- rule("[_:isOn in lamps]:on")
    --rule("[_==='RPC'in globals]:GV")
    -- rule("noid:value")
    -- rule("1250:isOn")
    -- rule("quickvars")
    -- rule("for k,_ in ipairs({2,3,4}) do log('%s',_) end")
    -- rule("local a,b = 9,8; a*b")

    var.ii=0
    --a = rule("@@00:00:05 => ii=ii+1; log('5 seconds %s',ii)",{ruleResult=false,ruleTrue=false})
    -- rule("@{sunrise,catch} => log('God morning!')")
    -- rule("@sunset => log('God evening!')")
    -- rule("@23:00 => log('God night!')")
    -- rule("@sunset => log('sunset!')")
    -- --rule("trueFor(02:00,bs:safe) => log('bs safe')").start()
    -- rule("@now+1 => post(#foo)")
    -- rule("#foo => log('#foo received')")

    local msgOpts = { silent=true }
    rule("log('Weather condition is %s',weather:condition)",msgOpts)
    rule("log('Temperature is %s°',weather:temperature)",msgOpts)
    rule("log('Wind is %sms',weather:wind)",msgOpts)

    --rule("wait(1); post(#info)")

    Util.defvar('ER',er)
    local ruleOpts = { silent=true }
    rule("#UI{cmd='listRules'} => ER.listRules(false)",ruleOpts)
    rule("#UI{cmd='listRulesExt'} => ER.listRules(true)",ruleOpts)
    rule("#UI{cmd='listVars'} => ER.listVariables()",ruleOpts)
    rule("#UI{cmd='listTimers'} => ER.listTimers()",ruleOpts)
   
    rule("#UI{cmd='test1'} => a.disable()",ruleOpts)
    rule("#UI{cmd='test2'} => a.enable()",ruleOpts)
end

function QuickApp:onInit()
    self:setVariable('x',45)
    self:setVariable('y',46)
    self:EventRunnerEngine()
end