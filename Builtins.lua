QuickApp.__ER  = QuickApp.__ER or { modules={} }

function QuickApp.__ER.modules.builtins(ER)
    
    local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
    marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
    PrintBuffer,sunData =
    table.unpack(ER.utilities.export)
    
    local builtin = ER.builtins
    local args = ER.builtinArgs
    local Script = ER.Script
    local defVars = ER.localDefVars
    local fmt = string.format
    
    local definePropClass = ER.definePropClass
    local PropObject = ER.PropObject

    local function errorf(p,fm,...)
        local dbg = p.fun.dbg[p.fun.code[p.pc]]
        dbg = dbg and dbg.d or {}
        local err = errorMsg{type="Runtime",msg=fmt(fm,...),from=dbg.from,to=dbg.to,src=p.fun.src}
        e_error(err)
    end
    
    -------------- builtin constants -------------------------
    ER.constants = {
        ['_args'] = function(_,st,p) ER.returnMultipleValues(st,table.unpack(p.args or {})) end,
        sunset = function(_,st) st.push(toTime(sunData().sunsetHour)) end,
        sunrise = function(_,st) st.push(toTime(sunData().sunriseHour)) end,
        midnight = function(_,st) st.push(midnight()) end,
        catch = function(_,st) st.push(math.maxinteger) end,
        dawn = function(_,st) st.push(toTime(sunData().dawnHour)) end,
        dusk = function(_,st) st.push(toTime(sunData().duskHour)) end,
        now = function(_,st) st.push(os.time()-midnight()) end,
        wnum = function(_,st) st.push(fibaro.getWeekNumber(os.time())) end,
    }
    
    local function alarmLoop()
        local p = api.get("/alarms/v1/partitions/1")
        --print(p.id,p.armed,p.secondsToArm,json.encodeFast(p)) 
    end
    setInterval(alarmLoop,2000)

    -------------- builtin props -------------------------
    function ER.setupProps()
        -- getProps helpers
        local function BN(x) if type(x)=='boolean' then return x and 1 or 0 else return x end end
        local function get(id,prop) return fibaro.get(id,prop) end
        local function on(id,prop) return BN(fibaro.get(id,prop)) > 0 end
        local function off(id,prop) return BN(fibaro.get(id,prop)) == 0 end
        local function call(id,cmd) fibaro.call(id,cmd); return true end
        local function profile(id,_) return api.get("/profiles/"..id.."?showHidden=true") end
        local function child(id,_) return quickApp.childDevices[id] end
        local function last(id,prop) local _,t=fibaro.get(id,prop); local r = t and os.time()-t or 0; return r end
        local function cce(id,_,e) e=e.event; return e.type=='device' and e.property=='centralSceneEvent'and e.id==id and e.value or {} end
        local function ace(id,_,e) e=e.event; return e.type=='device' and e.property=='accessControlEvent' and e.id==id and e.value or {} end
        local function sae(id,_,e) e=e.event; return e.type=='device' and e.property=='sceneActivationEvent' and e.id==id and e.value.sceneId end
        local mapOr,mapAnd,mapF=table.mapOr,table.mapAnd,function(f,l,s) table.mapf(f,l,s); return true end
        local function partition(id) return api.get("/alarms/v1/partitions/" .. id) or {} end
        local function arm(id,action)
            local PIN = Script.get('PIN')[1]
            if PIN == nil then return false end
            local url = id == 0 and 'http://192.168.1.57/api/alarms/v1/partitions/actions/arm' or 'http://192.168.1.57/api/alarms/v1/partitions/' .. id .. '/actions/arm'
            local method = action == 'arm' and 'POST' or 'DELETE'
            net.HTTPClient():request(url, { 
                options = { 
                    method=method,
                    headers = { 
                        ['Fibaro-User-PIN'] = PIN,
                        ['Authorization'] = fibaro.utils.basicAuthorization("admin","admin"),
                        ['X-Fibaro-Version'] = '2',
                        ['accept'] = '*/*'
                     }
                },
                success = function(resp) end,
                error = function(err) fibaro.post({type='alarm',id=id,action=action,property='error',value=err}) end
            })
        end
        local function tryArm(id)
            local PIN = Script.get('PIN')[1]
            if PIN == nil then return false end
            local url = id == 0 and 'http://192.168.1.57/api/alarms/v1/partitions/actions/tryArm' or 'http://192.168.1.57/api/alarms/v1/partitions/' .. id .. '/actions/tryArm'
            net.HTTPClient():request(url, { 
                options = { 
                    method='POST',
                    headers = { 
                        ['Fibaro-User-PIN'] = PIN,
                        ['Authorization'] = fibaro.utils.basicAuthorization("admin","admin"),
                        ['X-Fibaro-Version'] = '2',
                        ['accept'] = '*/*'
                     }
                },
                success = function(resp)
                    resp = json.decode(resp.data)
                    if resp.result == 'armDelayed' then fibaro.post({type='alarm',id=id,action='tryArm',property='armDelayed',value=resp.breachedDevices}) end
                end,
                error = function(err) fibaro.post({type='alarm',id=id,action='tryArm',property='error',value=err}) end
            })
        end
        local helpers = { BN=BN, get=get, on=on, off=off, call=call, profile=profile, child=child, last=last, cce=cce, ace=ace, sae=sae, mapOr=mapOr, mapAnd=mapAnd, mapF=mapF }
        
        local getProps={}
        -- { type, function to get prop, property name in sourceTrigger, reduce function, if props is a rule trigger }
        getProps.value={'device',get,'value',nil,true}
        getProps.state={'device',get,'state',nil,true}
        getProps.bat={'device',get,'batteryLevel',nil,true}
        getProps.power={'device',get,'power',nil,true}
        getProps.isDead={'device',get,'dead',mapOr,true}
        getProps.isOn={'device',on,'value',mapOr,true}
        getProps.isOff={'device',off,'value',mapAnd,true}
        getProps.isAllOn={'device',on,'value',mapAnd,true}
        getProps.isAnyOff={'device',off,'value',mapOr,true}
        getProps.last={'device',last,'value',nil,true}
        
        getProps.tryArm={'alarm',tryArm,nil,'alarm',false}
        getProps.armed={'alarm',function(id) return partition(id).armed end,'armed',mapOr,true}
        getProps.allArmed={'alarm',function(id) return partition(id).armed end,'armed',mapAnd,true,true}
        getProps.disarmed={'alarm',function(id) return partition(id).armed==false end,'armed',mapAnd,true}
        getProps.anyDisarmed={'alarm',function(id) return partition(id).armed==false end,'armed',mapOr,true,false}
        getProps.alarmBreached={'alarm',function(id) return partition(id).breached end,'breached',mapOr,true}
        getProps.alarmSafe={'alarm',function(id) return partition(id).breached==false end,'breached',mapAnd,true}
        getProps.allAlarmBreached={'alarm',function(id) return partition(id).breached end,'breached',mapAnd,true}
        getProps.anyAlarmSafe={'alarm',function(id) return partition(id).breached==false end,'breached',mapOr,true,false}

        getProps.child={'device',child,nil,nil,false}
        getProps.profile={'device',profile,nil,nil,false}
        getProps.scene={'device',sae,'sceneActivationEvent',nil,true}
        getProps.access={'device',ace,'accessControlEvent',nil,true}
        getProps.central={'device',cce,'centralSceneEvent',nil,true}
        getProps.safe={'device',off,'value',mapAnd,true}
        getProps.breached={'device',on,'value',mapOr,true}
        getProps.isOpen={'device',on,'value',mapOr,true}
        getProps.isClosed={'device',off,'value',mapAnd,true}
        getProps.lux={'device',get,'value',nil,true}
        getProps.volume={'device',get,'volume',nil,true}
        getProps.position={'device',get,'position',nil,true}
        getProps.temp={'device',get,'value',nil,true}
        getProps.coolingThermostatSetpoint={'device',get,'coolingThermostatSetpoint',nil,true}
        getProps.coolingThermostatSetpointCapabilitiesMax={'device',get,'coolingThermostatSetpointCapabilitiesMax',nil,true}
        getProps.coolingThermostatSetpointCapabilitiesMin={'device',get,'coolingThermostatSetpointCapabilitiesMin',nil,true}
        getProps.coolingThermostatSetpointFuture={'device',get,'coolingThermostatSetpointFuture',nil,true}
        getProps.coolingThermostatSetpointStep={'device',get,'coolingThermostatSetpointStep',nil,true}
        getProps.heatingThermostatSetpoint={'device',get,'heatingThermostatSetpoint',nil,true}
        getProps.heatingThermostatSetpointCapabilitiesMax={'device',get,'heatingThermostatSetpointCapabilitiesMax',nil,true}
        getProps.heatingThermostatSetpointCapabilitiesMin={'device',get,'heatingThermostatSetpointCapabilitiesMin',nil,true}
        getProps.heatingThermostatSetpointFuture={'device',get,'heatingThermostatSetpointFuture',nil,true}
        getProps.heatingThermostatSetpointStep={'device',get,'heatingThermostatSetpointStep',nil,true}
        getProps.thermostatFanMode={'device',get,'thermostatFanMode',nil,true}
        getProps.thermostatFanOff={'device',get,'thermostatFanOff',nil,true}
        getProps.thermostatMode={'device',get,'thermostatMode',nil,true}
        getProps.thermostatModeFuture={'device',get,'thermostatModeFuture',nil,true}
        getProps.on={'device',call,'turnOn',mapF,true}
        getProps.off={'device',call,'turnOff',mapF,true}
        getProps.play={'device',call,'play',mapF,nil}
        getProps.pause={'device',call,'pause',mapF,nil}
        getProps.open={'device',call,'open',mapF,true}
        getProps.close={'device',call,'close',mapF,true}
        getProps.stop={'device',call,'stop',mapF,true}
        getProps.secure={'device',call,'secure',mapF,false}
        getProps.unsecure={'device',call,'unsecure',mapF,false}
        getProps.isSecure={'device',on,'secured',mapAnd,true}
        getProps.isUnsecure={'device',off,'secured',mapOr,true}
        getProps.name={'device',function(id) return fibaro.getName(id) end,nil,nil,false}
        getProps.HTname={'device',function(id) return Util.reverseVar(id) end,nil,nil,false}
        getProps.roomName={'device',function(id) return fibaro.getRoomNameByDeviceID(id) end,nil,nil,false}
        getProps.trigger={'device',function() return true end,'value',nil,true}
        getProps.time={'device',get,'time',nil,true}
        getProps.manual={'device',function(id) return quickApp:lastManual(id) end,'value',nil,true}
        getProps.start={'device',function(id) return fibaro.scene("execute",{id}) end,"",mapF,false}
        getProps.kill={'device',function(id) return fibaro.scene("kill",{id}) end,"",mapF,false}
        getProps.toggle={'device',call,'toggle',mapF,true}
        getProps.wake={'device',call,'wakeUpDeadDevice',mapF,true}
        getProps.removeSchedule={'device',call,'removeSchedule',mapF,true}
        getProps.retryScheduleSynchronization={'device',call,'retryScheduleSynchronization',mapF,true}
        getProps.setAllSchedules={'device',call,'setAllSchedules',mapF,true}
        getProps.levelIncrease={'device',call,'startLevelIncrease',mapF,nil}
        getProps.levelDecrease={'device',call,'startLevelDecrease',mapF,nil}
        getProps.levelStop={'device',call,'stopLevelChange',mapF,nil}
        
        -- setProps helpers
        local function set(id,cmd,val) fibaro.call(id,cmd,val); return val end
        local function set2(id,cmd,val) fibaro.call(id,cmd,table.unpack(val)); return val end
        local function setProfile(id,_,val) if val then fibaro.profile("activateProfile",id) end return val end
        local function setState(id,_,val) fibaro.call(id,"updateProperty","state",val); return val end
        local function setProps(id,cmd,val) fibaro.call(id,"updateProperty",cmd,val); return val end
        local function dim2(id,_,val) ER.utilities.dimLight(id,table.unpack(val)) end
        local function pushMsg(id,cmd,val) fibaro.alert(fibaro._pushMethod,{id},val,false,''); return val end
        local function setAlarm(id,cmd,val) arm(id,val and 'arm' or 'disarm') return val end
        helpers.set, helpers.set2, helpers.setProfile, helpers.setState, helpers.setProps, helpers.dim2, helpers.pushMsg = set, set2, setProfile, setState, setProps, dim2, pushMsg
        
        local setProps = {}
        -- { function to get prop, property name }
        setProps.R={set,'setR'} -- Don't think the RGBs are valid anymore...
        setProps.G={set,'setG'}
        setProps.B={set,'setB'}
        setProps.W={set,'setW'}
        setProps.value={set,'setValue'}
        setProps.state={setState,'setState'}

        setProps.armed={setAlarm,'setAlarm'}

        setProps.profile={setProfile,'setProfile'}
        setProps.time={set,'setTime'}
        setProps.power={set,'setPower'}
        setProps.targetLevel={set,'setTargetLevel'}
        setProps.interval={set,'setInterval'}
        setProps.mode={set,'setMode'}
        setProps.setpointMode={set,'setSetpointMode'}
        setProps.defaultPartyTime={set,'setDefaultPartyTime'}
        setProps.scheduleState={set,'setScheduleState'}
        setProps.color={set2,'setColor'}
        setProps.volume={set,'setVolume'}
        setProps.position={set,'setPosition'}
        setProps.positions={setProps,'availablePositions'}
        setProps.mute={set,'setMute'}
        setProps.thermostatSetpoint={set2,'setThermostatSetpoint'}
        setProps.thermostatMode={set,'setThermostatMode'}
        setProps.heatingThermostatSetpoint={set,'setHeatingThermostatSetpoint'}
        setProps.coolingThermostatSetpoint={set,'setCoolingThermostatSetpoint'}
        setProps.thermostatFanMode={set,'setThermostatFanMode'}
        setProps.schedule={set2,'setSchedule'}
        setProps.dim={dim2,'dim'}
        fibaro._pushMethod = 'push'
        setProps.msg={pushMsg,"push"}
        setProps.defemail={set,'sendDefinedEmailNotification'}
        setProps.btn={set,'pressButton'} -- ToDo: click button on QA?
        setProps.email={function(id,_,val) local _,_ = val:match("(.-):(.*)"); fibaro.alert('email',{id},val) return val end,""}
        setProps.start={function(id,_,val) 
            if isEvent(val) then 
                quickApp:postRemote(id,val) return true
            else 
                fibaro.scene("execute",{id}) return true
            end
        end,""}

        local filters = ER.propFilters
        local function NB(x) if type(x)=='number' then return x~=0 and 1 or 0 else return x end end
        local function mapAnd(l) for _,v in ipairs(l) do if not NB(v) then return false end end return true end
        local function mapOr(l) for _,v in ipairs(l) do if NB(v) then return true end end return false end
        function filters.average(list) local s = 0; for _,v in ipairs(list) do s=s+BN(v) end return s/#list end
        function filters.sum(list) local s = 0; for _,v in ipairs(list) do s=s+BN(v) end return s end
        function filters.allFalse(list) return not mapOr(list) end
        function filters.someFalse(list) return not mapAnd(list)  end
        function filters.allTrue(list) return mapAnd(list) end
        function filters.someTrue(list) return mapOr(list)  end
        function filters.mostlyTrue(list) local s = 0; for _,v in ipairs(list) do s=s+(NB(v) and 1 or 0) end return s>#list/2 end
        function filters.mostlyFalse(list) local s = 0; for _,v in ipairs(list) do s=s+(NB(v) and 0 or 1) end return s>#list/2 end
        function filters.bin(list) local s={}; for _,v in ipairs(list) do s[#s+1]=NB(v) and 1 or 0 end return s end


        return getProps,setProps,helpers
    end

    -------------- builtin functions -------------------------
    args.post = {1,2}
    function builtin.post(i,st,p) 
        local e,t,env,r=st.pop(),0,p.args[1] or {},nil
        if i[3]==2 then t=e; e=st.pop() end
        r = Script.post(p,e,t,"post",env.rule)
        st.push(r)
    end
    args.cancel = {1,1}
    function builtin.cancel(i,st,p) Script.clearTimeout(p,st.pop()) st.push(nil) end
    
    local function encodeObj(o) if getmetatable(o) then return tostring(o) else return encodeFast(o) end end
    args.log = {1,99}
    function builtin.log(i,st,p)
        local args,n = st.popm(i[3]),i[3]
        local str = ""
        for i=1,#args do if type(args[i])=='table' then args[i]=encodeObj(args[i]) end end
        if #args < n then for i=1,n-#args do args[#args+1]='nil' end end
        if #args == 1 then str=args[1]
        elseif #args>1 then str = fmt(table.unpack(args)) end
        fibaro.debug(p.rule and p.rule._ltag or ER.er.ltag or __TAG,str)
        st.push(str)
    end
    
    args.fmt = {1,99}
    function builtin.fmt(i,st,p) st.push(string.format(table.unpack(st.lift(i[3])))) end
    args.HM = {1,1}
    function builtin.HM(i,st,p) local t = st.pop(); st.push(os.date("%H:%M",t < os.time() and t+midnight() or t)) end  
    args.HMS = {1,1}
    function builtin.HMS(i,st,p) local t = st.pop(); st.push(os.date("%H:%M:%S",t < os.time() and t+midnight() or t)) end  
    args.sign = {1,1}
    function builtin.sign(i,st,p) st.push(tonumber(st.pop()) < 0 and -1 or 1) end
    args.rnd = {1,2}
    function builtin.rnd(i,st,p) local ma,mi=st.pop(),i[3]>1 and st.pop() or 1 st.push(math.random(mi,ma)) end
    args.round = {1,1}
    function builtin.round(i,st,p) local v=st.pop(); st.push(math.floor(v+0.5)) end
    args.sum = {1,1}
    function builtin.sum(i,st,p) local m,res=st.pop(),0 for _,x in ipairs(m) do res=res+x end st.push(res) end 
    args.average = {1,1}
    function builtin.average(i,st,p) local m,res=st.pop(),0 for _,x in ipairs(m) do res=res+x end st.push(res/#m) end 
    args.size = {1,1}
    function builtin.size(i,st,p) st.push(#(st.pop())) end
    args.min = {1,99}
    function builtin.min(i,st,p) st.push(math.min(table.unpack(type(st.peek())=='table' and st.pop() or st.lift(i[3])))) end
    args.max = {1,99}
    function builtin.max(i,st,p) st.push(math.max(table.unpack(type(st.peek())=='table' and st.pop() or st.lift(i[3])))) end
    args.sort = {1,99}
    function builtin.sort(i,st,p) local a = type(st.peek())=='table' and st.pop() or st.lift(i[3]); table.sort(a) st.push(a) end
    args.match = {2,2}
    function builtin.match(i,st,p) local a,b=st.pop(),st.pop(); st.push(string.match(b,a)) end
    args.osdate = {0,1}
    function builtin.osdate(i,st,p) local x,y = st.peek(i[3]-1),(i[3]>1 and st.pop() or nil) st.pop(); st.push(os.date(x,y)) end
    args.ostime = {0,0}
    function builtin.ostime(i,st,p) st.push(os.time()) end
    args.global = {1,1}
    function builtin.global(i,st)       st.push(api.post("/globalVariables/",{name=st.pop()})) end  
    args.listglobals = {0,0}
    function builtin.listglobals(i,st)  st.push(api.get("/globalVariables/")) end
    args.deleteglobal = {1,1}
    function builtin.deleteglobal(i,st) st.push(api.delete("/globalVariables/"..st.pop())) end
    args.subscribe = {1,1}
    function builtin.subscribe(i,st,p) quickApp:subscribe(st.pop()) st.push(true) end
    args.publish = {1,2}
    function builtin.publish(i,st,p) local e,t=st.pop(),nil; if i[3]==2 then t=e; e=st.pop() end quickApp:publish(e,t) st.push(e) end
    args.remote = {2,2}
    function builtin.remote(i,st,p) 
        local e,u=st.pop(),st.pop(); 
        quickApp:postRemote(u,e)
        st.push(true) 
    end
    args.add = {2,2}
    function builtin.adde(i,st,p) local v,t=st.pop(),st.pop() table.insert(t,v) st.push(t) end
    args.remove = {2,2}
    function builtin.remove(i,st,p) local v,t=st.pop(),st.pop() table.remove(t,v) st.push(t) end
    args.enable = {0,1}
    function builtin.enable(i,st,p)
        if i[3] == 0 then
            p.rule.enable()
            st.push(true)
            return
        end
        local t,g = st.pop(),false; if n==2 then g,t=t,st.pop() end 
        st.push(fibaro.EM.enable(t,g))
    end
    args.disable = {0,1}
    function builtin.disable(i,st,p)
        if i[3] == 0 then p.rule.disable() st.push(true) return end
        local r = st.pop()
        st.push(r.disable())
    end
    args.yield = {0,99}
    function builtin.yield(i,st,p) 
        local args = st.popm(i[3])
        p.yielded = true; 
        st.push(args); 
        return 'multiple_values' 
    end
    args.wait = {1,2}
    function builtin.wait(i,st,p)
        if not p.co then errorf(p,"wait called outside of coroutine") end
        local args,n = st.popm(i[3]),i[3]
        p.yielded = true;
        args[1] = args[1] * 1000
        st.push({"%wait%",table.unpack(args)}); return 'multiple_values'
    end
    args.once = {0,2}
    function builtin.once(i,st,p) -- i[4] is last state
        local n = i[3]            -- i[5] is optional timer to reset state
        if n==1 then local f; i[4],f = st.pop(),i[4]; st.push(not f and i[4]) 
        elseif n==2 then 
            local f,g,e; e,i[4],f = st.pop(),st.pop(),i[4]; g=not f and i[4]; st.push(g) --ToDo verify args
            if g then Script.cancel(p,i[5]) i[5]=Script.post(p,function() i[4]=nil end,e,"once") end
        else 
            local f; i[4],f=os.date("%x"),i[4] or ""; st.push(f ~= i[4]) -- once daily...
        end
    end
    args.again = {0,1}
    function builtin.again(i,st,p)
        local env,n = p.args[1] or {},i[3]
        local rule = env.rule
        local flags = rule.trueForFlags or {}; rule.trueForFlags=flags
        --- ToDo: check if again is called in a tryeFor rule
        local v = n>0 and st.pop() or math.huge
        flags.again = (flags.again or 0)+1
        if v > flags.again then setTimeout(function() rule.start(flags.event) end,0) else flags.again,flags.even = nil,nil end
        st.push(flags.again or v)
    end
    args.trueFor = {2,3}
    function builtin.trueFor(i,st,p)
        local time,val,log = table.unpack(st.popm(i[3]))
        log = log == true
        local env = p.args[1] or {}
        local id,rule,event = env.rule.id,env.rule,env.event
        local flags = rule.trueForFlags or {}; rule.trueForFlags=flags
        if val then
            if flags.expired then -- we are called when timer has expired, return true and advance to action...
                if log then env.co.LOG("trueFor true") end
                st.push(val);
                flags.expired=nil;
                return
            end
            if flags.timer then st.push(false); if log then print("trueFor waiting") end return end -- still wating
            flags.timer = Script.setTimeout(p,function()
                flags.expired,flags.timer=true,nil; 
                Script.post(p,{type='trueFor',id=id,status='action',time=time,rule=rule,_sh=true})
                rule.start(event)
            end,1000*time,"trueFor");
            if log then env.co.LOG("trueFor started") end
            flags.event = event
            Script.post(p,{type='trueFor',id=id,status='started',time=time,rule=rule,_sh=true})
            st.push(false); return
        else -- value false, cancel timer
            if log then env.co.LOG("trueFor false") end
            if flags.timer then
                flags.timer=Script.clearTimeout(p,flags.timer)
                Script.post(p,{type='trueFor',id=id,status='cancelled',time=time,rule=rule,_sh=true})
            end
            st.push(false)
        end
    end
    
    ------------------ for loop builtins ---------------------
    args.idxsetup = {3,3}
    function builtin.idxsetup(i,st,p) -- 'idxsetup',{idx,sgv,stopv,stepv},{sav,sov,se})
        local env = p.env
        local idx,sgv,stopv,stepv = table.unpack(i,4)
        local sav,sov,se = table.unpack(st.popm(i[3]))
        env.push(idx,sav)
        env.push(stopv,sov)
        env.push(stepv,se)
        env.push(sgv,se < 0 and -1 or 1)
        st.push(true)
    end
    
    args.idxcond = {0,0}
    function builtin.idxcond(i,st,p) -- 'idxcond',{idx,sgv,stopv}),
        local env = p.env
        local idx,sgv,stopv = table.unpack(i,4)
        idx,sgv,stopv = env.get(idx)[1],env.get(sgv)[1],env.get(stopv)[1]
        st.push(idx*sgv <= stopv*sgv)
    end
    
    args.idxinc = {0,0}
    function builtin.idxinc(i,st,p) -- 'idxinc',{idx,sgv})
        local env = p.env
        local idx,stepv = table.unpack(i,4)
        env.set(idx,env.get(idx)[1]+env.get(stepv)[1])
        st.push(true)
    end
    
    args.flsetup = {1,1}
    function builtin.flsetup(i,st,p) -- 'flsetup',{kvar,vvar,fvar,lvar,svar},{expr})
        local env = p.env
        local kvar,vvar,fvar,lvar,svar = table.unpack(i,4)
        local f,l,s = table.unpack(st.popm(1))
        env.push(fvar,f)
        env.push(lvar,l)
        --env.push(svar,s)
        env.push(kvar,s)
        env.push(vvar,nil)
        st.push(true)
    end
    
    args.flinc = {0,0}
    function builtin.flinc(i,st,p) -- 'flinc',{kvar,vvar,fvar,lvar},{})
        local env = p.env
        local kvar,vvar,fvar,lvar,v = table.unpack(i,4)
        local k,f,l = env.get(kvar)[1],env.get(fvar)[1],env.get(lvar)[1]
        k,v = f(l,k)
        env.set(kvar,k)
        env.set(vvar,v)
        st.push(true)
    end
    
    --------------------------
    
    local function httpCall(url,options,data)
        local opts = table.copy(options)
        opts.headers = opts.headers or {}
        if opts.type then
            opts.headers["content-type"]=opts.type
            opts.type=nil
        end
        if not opts.headers["content-type"] then
            opts.headers["content-type"] = 'application/json'
        end
        if opts.user or opts.pwd then 
            opts.headers['Authorization']= fibaro.utils.basicAuthorization((opts.user or ""),(opts.pwd or ""))
            opts.user,opts.pwd=nil,nil
        end
        opts.data = data and json.encode(data)
        local basket = {}
        net.HTTPClient():request(url,{
            options=opts,
            success = function(res0)
                pcall(function()
                    res0.data = json.decode(res0.data)  
                end)
                basket[1](res0) 
            end,
            error = function(res0) basket[1](res0) end
        })
        return '%magic_suspend%',basket
    end
    
    local http = {}
    function http.get(url,options) options=options or {}; options.method="GET" return httpCall(url,options) end
    function http.put(url,options,data) options=options or {}; options.method="PUT" return httpCall(url,options,data) end
    function http.post(url,options,data) options=options or {}; options.method="POST" return httpCall(url,options,data) end
    function http.delete(url,options) options=options or {}; options.method="DELETE" return httpCall(url,options) end
    defVars.http = http
    
    local function getFibObj(path,p,k,v)
        local oo = api.get(path) or {}
        if p then oo = oo[p] end
        for _,o in ipairs(oo or {}) do
            if o[k]==v then return o end
        end
    end
    defVars.LOC = function(name) return getFibObj("/panels/location",nil,"name",name) end
    defVars.USER = function(name) return getFibObj("/users",nil,"name",name) end
    defVars.PHONE = function(name) return getFibObj("/iosDevices",nil,"name",name) end
    defVars.PART = function(name) return getFibObj("/alarms/v1/partitions",nil,"name",name) end
    defVars.PROF = function(name) return getFibObj("/profiles","profiles","name",name) end
    defVars.CLIM = function(name) return getFibObj("/panels/climate",nil,"name",name) end
    defVars.SPRINK = function(name) return getFibObj("/panels/sprinklers",nil,"name",name) end
    
    defVars.S1 = {click = "16", double = "14", tripple = "15", hold = "12", release = "13"}
    defVars.S2 = {click = "26", double = "24", tripple = "25", hold = "22", release = "23"}
    defVars.catch = math.huge
    function QuickApp:printTagAndColor(tag,color,fmt,...)
        assert(fmt,"print needs tag, color, and args")
        fmt = string.format(fmt,...)
        local t = __TAG
        __TAG = tag or __TAG
        if hc3_emulator or not color then self:tracef(fmt,...) 
        else
            self:trace("<font color="..color..">"..fmt.."</font>") 
        end
        __TAG = t
    end
    defVars.print = function(...) quickApp:printTagAndColor(...) end
    --defVars.QA = quickApp
    
  definePropClass('Weather')
  function Weather:__init() PropObject.__init(self) end
  function Weather.getProp.temperature(id,prop,event) return fibaro.weather.temperature() end
  function Weather.getProp.temperatureUnit(id,prop,event) return fibaro.weather.temperatureUnit() end
  function Weather.getProp.humidity(id,prop,event) return fibaro.weather.humidity() end
  function Weather.getProp.wind(id,prop,event) return fibaro.weather.wind() end
  function Weather.getProp.condition(id,prop,event) return fibaro.weather.weatherCondition() end
  function Weather.getProp.code(id,prop,event) return fibaro.weather.conditionCode() end

  function Weather.trigger.temperature(id,prop) return {type='weather', property='Temperature'} end
  function Weather.trigger.temperatureUnit(id,prop) return {type='weather', property='TemperatureUnit'} end
  function Weather.trigger.humidity(id,prop) return {type='weather', property='Humidity'} end
  function Weather.trigger.wind(id,prop) return {type='weather', property='Wind'} end
  function Weather.trigger.condition(id,prop) return {type='weather', property='WeatherCondition'} end
  function Weather.trigger.code(id,prop) return {type='weather', property='ConditionCode'} end

  defVars.weather = Weather()
end