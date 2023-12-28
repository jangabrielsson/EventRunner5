---@diagnostic disable: undefined-global
fibaro.__ER  = fibaro.__ER or { modules={} }

function fibaro.__ER.modules.builtins(ER)
    
local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
  PrintBuffer,sunData,LOG,LOGERR,htmlTable,evOpts,eventCustomToString,eformat =
  table.unpack(ER.utilities.export)
    
    local builtin = ER.builtins
    local args = ER.builtinArgs
    local Script = ER.Script
    local defVars = ER.vars
    local fmt = string.format
    local settings = ER.settings

    local definePropClass = ER.definePropClass
    local PropObject = ER.PropObject
    local function isEvent(e) return type(e) == 'table' and type(e.type)=='string' end

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
        devices = function(_,st) st.push(fibaro.getDevicesID()) end,
        quickapps = function(_,st) st.push(fibaro.getDevicesID({interfaces={'quickApp'}})) end,
        quickvars = function(_,st) st.push(table.map(function(g) return g.name end,__fibaro_get_device_property(quickApp.id, "quickAppVariables").value or {})) end,
        globals = function(_,st) st.push(table.map(function(g) return g.name end,api.get('/globalVariables'))) end,
    }

    -------------- builtin props -------------------------
    function ER.setupProps()
        -- getProps helpers
        local function BN(x) if type(x)=='boolean' then return x and 1 or 0 else return tonumber(x) or 0 end end
        local function get(id,prop) return fibaro.get(id,prop) end
        local function getnum(id,prop) return tonumber((fibaro.get(id,prop))) or nil end
        local function on(id,prop) return BN(fibaro.get(id,prop)) > 0 end
        local function off(id,prop) return BN(fibaro.get(id,prop)) == 0 end
        local function call(id,cmd) fibaro.call(id,cmd); return true end
        local function toggle(id,prop) if on(id,prop) then fibaro.call(id,'turnOff') else fibaro.call(id,'turnOn') end return true end
        local function profile(id,_) return api.get("/profiles/"..id.."?showHidden=true") end
        local function child(id,_) return quickApp.childDevices[id] end
        local function last(id,prop) local _,t=fibaro.get(id,prop); local r = t and os.time()-t or 0; return r end
        local function cce(id,_,e) return e.type=='device' and e.property=='centralSceneEvent'and e.id==id and e.value or {} end
        local function ace(id,_,e) return e.type=='device' and e.property=='accessControlEvent' and e.id==id and e.value or {} end
        local function sae(id,_,e) return e.type=='device' and e.property=='sceneActivationEvent' and e.id==id and e.value.sceneId end
        local mapOr,mapAnd,mapF=table.mapOr,table.mapAnd,function(f,l,s) table.mapf(f,l,s); return true end
        local function partition(id) return api.get("/alarms/v1/partitions/" .. id) or {} end
        local function armState(id) return id==0 and fibaro.getHomeArmState() or fibaro.getPartitionArmState(id) end
        local function arm(id,action)
            if action=='arm' then 
                local _,res = fibaro.armPartition(id); return res == 200
            else
                local _,res = fibaro.unarmPartition(id); return res == 200
            end
        end
        local function tryArm(id)
            local data,res = fibaro.tryArmPartition(id)
            if res ~= 200 then return false end
            if type(data) == 'table' then
                fibaro.post({type='alarm',id=id,action='tryArm',property='delayed',value=data})
            end
            return true
        end
        local helpers = { BN=BN, get=get, on=on, off=off, call=call, profile=profile, child=child, last=last, cce=cce, ace=ace, sae=sae, mapOr=mapOr, mapAnd=mapAnd, mapF=mapF }
        
        local getProps={}
        -- { type, function to get prop, property name in sourceTrigger, reduce function, if props is a rule trigger }
        getProps.value={'device',get,'value',nil,true}
        getProps.state={'device',get,'state',nil,true}
        getProps.bat={'device',getnum,'batteryLevel',nil,true}
        getProps.power={'device',getnum,'power',nil,true}
        getProps.isDead={'device',get,'dead',mapOr,true}
        getProps.isOn={'device',on,'value',mapOr,true}
        getProps.isOff={'device',off,'value',mapAnd,true}
        getProps.isAllOn={'device',on,'value',mapAnd,true}
        getProps.isAnyOff={'device',off,'value',mapOr,true}
        getProps.last={'device',last,'value',nil,true}
    
        getProps.armed={'alarm',function(id) return  armState(id)=='armed' end,'armed',mapOr,true}
        getProps.tryArm={'alarm',tryArm,nil,'alarm',false}
        getProps.isArmed={'alarm',function(id) return partition(id).armed end,'armed',mapOr,true}
        getProps.isAllArmed={'alarm',function(id) return partition(id).armed end,'armed',mapAnd,true,true}
        getProps.isDisarmed={'alarm',function(id) return partition(id).armed==false end,'armed',mapAnd,true}
        getProps.isAnyDisarmed={'alarm',function(id) return partition(id).armed==false end,'armed',mapOr,true,false}
        getProps.isAlarmBreached={'alarm',function(id) return partition(id).breached end,'breached',mapOr,true}
        getProps.isAlarmSafe={'alarm',function(id) return partition(id).breached==false end,'breached',mapAnd,true}
        getProps.isAllAlarmBreached={'alarm',function(id) return partition(id).breached end,'breached',mapAnd,true}
        getProps.isAnyAlarmSafe={'alarm',function(id) return partition(id).breached==false end,'breached',mapOr,true,false}

        getProps.child={'device',child,nil,nil,false}
        getProps.profile={'device',profile,nil,nil,false}
        getProps.scene={'device',sae,'sceneActivationEvent',nil,true}
        getProps.access={'device',ace,'accessControlEvent',nil,true}
        getProps.central={'device',cce,'centralSceneEvent',nil,true}
        getProps.safe={'device',off,'value',mapAnd,true}
        getProps.breached={'device',on,'value',mapOr,true}
        getProps.isOpen={'device',on,'value',mapOr,true}
        getProps.isClosed={'device',off,'value',mapAnd,true}
        getProps.lux={'device',getnum,'value',nil,true}
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
        getProps.partition={'alarm',function(id) return partition(id) end,nil,nil,false}
        getProps.HTname={'device',function(id) return ER.reverseVar(id) end,nil,nil,false}
        getProps.roomName={'device',function(id) return fibaro.getRoomNameByDeviceID(id) end,nil,nil,false}
        getProps.trigger={'device',function() return true end,'value',nil,true}
        getProps.time={'device',get,'time',nil,true}
        getProps.manual={'device',function(id) return quickApp:lastManual(id) end,'value',nil,true}
        getProps.start={'device',function(id) return fibaro.scene("execute",{id}) end,"",mapF,false}
        getProps.kill={'device',function(id) return fibaro.scene("kill",{id}) end,"",mapF,false}
        getProps.toggle={'device',toggle,'value',mapF,true}
        getProps.wake={'device',call,'wakeUpDeadDevice',mapF,true}
        getProps.removeSchedule={'device',call,'removeSchedule',mapF,true}
        getProps.retryScheduleSynchronization={'device',call,'retryScheduleSynchronization',mapF,true}
        getProps.setAllSchedules={'device',call,'setAllSchedules',mapF,true}
        getProps.levelIncrease={'device',call,'startLevelIncrease',mapF,nil}
        getProps.levelDecrease={'device',call,'startLevelDecrease',mapF,nil}
        getProps.levelStop={'device',call,'stopLevelChange',mapF,nil}
        getProps.type={'device',function(id) return ER.getDeviceInfo(id).type end,'type',mapF,nil}
        
        -- setProps helpers
        local function set(id,cmd,val) fibaro.call(id,cmd,val); return val end
        local function set2(id,cmd,val) fibaro.call(id,cmd,table.unpack(val)); return val end
        local function setProfile(id,_,val) if val then fibaro.profile("activateProfile",id) end return val end
        local function setState(id,_,val) fibaro.call(id,"updateProperty","state",val); return val end
        local function setProps(id,cmd,val) fibaro.call(id,"updateProperty",cmd,val); return val end
        local function dim2(id,_,val) ER.utilities.dimLight(id,table.unpack(val)) end
        local function pushMsg(id,cmd,val) fibaro.alert(fibaro._pushMethod,{id},val); return val end
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
        setProps.prop={function(id,_,val) fibaro.call(id,"updateProperty",table.unpack(val)) end,'upDateProp'}

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
                fibaro.postRemote(id,val) return true
            else 
                fibaro.scene("execute",{id}) return true
            end
        end,""}
        setProps.sim_pressed={function(id,_,val) fibaro.post({type='device',id=id,property='centralSceneEvent',value={keyId=val,keyAttribute='Pressed'}}) end,"push"} -- For simulated button presses
        setProps.sim_helddown={function(id,_,val) fibaro.post({type='device',id=id,property='centralSceneEvent',value={keyId=val,keyAttribute='HeldDown'}}) end,"push"}
        setProps.sim_released={function(id,_,val) fibaro.post({type='device',id=id,property='centralSceneEvent',value={keyId=val,keyAttribute='Released'}}) end,"push"}

        setProps.isCat={function(id,_,val) return ER.getDeviceInfo(id).categories[val]==true end,"..."}
        setProps.isInterf={function(id,_,val) return ER.getDeviceInfo(id).interfaces[val]==true end,"..."}

        local filters = ER.propFilters
        ER.propFilterTriggers = {}
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
        function filters.GV(list) local s={}; for _,v in ipairs(list) do s[#s+1]=GlobalV(v) end return s end
        ER.propFilterTriggers.GV = true
        function filters.QV(list) local s={}; for _,v in ipairs(list) do s[#s+1]=QuickAppV(v) end return s end
        ER.propFilterTriggers.QV = true
        function filters.id(list,ev) return next(ev) and ev.id or list end -- If we called from rule trigger collector we return whole list
        local function collect(t,m)
            if type(t)=='table' then
                for _,v in pairs(t) do collect(v,m) end
            else m[t]=true end
        end
        function filters.leaf(tree)
            local map,res = {},{}
            collect(tree,map)
            for e,_ in pairs(map) do res[#res+1]=e end
            return res 
        end

        ------------- Device info cache --------------------------------
        local deviceInfo = {}
        local function revMap(l) local r={} for _,v in ipairs(l) do r[v]=true end return r end
        local function mapDevice(d)
            local ifs = revMap(d.interfaces or {})
            local cats = revMap(d.properties.categories or {})
            deviceInfo[d.id] = { interfaces=ifs, categories = cats, type=d.type, name=d.name, roomID=d.roomID, parentId=d.parentId, visible=d.visible, enabled=d.enabled}
        end

        local function getDeviceInfo(id)
            if not deviceInfo[id] then mapDevice(__fibaro_get_device(id)) end
            return deviceInfo[id] or { interfaces={}, categories = {}}
        end
        ER.getDeviceInfo = getDeviceInfo

        for _,d in ipairs(__fibaro_get_devices()) do mapDevice(d) end

        fibaro.event({type='deviceEvent',value='created'},function(env)
            mapDevice(env.event.id)
        end)
 
        fibaro.event({type='deviceEvent',value='modified'},function(env)
            mapDevice(env.event.id)
        end)

        fibaro.event({type='deviceEvent',value='removed'},function(env)
            deviceInfo[env.event.id] = nil
        end)

        defVars.deviceInfo = function(id) return getDeviceInfo(id) end
        --local function mapAnd2(f,l) for _,v in ipairs(l) do if not f(v) then return false end end return true end
        function defVars.isCat(id,c) return getDeviceInfo(id).categories[c]==true end
        ------------------------------------------------------

        return getProps,setProps,helpers
    end

    -------------- builtin functions -------------------------
    args.post = {1,3}
    function builtin.post(i,st,p) 
        local env,r=p.args[1] or {},nil
        local args,n = st.popm(i[3]),i[3]
        local e = args[1]
        local t = args[2] or 0
        local d = args[3] or env.rule or "ER"
        eventCustomToString(e)
        r = Script.post(p,e,t,d)
        st.push(r)
    end
    args.cancel = {1,1}
    function builtin.cancel(i,st,p) Script.clearTimeout(p,st.pop()) st.push(nil) end
    
    local function encodeObj(o) if getmetatable(o) then return tostring(o) else return encodeFast(o) end end
    args.log = {1,99}
    function builtin.log(i,st,p)
        local args,n = st.popm(i[3]),i[3]
        local opts = p.co.options or {}
        local str = ""
        for i=1,n do if type(args[i])=='table' then args[i]=encodeObj(args[i]) end end
        --if #args < n then for i=1,n-#args do args[#args+1]='nil' end end
        if n == 1 then str=tostring(args[1])
        elseif #args>1 then
            local stat,res = pcall(fmt,args[1],args[2],args[3],args[4],args[5],args[6],args[7],args[8])
            if stat then str = res
            else 
                res = res:gsub("bad argument #(%d+)",function(n) return "bad argument #"..(n-1) end)
                errorf(p,"log format: %s",res) 
            end 
        end
        if opts.userLogColor then str = fmt("<font color=%s>%s</font>",opts.userLogColor,str) end
        local prFun = settings.userLogFunction or function(_,tag,str) fibaro.debug(tag,str) end
        local stat,res = pcall(prFun,p.rule,p.rule and p.rule._ltag or ER.er.ltag or __TAG,str)
        if not stat then errorf(p,"userLogFunction: %s",res) end
        st.push(str)
    end
    args.elog = {1,99}
    function builtin.elog(i,st,p)
        local args,n = st.popm(i[3]),i[3]
        local opts = p.co.options or {}
        local stat,str = pcall(eformat,args[1],args[2],args[3],args[4],args[5],args[6],args[7],args[8])
        if not stat then
            str = str:gsub("#(%d+)",function(n) return "bad argument #"..(n-1) end)
            errorf(p,"elog format: %s",str) 
        end
        if opts.userLogColor then str = fmt("<font color=%s>%s</font>",opts.userLogColor,str) end
        local prFun = settings.userLogFunction or fibaro.debug
        local stat,res = pcall(prFun,p.rule,p.rule and p.rule._ltag or ER.er.ltag or __TAG,str)
        if not stat then errorf(p,"userLogFunction: %s",res) end
        st.push(str)
    end

    args.fmt = {1,99}
    function builtin.fmt(i,st,p) st.push(fmt(table.unpack(st.lift(i[3])))) end
    args.efmt = {1,99}
    function builtin.efmt(i,st,p) st.push(eformat(table.unpack(st.lift(i[3])))) end
    args.HM = {1,1}
    function builtin.HM(i,st,p) local t = st.pop(); st.push(os.date("%H:%M",t < os.time()-8760*3600 and t+midnight() or t)) end  
    args.HMS = {1,1}
    function builtin.HMS(i,st,p) local t = st.pop(); st.push(os.date("%H:%M:%S",t < os.time()-8760*3600 and t+midnight() or t)) end  
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
    --args.match = {2,2}
    --function builtin.match(i,st,p) local a,b=st.pop(),st.pop(); st.push(string.match(b,a)) end
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
    function builtin.subscribe(i,st,p) fibaro.subscribe(st.pop()) st.push(true) end
    args.publish = {1,2}
    function builtin.publish(i,st,p) local e,t=st.pop(),nil; if i[3]==2 then t=e; e=st.pop() end fibaro.publish(e,t) st.push(e) end
    args.remote = {2,2}
    function builtin.remote(i,st,p) 
        local e,u=st.pop(),st.pop(); 
        fibaro.postRemote(u,e)
        st.push(true) 
    end
    args.add = {2,2}
    function builtin.adde(i,st,p) local v,t=st.pop(),st.pop() table.insert(t,v) st.push(t) end
    args.remove = {2,2}
    function builtin.remove(i,st,p) local v,t=st.pop(),st.pop() table.remove(t,v) st.push(t) end
    args.enable = {0,2}
    function builtin.enable(i,st,p)
        if i[3] == 0 then 
            p.rule.enable() 
            st.push(true) 
        else
            local tag = st.popm(i[3])
            st.push(ER.enable(tag[1]))
        end
    end
    args.disable = {0,1}
    function builtin.disable(i,st,p)
        if i[3] == 0 then p.rule.disable() st.push(true) return end
        local r = st.pop()
        st.push(ER.disable(r))
    end
    args.yield = {0,99}
    function builtin.yield(i,st,p) 
        local args = st.popm(i[3])
        p.yielded = true; 
        st.push(args); 
        return 'multiple_values'
    end
    args.filter = {3,3}
    function builtin.filter(i,st,p) 
        local out,list,cond = st.pop(),st.pop(),st.pop()
        local v = p.env.get('_')[1]
        if cond and out ~= nil then list[#list+1] = out end
        st.push(out)
    end
    args.wait = {1,2}
    function builtin.wait(i,st,p)
        if not p.co then errorf(p,"wait called outside of coroutine") end
        local args,n = st.popm(i[3]),i[3]
        p.yielded = true;
        args[1] = args[1] * 1000
        st.push({"%wait%",args[1],args[2],args[3]}); return 'multiple_values'
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
        --- ToDo: check if again is called in a trueFor rule
        local v = n>0 and st.pop() or math.huge
        flags.again = (flags.again or 0)+1
        if v > flags.again then setTimeout(function() rule.start0(flags.event) end,0) else flags.again,flags.even = nil,nil end
        st.push(flags.again or v)
    end
    args.trueFor = {2,3}
    function builtin.trueFor(i,st,p)
        local args = st.popm(i[3])
        local time,val,log = args[1],args[2],args[3]
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
                rule.start0(event)
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
        local sav,sov,se = table.unpack((st.popm(i[3])))
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
        local args = st.popm(1)
        local f,l,s = table.unpack(args)
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
    
    local function httpCall(cb,url,options,data,dflt)
        local opts = table.copy(options)
        opts.headers = opts.headers or {}
        if opts.type then
            opts.headers["content-type"]=opts.type
            opts.type=nil
        end
        if not opts.headers["content-type"] then
            opts.headers["content-type"] = 'application/json'
        end
        if opts.user and opts.pwd then 
            opts.headers['Authorization']= fibaro.utils.basicAuthorization((opts.user or ""),(opts.pwd or ""))
            opts.user,opts.pwd=nil,nil
        end
        opts.data = data and json.encode(data)
        opts.checkCertificate = false
        local basket = {}
        net.HTTPClient():request(url,{
            options=opts,
            success = function(res0)
                pcall(function()
                    res0.data = json.decode(res0.data)  
                end)
                cb(res0.data or dflt,res0.status)
            end,
            error = function(err) cb(dflt,err) end
        })
        return opts.timeout and opts.timeout//1000 or 30*1000,"HTTP"
    end
    
    local http = {
        get = ER.asyncFun(function(cb,url,options,dflt) options=options or {}; options.method="GET" return httpCall(cb,url,options,dflt) end),
        put = ER.asyncFun(function(cb,url,options,data,dflt) options=options or {}; options.method="PUT" return httpCall(cb,url,options,data,dflt) end),
        post = ER.asyncFun(function(cb,url,options,data,dflt) options=options or {}; options.method="POST" return httpCall(cb,url,options,data,dflt) end),
        delete = ER.asyncFun(function(cb,url,options,dflt) options=options or {}; options.method="DELETE" return httpCall(cb,url,options,dflt) end),
    }
    defVars.http = http
    
    local function hc3api(cb,method,api,data)
        local creds = defVars._creds and defVars._creds[1]
        if not creds then setTimeout(function() cb(nil,404) end,0) end
        net.HTTPClient():request("http://localhost/api"..api,{
            options = {
                method = method or "GET",
                headers = {
                    ['Accept'] = 'application/json',
                    ["Authorization"] = creds,
                    ['X-Fibaro-Version'] = '2',
                   -- ["Content-Type"] = "application/json",
                },
                data = data and json.encode(data) or nil
            },
            success = function(resp)
                cb(json.decode(resp.data),200)
            end,
            error = function(err)
                cb(nil,err)
            end
        })
    end

    local api2 = {
        get = ER.asyncFun(function(cb,path) return hc3api(cb,"GET",path,nil) end),
        put = ER.asyncFun(function(cb,path,data) return hc3api(cb,"PUT",path,data) end),
        post = ER.asyncFun(function(cb,path,data) return hc3api(cb,"POST",path,data) end),
        delete = ER.asyncFun(function(cb,path) return hc3api(cb,"DELETE",path,nil) end),
    }
    defVars.hc3api = api2
    defVars._hc3api = hc3api

    ------------------ NoreRed support ---------------------------
    local NR_trans = {}
    function quickApp:fromNodeRed(ev)
        ev = type(ev)=='string' and json.decode(ev) or ev
        local tag = ev._transID
        ev._IP,ev._async,ev._from,ev._transID=nil,nil,nil,nil
        local f = NR_trans[tag]
        if f then
            NR_trans[tag] = nil
            f(ev,200)
        else fibaro.post(ev) end
    end

    --local noderedURL = "http://192.168.1.128:1880/ER_HC3"
    local function nodePost(event,cb)
        event._from = quickApp.id
        event._IP = fibaro.getIPaddress()
        local noderedURL = defVars.noderedURL and defVars.noderedURL[1]
        assert(noderedURL,"noderedURL not defined")
        local params =  {
            options = {
                headers = {['Accept']='application/json',['Content-Type']='application/json'},
                data = json.encode(event), timeout=4000, method = 'POST'
            },
            success = function(res)
                _,res.data = pcall(json.decode,res.data)
                cb(res.status,res.data) 
            end,
            error = function(err) cb(err) end
        }
        net.HTTPClient():request(noderedURL,params)
    end

   local function nodered(cb,event,dflt)
        event = table.copy(event)
        event._async = false
        nodePost(event,function(status,data)
            if status==200 then
                cb(data,200)
            else
                cb(dflt,status)
            end
        end)
        return 10*1000,"NodeRed"-- Timeout
    end

    local NRID = 1
    local function nodered_as(cb,event,dflt)
        event = table.copy(event)
        event._async = true
        event._transID = NRID; NRID=NRID+1
        NR_trans[event._transID] = cb
        nodePost(event,function(status,data)
            if status==200 then
            else
                fibaro.warningf(__TAG,"Nodered %s",status)
                NR_trans[event._transID] = nil
                cb(dflt,status)
            end
        end)
        return 10*1000,"NodeRed" -- Timeout
    end
    defVars.nr = { post = ER.asyncFun(nodered), post_as = ER.asyncFun(nodered_as) }
    --------------------- end NR -----------------------

    -- Interactive push notifications
    local interactivePushTable = {}
    function quickApp:INTERACTIVE_OK_BUTTON(tag,...)
       if type(tag) ~= 'string' then return end
       local cb = interactivePushTable[tag]
       interactivePushTable[tag] = nil
       if cb then
          clearTimeout(cb[2])
          cb[1](true) 
       end
    end

    local function pushYesNo(mobileId,title,message,tag)
      api.post("/mobile/push",{
      category = "YES_NO", 
      title = title, 
      message = message, 
      service = "Device", 
      data = {
        actionName = "INTERACTIVE_OK_BUTTON", 
        deviceId = quickApp.id,  
        args = {tag}
      }, 
      action = "RunAction",  
        mobileDevices = { mobileId }, 
      })
    end

    defVars.ask = ER.asyncFun(function(cb,mobileId,title,message,timeout)
      assert(tonumber(mobileId),"ask: mobileId must be a number")
      assert(type(title)=='string',"ask: title must be a string")
      assert(type(message)=='string',"ask: message must be a string")
      timeout = timeout and timeout*1000 or 60*1000
      local tag,ref = "x"..math.random(10000000)..os.time(),nil
      pushYesNo(mobileId,title,message,tag)
      ref = setTimeout(function()
         local cb = interactivePushTable[tag]
         interactivePushTable[tag]=nil
         local stat,res = pcall(function()
             if cb then cb[1](false) end 
             return true
         end)
         if not stat then print("err",res) end
       end
      ,timeout)
      interactivePushTable[tag]={cb,ref}
      return timeout
    end)
    
    --------------------- end interactive push -----------------------

    local function getFibObj(path,p,k,v)
        local oo = api.get(path) or {}
        if p then oo = oo[p] end
        for _,o in ipairs(oo or {}) do
            if o[k]==v then return o end
        end
    end

    local function enable(r,mode)
        if ER.isRule(r) then return r[mode]()
        elseif tonumber(r) and ER.rules[tonumber(r)] then
            return ER.rules[tonumber(r)][mode]()
        elseif type(r) == 'table' then
            for _,r0 in ipairs(r) do enable(r0,mode) end
        elseif type(r) == 'string' then
            for id,r0 in ipairs(ER.rules) do
                if r0._rtag == r then r0[mode]() end
            end
        else
            error(mode..": not a rule")
        end
    end
    
    function ER.enable(r) return enable(r,'enable') end
    function ER.disable(r) return enable(r,'disable') end

    defVars.LOC = function(name) return getFibObj("/panels/location",nil,"name",name) end
    defVars.USER = function(name) return getFibObj("/users",nil,"name",name) end
    defVars.PHONE = function(name) return getFibObj("/iosDevices",nil,"name",name) end
    defVars.PART = function(name) return getFibObj("/alarms/v1/partitions",nil,"name",name) end
    defVars.PROF = function(name) return getFibObj("/profiles","profiles","name",name) end
    defVars.CLIM = function(name) return getFibObj("/panels/climate",nil,"name",name) end
    defVars.SPRINK = function(name) return getFibObj("/panels/sprinklers",nil,"name",name) end

    local function makeDateFun(str,cache)
        if cache[str] then return cache[str] end
        local f = fibaro.dateTest(str)
        cache[str] = f
        return f
      end
  
    local cache = { date={}, day = {}, month={}, wday={} }
    defVars.date = function(s) return (cache.date[s] or makeDateFun(s,cache.date))() end               -- min,hour,days,month,wday
    defVars.day = function(s) return (cache.day[s] or makeDateFun("* * "..s,cache.day))() end          -- day('1-31'), day('1,3,5')
    defVars.month = function(s) return (cache.month[s] or makeDateFun("* * * "..s,cache.month))() end  -- month('jan-feb'), month('jan,mar,jun')
    defVars.wday = function(s) return (cache.wday[s] or makeDateFun("* * * * "..s,cache.wday))() end   -- wday('fri-sat'), wday('mon,tue,wed')

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
    defVars.printc = function(...) quickApp:printTagAndColor(...) end
    defVars.QA = quickApp

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

  definePropClass('GlobalV')
  function GlobalV:__init(name) PropObject.__init(self) self.name = name end
  function GlobalV:__tostring() return fmt("GV(%s)",self.name) end
  function GlobalV.getProp.name(id,prop,event) return id.name end
  function GlobalV.getProp.value(id,prop,event) return marshallFrom(fibaro.getGlobalVariable(id.name)) end
  function GlobalV.getProp.delete(id,prop,event) return fibaro.getGlobalVariable(id.name) end
  function GlobalV.setProp.value(id,prop,val) fibaro.setGlobalVariable(id.name,marshallTo(val)) return val end
  function GlobalV.trigger.value(id,prop) return {type='globalVariable', name=id.name} end
  defVars.GV = function(n) return GlobalV(n) end

  definePropClass('QuickAppV')
  function QuickAppV:__init(name) PropObject.__init(self) self.name = name end
  function QuickAppV:__tostring() return fmt("QV(%s)",self.name) end
  function QuickAppV.getProp.name(id,prop,event) return id.name end
  function QuickAppV.getProp.value(id,prop,event) return quickApp:getVariable(id.name) end
  function QuickAppV.getProp.delete(id,prop,event) return quickApp:setVariable(id.name,nil) end
  function QuickAppV.setProp.value(id,prop,val) quickApp:setVariable(id.name,val) return val end
  function QuickAppV.trigger.value(id,prop) return {type='quickVar', name=id.name} end
  defVars.QV = function(n) return QuickAppV(n) end

  ----------- Child support ----------------
  local ERchildren = {}
  local function initChildren()
    quickApp:initChildren(ERchildren)
    for uid,c in pairs(quickApp.children) do 
    defVars[uid]=c.id
      defVars[uid.."_D"]=c
      defVars[uid.."_ID"]=c.id
      local d = api.get("/devices/"..c.id)
      for name,_ in pairs(d.actions) do
        c[name] = function(self,...) fibaro.post({type='UI',action=name,id=c.id,args={}}) end
      end
    end
  end
  local function child(uid,name,typ)
    ERchildren[uid] = {name=name,type=typ,className='QwikAppChild'}
  end
  defVars.child=child
  defVars.initChildren=initChildren
end