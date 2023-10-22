--%%include=Include.lua
--%%name=EventRunner5

function QuickApp:main(er)
    local rule,eval,Util = er.rule,er.eval,er
    self:enableTriggerType({"device","global-variable","custom-event","profile","alarm","weather","location","quickvar","user"}) -- types of events we want

    bs = fibaro.fibemu.create.binarySwitch().id

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
    rule("@{catch,sunset+00:10} => gardenlight:on")
    -- rule("wait(00:00:03,'abc'); log('RUN'); bs:on")

    -- er.listRules()
    -- er.listVariables()
end

function QuickApp:onInit()
    self:debug("onInit")
    self:EventRunnerEngine()
end