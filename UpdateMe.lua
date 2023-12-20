--%%file=fibaroExtra.lua,extra;

local __version = "0.1"
local __author = "Jan Gabrielsson"
local TIMETOREVERT = 60 -- seconds waiting for allOk before reverting

--[[
  id = <deviceId>,
  addUpdate = { urlList> }
  url = <github url to file>
  Ex. "https://raw.githubusercontent.com/jangabrielsson/TQAE/ER4_0.998/jgabs_QAs/EventRunner/EventRunner4.lua"
  file = <filename>
--]]

local QAs = {}

local function update(id,url,fname)
  local qa = QAs[id] or {}
  local updateFile

  -- Save old content
  local fc = fibaro.getFile(id,fname)
  if not fc then quickApp:error("Failed to get file "..fname.." for QA with id "..id) end
  qa.file = {name=fname,content=fc.content}

  -- Get gitHub file(s)
  local request = {
    success=function(resp)
      if resp.status > 204 then errorf("%s, trying to fetch %s",resp.data,url)
      else 
        updateFile(resp.data)
      end
    end,
    error=function(err)
      errorf("%s, trying to fetch %s",err,url)
    end,
  }

  -- Update file  
  local function updateFile(content)
    if content == qa.file.content then
      quickApp:debug("No change in file "..fname.." for QA with id "..id)
      return
    end
    local _,code = fibaro.updateFile(id,fname,content)
  end

  net.HTTPClient():request(url,request)
end

local function revertUpdate(idi)
  local id = tonumber(idi)
  if not id then quickApp:error("Invalid id "..tostring(idi)) return end
  local qa = QAs[id] or {}
  if qa.updating then
    quickApp:debug("No answer from QA with id "..id)
    quickApp:debug("Reverting update for QA with id "..id)
    qa.updating = nil
    qa.timer = nil
    local fname = qa.file.name
    local content = qa.file.content
    local res,code = fibaro.updateFile(id,fname,content)
    if code > 206 then quickApp:error("Failed to revert file "..fname.." for QA with id "..id) end
  end
end

function QuickApp:updateMe(args)
  args = json.decode(args)
  assert(args.id,"Missing id")
  assert(args.url,"Missing url")
  assert(args.file,"Missing file")
  local id = args.id
  local qa = QAs[id] or {}
  QAs[id] = qa
  if qa.updating then
    quickApp:debug("QA with id "..tostring(id).." already updating")
    return
  end
  qa.updating = true
  QAs[args.id].timer = setTimeout(function() revertUpdate(id) end,TIMETOREVERT*1000)
end

function QuickApp:allOk(id)
  if not QAs[id] then fibaro:debug("No QA with id "..tostring(id)) end
  if not QAs[id].updating then fibaro:debug("QA with id "..tostring(id).." not updating") end
  if QAs[id].timer then
    fibaro:debug("Clearing timer")
    clearTimeout(QAs[id].timer)
    QAs[id].updating = nil
    QAs[id].timer = nil
  end
end

function QuickApp:onInit()
  self:debugf("UpdateMe v:%s",__version)
end