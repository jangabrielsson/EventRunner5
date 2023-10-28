fibaro.__ER  = fibaro.__ER or { modules={} }

function fibaro.__ER.modules.tokenizer(ER)
  local toTime = fibaro.toTime
  
  
  local fmt = string.format
  local patterns = {}
  
  local function toTimeDate(str)
    local y,m,d,h,min,s=str:match("(%d?%d?%d?%d?)/?(%d+)/(%d+)/(%d%d):(%d%d):?(%d?%d?)")
    local t = os.date("*t")
    return os.time{year=y~="" and y or t.year,month=m,day=d,hour=h,min=min,sec=s~="" and s or 0}
  end
  
  local tokenMetatable = {
    __tostring = function (t) return fmt("%s:%s/%s/%s",t.type,t.value or t.opval,t.from,t.to) end
  }
  
  local function token(prefix, pattern, createFn)
    pattern = "^(" .. pattern .. ")"
    local function fn(ctx)
      local _, len, res, group = string.find(ctx.source, pattern)
      if len then
        if createFn then
          local tokenv = createFn(group or res)
          tokenv.from, tokenv.to = ctx.cursor+1, ctx.cursor+len
          table.insert(ctx.tokens, tokenv)
          setmetatable(tokenv, tokenMetatable)
        end
        ctx.source = string.sub(ctx.source, len+1)
        ctx.cursor = ctx.cursor + len
        return true
      end
    end
    for c in prefix:gmatch"." do
      patterns[c] = patterns[c] or {}
      table.insert(patterns[c], fn)
    end
  end
  
  local nopers = {['jmp']=true,}--['return']=true}
  local SW={['(']='lpar',[')']='rpar',['{']='lcur',['}']='rcur',['[']='lbra',[']']='rbra',['||']='lor',[',']='comma'}
  local function checkOp(op) return ER.opers0[op] and ER.opers0[op].op and "op" or "badop" end
  local function keywordOp(op) return ER.opers0[op] and ER.opers0[op].op end
  local function trans(op) return ER.opers0[op] and ER.opers0[op].trans or op end
  local keyword={
    ['if']='t_if',['then']='t_then',['else']='t_else',['elseif']='t_elseif',['end']='t_end',['while']='t_while',
    ['repeat']='t_repeat',['do']='t_do',['until']='t_until',['return']='t_return',['for']='t_for',
  }
  
  token(" \t\n\r","[%s%c]+")
  --2019/3/30/20:30
  token("0123456789","%d?%d?%d?%d?/?%d+/%d+/%d%d:%d%d:?%d?%d?",function (t) return {type="num", value=toTimeDate(t)} end)
  token("0123456789","%d%d:%d%d:?%d?%d?",function (t) return {type='num', value=toTime(t)} end)
  token("0123456789","%d+:%d+",function (_) error('Bad time constant') end)
  token("t+n","[t+n][/]", function (op) return {type="op", opval=trans(op)} end)
  token("#","#[A-Za-z_][%w_%-]*",function (w) return {type="event", value=w:sub(2)} end)
  --token("[A-Za-z_][%w_]*", function (w) return {type=nopers[w] and 'operator' or "name", sw=nopers[w] and 'op' or 'nam', value=w} end)
  token("_abcdefghijklmnopqrstuvwxyzåäöABCDEFGHIJKLMNOPQRSTUVWXYZÅÄÖ\xC3\xA5\xA4\xB6\x85\x84\x96","[_a-zA-Z\xC3\xA5\xA4\xB6\x85\x84\x96][_0-9a-zA-Z\xC3\xA5\xA4\xB6\x85\x84\x96]*", 
  function (w) return keywordOp(w) and {type='op',opval=trans(w)} or {type=keyword[w] or "name", value=w} end)
  token("0123456789","%d+%.%d+", function (d) return {type="num", value=tonumber(d)} end)
  token("0123456789","%d+", function (d) return {type="num", value=tonumber(d)} end)
  token('"','"([^"]*)"', function (s) return {type="str", value=s} end)
  token("'","'([^']*)'", function (s) return {type="str", value=s} end)
  token("-","%-%-.-\n")
  token("-","%-%-.*")
  token(">",">>",function() return {type="t_gg", value=">>"} end)
  token("|","||",function() return {type="t_vv", value=">>"} end)
  token("=","===",function (op) return {type="op", opval=trans(op)} end)    
  token(".","%.%.%.",function (op) return {type="op", opval=trans(op)} end)
  token("$","%$%$", function (op) return {type="op", opval=trans(op)} end)
  token("@$=<>!+.-*&|/^~;:","[@%$=<>!+%.%-*&|/%^~;:][%+@=<>&|;:%.]?", function (op) return {type=checkOp(op), opval=trans(op)} end)
  token("{}(),[]#%","[{}%(%),%[%]#%%]", function (op) return {type=SW[op] or checkOp(op), opval=trans(op)} end)
  
  local function dispatch(c,ctx) 
    for _,m in ipairs(patterns[c] or {}) do
      if m(ctx) then return true end
    end
  end
  
  local function tokenize(src)
    local ctx = { source = src, tokens = {}, cursor = 0 }
    while #ctx.source>0 and dispatch(ctx.source:sub(1,1),ctx) do end
    if #ctx.source > 0 then 
      print("tokenizer failed at " .. ctx.source) 
    end
    return ctx.tokens
  end
  
  function ER:tokenize(str)
    return ER.utilities.stream(tokenize(str))
  end
  
end