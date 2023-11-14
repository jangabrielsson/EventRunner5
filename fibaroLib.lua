------------- Debug ---------------------

function fibaro.debugf(tag,fmt,...) fibaro.debug(tag,string.format(fmt,...)) end
function fibaro.tracef(tag,fmt,...) fibaro.trace(tag,string.format(fmt,...)) end
function fibaro.warningf(tag,fmt,...) fibaro.warning(tag,string.format(fmt,...)) end
function fibaro.errorf(tag,fmt,...) fibaro.error(tag,string.format(fmt,...)) end

------------- Scenes ---------------------
function fibaro.isSceneEnabled(sceneID) 
  __assert_type(sceneID,"number" )
  return (api.get("/scenes/"..sceneID) or { enabled=false }).enabled 
end

function fibaro.setSceneEnabled(sceneID,enabled) 
  __assert_type(sceneID,"number" )   __assert_type(enabled,"boolean" )
  return api.put("/scenes/"..sceneID,{enabled=enabled}) 
end

function fibaro.getSceneRunConfig(sceneID)
  __assert_type(sceneID,"number" )
  return api.get("/scenes/"..sceneID).mode 
end

function fibaro.setSceneRunConfig(sceneID,runConfig)
  __assert_type(sceneID,"number" )
  assert(({automatic=true,manual=true})[runConfig],"runconfig must be 'automatic' or 'manual'")
  return api.put("/scenes/"..sceneID, {mode = runConfig}) 
end

function fibaro.getSceneByName(name)
  __assert_type(name,"string" )
  for _,s in ipairs(api.get("/scenes")) do
    if s.name==name then return s end
  end
end

------------- Global Variables ---------------------
function fibaro.getAllGlobalVariables() 
  return table.map(function(v) return v.name end,api.get("/globalVariables")) 
end

function fibaro.createGlobalVariable(name,value,options)
  __assert_type(name,"string")
  if not fibaro.existGlobalVariable(name) then 
    value = tostring(value)
    local args = table.copy(options or {})
    args.name,args.value=name,value
    return api.post("/globalVariables",args)
  end
end

function fibaro.deleteGlobalVariable(name) 
  __assert_type(name,"string")
  return api.delete("/globalVariables/"..name) 
end

function fibaro.existGlobalVariable(name)
  __assert_type(name,"string")
  return api.get("/globalVariables/"..name) and true 
end

function fibaro.getGlobalVariableType(name)
  __assert_type(name,"string")
  local v = api.get("/globalVariables/"..name) or {}
  return v.isEnum,v.readOnly
end

function fibaro.getGlobalVariableLastModified(name)
  __assert_type(name,"string")
  return (api.get("/globalVariables/"..name) or {}).modified 
end

------------ Custome Events ----------------------
function fibaro.getAllCustomEvents() 
  return table.map(function(v) return v.name end,api.get("/customEvents") or {}) 
end

function fibaro.createCustomEvent(name,userDescription) 
  __assert_type(name,"string" )
  return api.post("/customEvents",{name=name,userDescription=userDescription or ""})
end

function fibaro.deleteCustomEvent(name) 
  __assert_type(name,"string" )
  return api.delete("/customEvents/"..name) 
end

function fibaro.existCustomEvent(name) 
  __assert_type(name,"string" )
  return api.get("/customEvents/"..name) and true 
end

----------- Profiles -------------------------------
function fibaro.activeProfile(id)
  if id then
    if type(id)=='string' then id = fibaro.profileNameToId(id) end
    assert(id,"fibaro.activeProfile(id) - no such id/name")
    return api.put("/profiles",{activeProfile=id}) and id
  end
  return api.get("/profiles").activeProfile 
end

function fibaro.profileIdtoName(pid)
  __assert_type(pid,"number")
  for _,p in ipairs(api.get("/profiles").profiles or {}) do 
    if p.id == pid then return p.name end 
  end 
end

function fibaro.profileNameToId(name)
  __assert_type(name,"string")
  for _,p in ipairs(api.get("/profiles").profiles or {}) do 
    if p.name == name then return p.id end 
  end 
end

---------------- Partitions -----------------------
function fibaro.partitionIdToName(pid)
  __assert_type(pid,"number")
  return (api.get("/alarms/v1/partitions/"..pid) or {}).name 
end

function fibaro.partitionNameToId(name)
  assert(type(name)=='string',"Alarm partition name not a string")
  for _,p in ipairs(api.get("/alarms/v1/partitions") or {}) do
    if p.name == name then return p.id end
  end
end

