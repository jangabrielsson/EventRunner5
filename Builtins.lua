QuickApp.__ER  = QuickApp.__ER or { modules={} }

function QuickApp.__ER.modules.builtins(ER)
    
    local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
    marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
    PrintBuffer,sunData =
    table.unpack(ER.utilities.export)
    
    local builtin = ER.builtins
    local args = ER.builtinArgs
    local defVars = ER.localDefVars
    local fmt = string.format
    
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
        local helpers = { BN=BN, get=get, on=on, off=off, call=call, profile=profile, child=child, last=last, cce=cce, ace=ace, sae=sae, mapOr=mapOr, mapAnd=mapAnd, mapF=mapF }
        
        local getProps={}
        -- { function to get prop, property name in sourceTrigger, reduce function, if props is a rule trigger }
        getProps.value={get,'value',nil,true}
        getProps.state={get,'state',nil,true}
        getProps.bat={get,'batteryLevel',nil,true}
        getProps.power={get,'power',nil,true}
        getProps.isDead={get,'dead',mapOr,true}
        getProps.isOn={on,'value',mapOr,true}
        getProps.isOff={off,'value',mapAnd,true}
        getProps.isAllOn={on,'value',mapAnd,true}
        getProps.isAnyOff={off,'value',mapOr,true}
        getProps.last={last,'value',nil,true}
        getProps.alarm={alarm,nil,'alarm',true}
        getProps.armed={function(id) return gp(id).armed end,'armed',mapOr,true}
        getProps.allArmed={function(id) return gp(id).armed end,'armed',mapAnd,true,true}
        getProps.disarmed={function(id,_,_) return not gp(id).armed end,'armed',mapAnd,true}
        getProps.anyDisarmed={function(id,_,_) return not gp(id).armed end,'armed',mapOr,true,false}
        getProps.alarmBreached={function(id) return gp(id).breached end,'breached',mapOr,true}
        getProps.alarmSafe={function(id) return not gp(id).breached end,'breached',mapAnd,true}
        getProps.allAlarmBreached={function(id) return gp(id).breached end,'breached',mapAnd,true}
        getProps.anyAlarmSafe={function(id) return not gp(id).breached end,'breached',mapOr,true,false}
        getProps.willArm={function(id) return armedPs[id] end,'willArm',mapOr,true}
        getProps.allWillArm={function(id) return armedPs[id] end,'willArm',mapAnd,true}
        getProps.child={child,nil,nil,false}
        getProps.profile={profile,nil,nil,false}
        getProps.scene={sae,'sceneActivationEvent',nil,true}
        getProps.access={ace,'accessControlEvent',nil,true}
        getProps.central={cce,'centralSceneEvent',nil,true}
        getProps.safe={off,'value',mapAnd,true}
        getProps.breached={on,'value',mapOr,true}
        getProps.isOpen={on,'value',mapOr,true}
        getProps.isClosed={off,'value',mapAnd,true}
        getProps.lux={get,'value',nil,true}
        getProps.volume={get,'volume',nil,true}
        getProps.position={get,'position',nil,true}
        getProps.temp={get,'value',nil,true}
        getProps.coolingThermostatSetpoint={get,'coolingThermostatSetpoint',nil,true}
        getProps.coolingThermostatSetpointCapabilitiesMax={get,'coolingThermostatSetpointCapabilitiesMax',nil,true}
        getProps.coolingThermostatSetpointCapabilitiesMin={get,'coolingThermostatSetpointCapabilitiesMin',nil,true}
        getProps.coolingThermostatSetpointFuture={get,'coolingThermostatSetpointFuture',nil,true}
        getProps.coolingThermostatSetpointStep={get,'coolingThermostatSetpointStep',nil,true}
        getProps.heatingThermostatSetpoint={get,'heatingThermostatSetpoint',nil,true}
        getProps.heatingThermostatSetpointCapabilitiesMax={get,'heatingThermostatSetpointCapabilitiesMax',nil,true}
        getProps.heatingThermostatSetpointCapabilitiesMin={get,'heatingThermostatSetpointCapabilitiesMin',nil,true}
        getProps.heatingThermostatSetpointFuture={get,'heatingThermostatSetpointFuture',nil,true}
        getProps.heatingThermostatSetpointStep={get,'heatingThermostatSetpointStep',nil,true}
        getProps.thermostatFanMode={get,'thermostatFanMode',nil,true}
        getProps.thermostatFanOff={get,'thermostatFanOff',nil,true}
        getProps.thermostatMode={get,'thermostatMode',nil,true}
        getProps.thermostatModeFuture={get,'thermostatModeFuture',nil,true}
        getProps.on={call,'turnOn',mapF,true}
        getProps.off={call,'turnOff',mapF,true}
        getProps.play={call,'play',mapF,nil}
        getProps.pause={call,'pause',mapF,nil}
        getProps.open={call,'open',mapF,true}
        getProps.close={call,'close',mapF,true}
        getProps.stop={call,'stop',mapF,true}
        getProps.secure={call,'secure',mapF,false}
        getProps.unsecure={call,'unsecure',mapF,false}
        getProps.isSecure={on,'secured',mapAnd,true}
        getProps.isUnsecure={off,'secured',mapOr,true}
        getProps.name={function(id) return fibaro.getName(id) end,nil,nil,false}
        getProps.HTname={function(id) return Util.reverseVar(id) end,nil,nil,false}
        getProps.roomName={function(id) return fibaro.getRoomNameByDeviceID(id) end,nil,nil,false}
        getProps.trigger={function() return true end,'value',nil,true}
        getProps.time={get,'time',nil,true}
        getProps.manual={function(id) return quickApp:lastManual(id) end,'value',nil,true}
        getProps.start={function(id) return fibaro.scene("execute",{id}) end,"",mapF,false}
        getProps.kill={function(id) return fibaro.scene("kill",{id}) end,"",mapF,false}
        getProps.toggle={call,'toggle',mapF,true}
        getProps.wake={call,'wakeUpDeadDevice',mapF,true}
        getProps.removeSchedule={call,'removeSchedule',mapF,true}
        getProps.retryScheduleSynchronization={call,'retryScheduleSynchronization',mapF,true}
        getProps.setAllSchedules={call,'setAllSchedules',mapF,true}
        getProps.levelIncrease={call,'startLevelIncrease',mapF,nil}
        getProps.levelDecrease={call,'startLevelDecrease',mapF,nil}
        getProps.levelStop={call,'stopLevelChange',mapF,nil}
        
        -- setProps helpers
        local function set(id,cmd,val) fibaro.call(id,cmd,val); return val end
        local function set2(id,cmd,val) fibaro.call(id,cmd,table.unpack(val)); return val end
        local function setProfile(id,_,val) if val then fibaro.profile("activateProfile",id) end return val end
        local function setState(id,_,val) fibaro.call(id,"updateProperty","state",val); return val end
        local function setProps(id,cmd,val) fibaro.call(id,"updateProperty",cmd,val); return val end
        local function dim2(id,_,val) ER.utilities.dimLight(id,table.unpack(val)) end
        local function pushMsg(id,cmd,val) fibaro.alert(fibaro._pushMethod,{id},val,false,''); return val end
        helpers.set, helpers.set2, helpers.setProfile, helpers.setState, helpers.setProps, helpers.dim2, helpers.pushMsg = set, set2, setProfile, setState, setProps, dim2, pushMsg
        
        local setProps = {}
        -- { function to get prop, property name }
        setProps.R={set,'setR'} -- Don't think the RGBs are valid anymore...
        setProps.G={set,'setG'}
        setProps.B={set,'setB'}
        setProps.W={set,'setW'}
        setProps.value={set,'setValue'}
        setProps.state={setState,'setState'}
        setProps.alarm={setAlarm,'setAlarm'}
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
        return getProps,setProps,helpers
    end
    
    -------------- builtin functions -------------------------
    args.post = {1,2}
    function builtin.post(i,st,p) 
        local e,t,env,r=st.pop(),0,p.args[1] or {},nil
        if i[3]==2 then t=e; e=st.pop() end
        if t == 0 then r = fibaro.post(e,t,env.rule)
        else
            r = p.ctx.setTimeout(p,function() fibaro.post(e,0,env.rule) end,t*1000,"post")
        end
        st.push(r)
    end
    args.cancel = {1,1}
    function builtin.cancel(i,st,p) p.ctx.clearTimeout(p,st.pop()) st.push(nil) end
    
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
            local f,g,e; e,i[4],f = st.pop(),st.pop(),i[4]; g=not f and i[4]; st.push(g) 
            if g then fibaro.cancel(i[5]) i[5]=fibaro.post(function() i[4]=nil end,e) end
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
            flags.timer = p.ctx.setTimeout(p,function()
                flags.expired,flags.timer=true,nil; 
                fibaro.post({type='trueFor',id=id,status='action',time=time,rule=rule,_sh=true})
                rule.start(event)
            end,1000*time);
            if log then env.co.LOG("trueFor started") end
            flags.event = event
            fibaro.post({type='trueFor',id=id,status='started',time=time,rule=rule,_sh=true})
            st.push(false); return
        else -- value false, cancel timer
            if log then env.co.LOG("trueFor false") end
            if flags.timer then
                flags.timer=p.ctx.clearTimeout(p,flags.timer)
                fibaro.post({type='trueFor',id=id,status='cancelled',time=time,rule=rule,_sh=true})
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
    
end