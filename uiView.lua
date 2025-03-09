

local UI = {
    {
        {button="B1", text="Btn 1", onReleased='A'},
        {button="B2", text="Btn 2", onReleased='B'}
    }
}

local function uiType(c) 
   return c.button and 'button' 
          or c.label and 'label'
          or c.slider and 'slider'
          or c.select and 'select'
          or "unknown"
end

local function dflt(v,d)
  if v~=nil then return v else return d end
end

local function createEventbindings(c,id,actions,opts,...)
    local binds,act = {},nil
    for _,a in ipairs(actions) do
        if not opts.child then
            act = {
                params = {
                    actionName = 'UIAction',
                    args = {
                        a,
                        id,
                        ...
                    }
                },
                type = 'deviceAction'
            }
        else
            act = {
                params = {
                    actionName = c[a] or c['onReleased'],
                    args = {},
                },
                type = 'deviceAction'
            }
        end --if
        binds[a] = { act }
   end -- loop
   return binds
end

local decoder = {}
function decoder.button(c,opt)
   return {
        eventBinding = createEventbindings(c,c.button,
            {"onReleased","onLongPressReleased","onLongPressDown"},
        opts),
        name = c.button,
        style = { weight = c.weight or opt.weight },
        text = c.text,
        type = 'button',
        visible = dflt(c.visible,opt.visible)
   }
end
function decoder.label(c)
   return {
        name = c.label,
        style = { weight = c.weight or opt.weight },
        text = c.text,
        type = 'label',
        visible = dflt(c.visible,opt.visible)
   }
end
function decoder.slider(c,opts)
   return {
        eventBinding = createEventbindings(c,c.slider,
            {"onChanged"},
        opts,"$event.value"),
        name = c.slider,
        style = { weight = c.weight or opt.weight },
        min = c.min or opts.min,
        max = c.max or opts.max,
        step = c.step or opts.step,
        text = c.text or opts.text,
        type = 'slider',
        visible = dflt(c.visible,opt.visible)
   }
end
function decoder.switch(c,opt)
   return {
        eventBinding = createEventbindings(c,c.switch,
            {"onReleased","onLongPressReleased","onLongPressDown"},
        opts,"$event.value"),
        name = c.switch,
        style = { weight = c.weight or opt.weight },
        text = c.text,
        type = 'switch',
        value = dflt(c.value,opts.value),
        visible = dflt(c.visible,opt.visible)
   }
end
function decoder.select(c,opts)
   return {
        eventBinding = createEventbindings(c,c.select,
            {"onToggled"},
        opts,"$event.value"),
        name = c.select,
        style = { weight = c.weight or opts.weight },
        options = dflt(c.options,opts.options),
        selectionType = c.selectionType or opts.selectionType,
        values = dflt(c.values,opts.values),
        text = c.text or opts.text,
        type = 'select',
        visible = dflt(c.visible,opts.visible)
   }
end
function decoder.unknown(c,opts)
   error("Unknown ui type ",json.encode(c))
end

local defaultWeight = {
    1.0,
    0.50,
    0.33,
    0.25,
    0.20,
}
local function decodeComponents(row,cfg)
    cmps = {}
    opts = {
        child = cfg.child == true,
        weight = defaultWeight[#row] or 1.0,
        min = 0,   --slider
        max = 100, --slider
        step = 1,  --slider
        text = "",
        value = false, -- switch
        selectionType = 'single', --select
        options = {}, -- select
        values = {},  -- select
        visible = true
    }
    for _,c in ipairs(row) do cmps[#cmps+1] = decoder[uiType(c)](c,opts) end
    return cmps
end

local function decodeUI(ui,cfg)
    cfg = cfg or { child = true }
    local components = {}
    for _,row in ipairs(ui) do
       components[#components+1] = {
          components = decodeComponents(row,cfg),
          style = { weight = 1.0 },
          type = 'horizontal'
       }
    end
    return components
end

print(json.encode(decodeUI(UI)))