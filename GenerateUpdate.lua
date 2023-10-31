--%%file=../fibemu/examples/fibaroExtra.lua,extra;

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
  "descr":"First version (alpha, not for production)",     
  "files":{    
   "fibaroExtra":"$base1/fibaroExtra.lua",   
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
        "sections": {
          "items": [
            {
              "type": "vertical",
              "components": [
                {
                  "type": "label",
                  "text": "EventRunner5",
                  "style": {
                    "weight": "1.2"
                  },
                  "name": "title"
                },
                {
                  "type": "space",
                  "style": {
                    "weight": "0.5"
                  }
                }
              ],
              "style": {
                "weight": "1.2"
              }
            },
            {
              "type": "vertical",
              "components": [
                {
                  "type": "horizontal",
                  "components": [
                    {
                      "type": "button",
                      "text": "List rules",
                      "style": {
                        "weight": "0.50"
                      },
                      "name": "listRules"
                    },
                    {
                      "type": "button",
                      "text": "List rules ext.",
                      "style": {
                        "weight": "0.50"
                      },
                      "name": "listRulesExt"
                    }
                  ],
                  "style": {
                    "weight": "1.2"
                  }
                },
                {
                  "type": "space",
                  "style": {
                    "weight": "0.5"
                  }
                }
              ],
              "style": {
                "weight": "1.2"
              }
            },
            {
              "type": "vertical",
              "components": [
                {
                  "type": "horizontal",
                  "components": [
                    {
                      "type": "button",
                      "text": "List timers",
                      "style": {
                        "weight": "0.50"
                      },
                      "name": "listTimers"
                    },
                    {
                      "type": "button",
                      "text": "List variables",
                      "style": {
                        "weight": "0.50"
                      },
                      "name": "listVars"
                    }
                  ],
                  "style": {
                    "weight": "1.2"
                  }
                },
                {
                  "type": "space",
                  "style": {
                    "weight": "0.5"
                  }
                }
              ],
              "style": {
                "weight": "1.2"
              }
            },
            {
              "type": "vertical",
              "components": [
                {
                  "type": "horizontal",
                  "components": [
                    {
                      "type": "button",
                      "text": "Test1",
                      "style": {
                        "weight": "0.50"
                      },
                      "name": "test1"
                    },
                    {
                      "type": "button",
                      "text": "Test2",
                      "style": {
                        "weight": "0.50"
                      },
                      "name": "test2"
                    }
                  ],
                  "style": {
                    "weight": "1.2"
                  }
                },
                {
                  "type": "space",
                  "style": {
                    "weight": "0.5"
                  }
                }
              ],
              "style": {
                "weight": "1.2"
              }
            }
          ]
        },
        "header": {
          "title": "quickApp_device_5000",
          "style": {
            "height": "200"
          }
        }
      },
      "head": {
        "title": "quickApp_device_5000"
      }
    }
  },
  "uiCallbacks": [
      {
        "callback": "listRules",
        "name": "listRules",
        "eventType": "onReleased"
      },
      {
        "callback": "listRulesExt",
        "name": "listRulesExt",
        "eventType": "onReleased"
      },
      {
        "callback": "listTimers",
        "name": "listTimers",
        "eventType": "onReleased"
      },
      {
        "callback": "listVariables",
        "name": "listVars",
        "eventType": "onReleased"
      },
      {
        "callback": "test1",
        "name": "test1",
        "eventType": "onReleased"
      },
      {
        "callback": "test2",
        "name": "test2",
        "eventType": "onReleased"
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