-- Returns devices breached in partition 'pid'
function fibaro.getBreachedDevicesInPartition(pid)
  assert(type(pid)=='number',"Alarm partition id not a number")
  local p,res = api.get("/alarms/v1/partitions/"..pid),{}
  for _,d in ipairs((p or {}).devices or {}) do
    if fibaro.getValue(d,"value") then res[#res+1]=d end
  end
  return res
end

-- helper function
local function filterPartitions(filter)
  local res = {}
  for _,p in ipairs(api.get("/alarms/v1/partitions") or {}) do if filter(p) then res[#res+1]=p.id end end
  return res
end

-- Return all partitions ids
function fibaro.getAllPartitions() return filterPartitions(function() return true end) end

-- Return partitions that are armed
function fibaro.getArmedPartitions() return filterPartitions(function(p) return p.armed end) end

-- Return partitions that are about to be armed
function fibaro.getActivatedPartitions() return filterPartitions(function(p) return p.secondsToArm end) end

-- Return breached partitions
function fibaro.getBreachedPartitions() return api.get("/alarms/v1/partitions/breached") or {} end

--If you want to list all devices that can be part of a alarm partition/zone you can do
function fibaro.getAlarmDevices() return api.get("/alarms/v1/devices/") end

function fibaro.armPartition(id)
  if id == 0 then
    return api.post("/alarms/v1/partitions/actions/arm")
  else
    return api.post("/alarms/v1/partitions/"..id.."/actions/arm")
  end
end

function fibaro.unarmPartition(id)
  if id == 0 then
    return api.delete("/alarms/v1/partitions/actions/arm")
  else
    return api.delete("/alarms/v1/partitions/"..id.."/actions/arm")
  end
end

function fibaro.tryArmPartition(id)
  local res,code
  if id == 0 then
    res,code = api.post("/alarms/v1/partitions/actions/tryArm")
    if type(res) == 'table' then
      local r = {}
      for _,p in ipairs(res) do r[p.id]=p.breachedDevices end
      if next(r) then return r,200 else return nil end
    else
      return nil
    end
  else
    local res,_ = api.post("/alarms/v1/partitions/"..id.."/actions/tryArm")
    if res.result=="armDelayed" and #res.breachedDevices > 0 then return {[id]=res.breachedDevices},200 else return nil end
  end
end

-------------------- Weather -------------------------------
fibaro.weather = {}
function fibaro.weather.temperature() return api.get("/weather").Temperature end
function fibaro.weather.temperatureUnit() return api.get("/weather").TemperatureUnit end
function fibaro.weather.humidity() return api.get("/weather").Humidity end
function fibaro.weather.wind() return api.get("/weather").Wind end
function fibaro.weather.weatherCondition() return api.get("/weather").WeatherCondition end
function fibaro.weather.conditionCode() return api.get("/weather").ConditionCode end

---------------- Climate panel ---------------------------
--Returns mode - "Manual", "Vacation", "Schedule"
function fibaro.getClimateMode(id)
  return (api.get("/panels/climate/"..id) or {}).mode
end

--Returns the currents mode "mode", or sets it - "Auto", "Off", "Cool", "Heat"
function fibaro.climateModeMode(id,mode)
  if mode==nil then return api.get("/panels/climate/"..id).properties.mode end
  assert(({Auto=true,Off=true,Cool=true,Heat=true})[mode],"Bad climate mode")
  return api.put("/panels/climate/"..id,{properties={mode=mode}})
end

-- Set zone to scheduled mode
function fibaro.setClimateZoneToScheduleMode(id)
  __assert_type(id, "number")
  return api.put('/panels/climate/'..id, {properties = {
    handTimestamp     = 0,
    vacationStartTime = 0,
    vacationEndTime   = 0
  }})
end

-- Set zone to manual, incl. mode, time ( secs ), heat and cool temp
function  fibaro.setClimateZoneToManualMode(id, mode, time, heatTemp, coolTemp)
  __assert_type(id, "number") __assert_type(mode, "string")
  assert(({Auto=true,Off=true,Cool=true,Heat=true})[mode],"Bad climate mode")
  return api.put('/panels/climate/'..id, { properties = { 
    handMode            = mode, 
    vacationStartTime   = 0, 
    vacationEndTime     = 0,
    handTimestamp       = tonumber(time) and os.time()+time or math.tointeger(2^32-1),
    handSetPointHeating = tonumber(heatTemp) and heatTemp or nil,
    handSetPointCooling = tonumber(coolTemp) and coolTemp or nil
  }})
end

-- Set zone to vacation, incl. mode, start (secs from now), stop (secs from now), heat and cool temp
function fibaro.setClimateZoneToVacationMode(id, mode, start, stop, heatTemp, coolTemp)
  __assert_type(id,"number") __assert_type(mode,"string") __assert_type(start,"number") __assert_type(stop,"number")
  assert(({Auto=true,Off=true,Cool=true,Heat=true})[mode],"Bad climate mode")
  local now = os.time()
  return api.put('/panels/climate/'..id, { properties = {
    vacationMode            = mode,
    handTimestamp           = 0, 
    vacationStartTime       = now+start, 
    vacationEndTime         = now+stop,
    vacationSetPointHeating = tonumber(heatTemp) and heatTemp or nil,
    vacationSetPointCooling = tonumber(coolTemp) and coolTemp or nil
  }})
end

--------------------------- QuickApps ----------------------------
function fibaro.restartQA(id)
  __assert_type(id,"number")
  return api.post("/plugins/restart",{deviceId=id or plugin.mainDeviceId})
end

function fibaro.getQAVariable(id,name)
  __assert_type(id,"number")
  __assert_type(name,"string")
  local props = (api.get("/devices/"..(id or plugin.mainDeviceId)) or {}).properties or {}
  for _, v in ipairs(props.quickAppVariables or {}) do
    if v.name==name then return v.value end
  end
end

function fibaro.setQAVariable(id,name,value)
  __assert_type(id,"number")
  __assert_type(name,"string")
  return fibaro.call(id,"setVariable",name,value)
end

function fibaro.getAllQAVariables(id)
  __assert_type(id,"number")
  local props = (api.get("/devices/"..(id or plugin.mainDeviceId)) or {}).properties or {}
  local res = {}
  for _, v in ipairs(props.quickAppVariables or {}) do
    res[v.name]=v.value
  end
  return res
end

function fibaro.isQAEnabled(id)
  __assert_type(id,"number")
  local dev = api.get("/devices/"..(id or plugin.mainDeviceId))
  return (dev or {}).enabled
end

function fibaro.setQAValue(device, property, value)
  fibaro.call(device, "updateProperty", property, (json.encode(value)))
end

function fibaro.enableQA(id,enable)
  __assert_type(id,"number")
  __assert_type(enable,"boolean")
  return api.post("/devices/"..(id or plugin.mainDeviceId),{enabled=enable==true})
end

function fibaro.deleteFile(deviceId,file)
  local name = type(file)=='table' and file.name or file
  return api.delete("/quickApp/"..(deviceId or plugin.mainDeviceId).."/files/"..name)
end

function fibaro.updateFile(deviceId,file,content)
  if type(file)=='string' then
    file = {isMain=false,type='lua',isOpen=false,name=file,content=""}
  end
  file.content = type(content)=='string' and content or file.content
  return api.put("/quickApp/"..(deviceId or plugin.mainDeviceId).."/files/"..file.name,file) 
end

function fibaro.updateFiles(deviceId,list)
  if #list == 0 then return true end
  return api.put("/quickApp/"..(deviceId or plugin.mainDeviceId).."/files",list) 
end

function fibaro.createFile(deviceId,file,content)
  if type(file)=='string' then
    file = {isMain=false,type='lua',isOpen=false,name=file,content=""}
  end
  file.content = type(content)=='string' and content or file.content
  return api.post("/quickApp/"..(deviceId or plugin.mainDeviceId).."/files",file) 
end

function fibaro.getFile(deviceId,file)
  local name = type(file)=='table' and file.name or file
  return api.get("/quickApp/"..(deviceId or plugin.mainDeviceId).."/files/"..name) 
end

function fibaro.getFiles(deviceId)
  local res,code = api.get("/quickApp/"..(deviceId or plugin.mainDeviceId).."/files")
  return res or {},code
end

function fibaro.copyFileFromTo(fileName,deviceFrom,deviceTo)
  deviceTo = deviceTo or plugin.mainDeviceId
  local copyFile = fibaro.getFile(deviceFrom,fileName)
  assert(copyFile,"File doesn't exists")
  fibaro.addFileTo(copyFile.content,fileName,deviceTo)
end

function fibaro.addFileTo(fileContent,fileName,deviceId)
  deviceId = deviceId or plugin.mainDeviceId
  local file = fibaro.getFile(deviceId,fileName)
  if not file then -- Create new file
    local _,res = fibaro.createFile(deviceId,{   
      name=fileName,
      type="lua",
      isMain=false,
      isOpen=false,
      content=fileContent
    })
    if res == 200 then
      fibaro.debug(nil,"File '",fileName,"' added")
    else quickApp:error("Error:",res) end
  elseif file.content ~= fileContent then  -- Update existing file
    local _,res = fibaro.updateFile(deviceId,{  
      name=file.name,
      type="lua",
      isMain=file.isMain,
      isOpen=file.isOpen,
      content=fileContent
    })
    if res == 200 then
      fibaro.debug(nil,"File '",fileName,"' updated")
    else fibaro.error(nil,"Error:",res) end
  else
    fibaro.debug(nil,"File '",fileName,"' not changed")
  end
end

function fibaro.getFQA(deviceId) return api.get("/quickApp/export/"..deviceId) end

function fibaro.putFQA(content) -- Should be .fqa json
  if type(content)=='table' then content = json.encode(content) end
  return api.post("/quickApp/",content)
end