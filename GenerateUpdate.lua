--%%file=fibaroExtra.lua,extra;

local entry = [[
  {
  "896846032517892":{
   "name":"EventRunner5",   
   "type":"com.fibaro.deviceController",
   "versions":[
  {
  "version":%%VERSION%%,     
  "vars":{
   "base1":"https://raw.githubusercontent.com/jangabrielsson/EventRunner5/ER5_%%VERSION%%",
  },     
  "descr":"First release",     
  "files":{    
   "ERlib":"$base1/ERlib.lua",
   "fibLib":"$base1/fibaroLib.lua", 
   "parser":"$base1/Parser.lua",
   "tokenizer":"$base1/Tokenizer.lua",
   "compiler":"$base1/Compiler.lua",
   "vm":"$base1/VM.lua",
   "rule":"$base1/Rule.lua",
   "builtins":"$base1/Builtins.lua",
   "utils":"$base1/Utils.lua",
   "engine":"$base1/Engine.lua",   
   "main":"$base1/EventRunner5.lua"      
  },     
  "keep":[
   "main"      
  ],     
  "quickAppVariables":[],     
  "viewLayout": {
    "$jason": {
      "body": {
        "header": {
          "style": {
            "height": "0"
          },
          "title": "quickApp_device_1425"
        },
        "sections": {
          "items": [
            {
              "components": [
                {
                  "name": "title",
                  "style": {
                    "weight": "1.2"
                  },
                  "text": "EventRunner5",
                  "type": "label"
                },
                {
                  "style": {
                    "weight": "0.5"
                  },
                  "type": "space"
                }
              ],
              "style": {
                "weight": "1.2"
              },
              "type": "vertical"
            },
            {
              "components": [
                {
                  "components": [
                    {
                      "name": "listRules",
                      "style": {
                        "weight": "0.50"
                      },
                      "text": "List rules",
                      "type": "button"
                    },
                    {
                      "name": "listRulesExt",
                      "style": {
                        "weight": "0.50"
                      },
                      "text": "List rules ext.",
                      "type": "button"
                    }
                  ],
                  "style": {
                    "weight": "1.2"
                  },
                  "type": "horizontal"
                },
                {
                  "style": {
                    "weight": "0.5"
                  },
                  "type": "space"
                }
              ],
              "style": {
                "weight": "1.2"
              },
              "type": "vertical"
            },
            {
              "components": [
                {
                  "components": [
                    {
                      "name": "listTimers",
                      "style": {
                        "weight": "0.50"
                      },
                      "text": "List timers",
                      "type": "button"
                    },
                    {
                      "name": "listVars",
                      "style": {
                        "weight": "0.50"
                      },
                      "text": "List variables",
                      "type": "button"
                    }
                  ],
                  "style": {
                    "weight": "1.2"
                  },
                  "type": "horizontal"
                },
                {
                  "style": {
                    "weight": "0.5"
                  },
                  "type": "space"
                }
              ],
              "style": {
                "weight": "1.2"
              },
              "type": "vertical"
            },
            {
              "components": [
                {
                  "components": [
                    {
                      "name": "listRuleStats",
                      "style": {
                        "weight": "0.50"
                      },
                      "text": "List stats",
                      "type": "button"
                    },
                    {
                      "name": "Restart",
                      "style": {
                        "weight": "0.50"
                      },
                      "text": "Restart",
                      "type": "button"
                    }
                  ],
                  "style": {
                    "weight": "1.2"
                  },
                  "type": "horizontal"
                },
                {
                  "style": {
                    "weight": "0.5"
                  },
                  "type": "space"
                }
              ],
              "style": {
                "weight": "1.2"
              },
              "type": "vertical"
            },
            {
              "components": [
                {
                  "name": "stats",
                  "style": {
                    "weight": "1.2"
                  },
                  "text": "",
                  "type": "label"
                },
                {
                  "style": {
                    "weight": "0.5"
                  },
                  "type": "space"
                }
              ],
              "style": {
                "weight": "1.2"
              },
              "type": "vertical"
            }
          ]
        }
      },
      "head": {
        "title": "quickApp_device_1425"
      }
    }
  },
  "uiCallbacks": [
    {
      "callback": "listRules",
      "eventType": "onReleased",
      "name": "listRules"
    },
    {
      "callback": "listRulesExt",
      "eventType": "onReleased",
      "name": "listRulesExt"
    },
    {
      "callback": "listTimers",
      "eventType": "onReleased",
      "name": "listTimers"
    },
    {
      "callback": "listVariables",
      "eventType": "onReleased",
      "name": "listVars"
    },
    {
      "callback": "listRuleStats",
      "eventType": "onReleased",
      "name": "listRuleStats"
    },
    {
      "callback": "restart",
      "eventType": "onReleased",
      "name": "Restart"
    }
  ],
    "interfaces":[
   "quickApp"      
  ],     
  "mainfile":"$base1/EventRunner5.lua"     
 }
  ]
 }}
]]

function QuickApp:onInit()
  local f = io.open("Engine.lua","r")
  local conf = f:read("*a")
  local version = conf:match("version%s*=%s*(%d+%.%d+)")
  version = tonumber(version)
  local config = entry:gsub("%%%%VERSION%%%%",version)
  print("Version:",version)
  config = json.decode(config)
  local conf
  local f = io.open("Update.json","r")
  if f then 
    conf = f:read("*a")
    local stat,res = pcall(json.decode,conf)
    if stat then 
      conf = res
      local _,versions = next(conf)
      versions = versions.versions
      for _,v in ipairs(versions) do
        if v.version == version then
          print("Version already exists - exit")
          return
        end
      end
      if #versions > 2 then table.remove(versions,1) end
      local _,templateVersions = next(config)
      templateVersions = templateVersions.versions
      versions[#versions+1] = templateVersions[1]
    else
      print("Bad Update.json - overwriting")
      conf = config
    end
  else
    conf = config
  end
  f = io.open("Update.json","w")
  f:write((json.encodeFormated(conf)))
  f:close()
  print("Done")
end
