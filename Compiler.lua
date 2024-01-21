fibaro.__ER  = fibaro.__ER or { modules={} }

function fibaro.__ER.modules.compiler(ER)
  
  local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
  PrintBuffer,sunData,LOG,LOGERR,htmlTable,evOpts =
  table.unpack(ER.utilities.export)

  local isParseConst = ER.isParseConst
  local errorMsg = ER.utilities.errorMsg
  local e_error = ER.utilities.xerror
  
  local compile
  local function makeOut()
    local self,code,dbg = {},{},{}
    self.code,self.dbg = code,dbg
    function self.instr(p,...) 
      local i = {...}
      table.insert(i,2,#i-1) code[#code+1]=i 
      dbg[i] = p
      return i
    end
    return self
  end
  
  local currentSource = ""
  local function errorf(p,fm,...)
    if p.d then p = p.d end
    local err = errorMsg{type="Compiler",msg=string.format(fm,...),from=p.from,to=p.to,src=currentSource}
    e_error(err) 
  end
  
  local comp,comp_op = {},{}
  
  function comp.num(p,out) out.instr(p,'push',p.value) end
  function comp.str(p,out) out.instr(p,'push',p.value) end
  function comp.var(p,out)
    if ER.constants[p.name] then
      out.instr(p,p.name)
    else
      out.instr(p,'var',p.name)
    end
  end
  function comp.const(p,out) 
    if type(p.value) == 'table' then 
      out.instr(p,'pushc',p.value) 
    else
      out.instr(p,'push',p.value) 
    end
  end
  function comp.gv(p,out) out.instr(p,'gv',p.name) end
  function comp.qv(p,out) out.instr(p,'qv',p.name) end
  function comp.pv(p,out) out.instr(p,'pv',p.name) end
  function comp.addto(p,out) compile(p.arg,out); out.instr(p,p.type,p.const,p.rev) end
  function comp.multo(p,out) compile(p.arg,out); out.instr(p,p.type,p.const,p.rev) end
  function comp.subto(p,out) compile(p.arg,out); out.instr(p,p.type,p.const,p.rev) end
  function comp.divto(p,out) compile(p.arg,out); out.instr(p,p.type,p.const,p.rev) end
  function comp.modto(p,out) compile(p.arg,out); out.instr(p,p.type,p.const,p.rev) end
  function comp.op(p,out)
    if comp_op[p.op] then
      comp_op[p.op](p,out)
    else
      for _,a in ipairs(p.args) do compile(a,out) end
      out.instr(p,p.op)
    end
  end
  function comp.f_not(p,out)
    compile(p.args[1],out)
    out.instr(p,'f_not')
  end
  function comp.f_if(p,out)
    compile(p.cond,out)
    if p.els==nil then
      local i,pc = out.instr(p,'jmpf',0),#out.code
      compile(p.th,out)
      i[3] = #out.code-pc+1
    else
      local i,pc = out.instr(p,'jmpfp',0),#out.code
      compile(p.th,out)
      local e,pc2= out.instr(p,'jmp',0),#out.code
      i[3] = #out.code-pc+1
      compile(p.els,out)
      e[3] = #out.code-pc2+1
    end
  end
  
  function comp.rule_action(p,out)
    compile(p.cond,out)
    out.instr(p,'rule_action')
    compile(p.action,out)
  end
  
  function comp_op.f_and(p,out)
    local jmps = {}
    for i=1,#p.args-1 do 
      compile(p.args[i],out)
      jmps[#jmps+1] = {out.instr(p,'jmpf',0),#out.code}
    end
    compile(p.args[#p.args],out)
    for _,j in ipairs(jmps) do j[1][3] = #out.code-j[2]+1 end
  end
  
  function comp_op.f_or(p,out)
    local jmps = {}
    for i=1,#p.args-1 do 
      compile(p.args[i],out)
      jmps[#jmps+1] = {out.instr(p,'jmpt',0),#out.code}
    end
    compile(p.args[#p.args],out)
    for _,j in ipairs(jmps) do j[1][3] = #out.code-j[2]+1 end
  end
  
  function comp_op.prop(p,out)
    local val = p.args[1]
    local prop = p.args[2]
    compile(val,out)
    out.instr(p,'prop',prop) 
  end
  
  function comp_op.elist(p,out) comp_op.progn({type='op',args=p.args},out) end

  function comp.aref(p,out)
    local k = isParseConst(p.key)
    if k then
      compile(p.tab,out)
      out.instr(p.tab,'aref',false,k)
    else
      compile(p.tab,out)
      compile(p.key,out)
      out.instr(p,'aref',false,false) -- variable,constant key
    end
  end
  
  function comp.aset(p,out)
    compile(p.tab,out)
    local k = isParseConst(p.key)
    if not k then compile(p.key,out) end
    local v = isParseConst(p.value)
    if not v then compile(p.value,out) end
    out.instr(p,'aset',k and k[1] or nil,v,false) -- variable,constant key,constant value,pop value
  end
  
  function comp.putprop(p,out)
    -- {type='putprop', device=p.args[1], prop=p.args[2], value=value}
    compile(p.device,out)
    compile(p.value,out)
    out.instr(p,'putprop',p.prop)
  end
  function comp.call(p,out)
    for _,arg in ipairs(p.args) do compile(arg,out) end
    local n = table.maxn(p.args)
    if ER.builtins[p.name] then
      local d = ER.builtinArgs[p.name]
      if d then if n < d[1] or n > d[2] then errorf(p,"Wrong number of arguments for builtin '%s' (%s,%s)",p.name,d[1],d[2]) end end
      out.instr(p,p.name,n)
    else
      out.instr(p,'call',p.name,n)
    end
  end
  function comp.callexpr(p,out)
    compile(p.expr,out)
    for _,arg in ipairs(p.args) do compile(arg,out) end
    out.instr(p,'call',false,#p.args)
  end
  function comp.callobj(p,out)
    local tab = p.expr
    local k = isParseConst(tab.key)
    compile(tab.tab,out)              
    out.instr(p,'aref',false,k,true) -- aref that pushes tab on the stack and becomes first arg to call
    for _,arg in ipairs(p.args) do compile(arg,out) end
    out.instr(p,'call',false,#p.args+1)
  end

  local popInstr = { setvar = true, aset=true, push=false }
  function comp_op.progn(p,out)
    if #p.args == 0 then return end
    for i=1,#p.args-1 do 
      compile(p.args[i],out)
      local ins = out.code[#out.code]
      local dopop = popInstr[ins[1]]
      if dopop~=nil then 
        if dopop then ins[5] = true
        else table.remove(out.code,#out.code) end
      else
        --print("POP after",ins[1])
        out.instr(p,'pop') 
      end
    end
    compile(p.args[#p.args],out)
  end
  function comp.f_while(p,out)   -- A <cond> jmpf B <body> jmpp A, B
    local start = #out.code+1
    compile(p.cond,out)
    local acond = #out.code
    local e = out.instr(p,'jmpf',0)
    compile(p.body,out)
    out.instr(p,'jmpp',start-#out.code-1)
    e[3] = #out.code-acond
  end
  function comp.f_repeat(p,out) -- A <progn> jmpfp A
    local start,body = #out.code+1,p.body
    if p.body.op=='progn' then
      table.insert(body.args,p.cond)
    else
      body = {type='op',op='progn',args={p.body,p.cond}}
    end
    compile(body,out)
    out.instr(p,'jmpfip',start-#out.code-1)
  end
  
  function comp.forfun(p,out)
    local name,const,exprs = p.name,p.const,p.exprs
    local n = table.maxn(exprs)
    for i=1,n  do compile(exprs[i],out) end
    out.instr(p,p.name,n,table.unpack(p.const))
  end
  
  function comp.f_return(p,out)
    local args = p.args
    if args == nil then out.instr(p,'return0')
    elseif args.op == 'elist' then
      for _,arg in ipairs(args.args) do compile(arg,out) end
      out.instr(p,'returnm',#args.args)
    else
      compile(args,out)
      out.instr(p,'return1')
    end 
  end
  
  -- x,y = 3,4
  -- collect(tag,3,4)
  -- x = mv(tag,1); y = mv(tag,2,delete)
  
  -- x,y = foo()
  -- local t1,t2 = foo()
  -- x = t1; y = t2
  
  function comp.setvar(p,out)
    if p.createLocal then out.instr(p,'local',p.name) end
    local c = isParseConst(p.value)
    if c then 
      out.instr(p,'setvar',p.name,c,false)
    else
      compile(p.value,out)
      out.instr(p,'setvar',p.name,false,false)
    end
  end
  function comp.setgv(p,out)
    local c = isParseConst(p.value)
    if c then 
      out.instr(p,'setgv',p.name,c,false)
    else
      compile(p.value,out)
      out.instr(p,'setgv',p.name,false,false)
    end
  end
  function comp.setqv(p,out)
    local c = isParseConst(p.value)
    if c then 
      out.instr(p,'setqv',p.name,c,false)
    else
      compile(p.value,out)
      out.instr(p,'setqv',p.name,false,false)
    end
  end
  function comp.setpv(p,out)
    local c = isParseConst(p.value)
    if c then 
      out.instr(p,'setpv',p.name,c,false)
    else
      compile(p.value,out)
      out.instr(p,'setpv',p.name,false,false)
    end
  end
  function comp_op.f_local(p,out)   -- like massign but assignments creates locals
    compile(p.arg,out)
    for i,v in ipairs(p.dest) do compile(v,out) end
  end
  function comp.massign(p,out)
    compile(p.arg,out)
    for i,v in ipairs(p.dest) do compile(v,out) end
  end
  function comp.mv(p,out) out.instr(p,'mv',p.tag,p.id,p.size,p.free) end
  function comp.collect(p,out)
    out.instr(p,'mvstart',p.tag)
    local args = p.args
    for _,arg in ipairs(args) do compile(arg,out) end
    out.instr(p,'mvend',p.tag)
  end

  function comp.table(p,out)
    local args,keys = p.value,{}
    for i,v in pairs(args) do
      if v[1]=='const' then
        keys[#keys+1]=v[2]
        compile(v[3],out)
      else
        compile(v[2],out)
        compile(v[3],out)
        keys[#keys+1] = '%comp%'
        keys[#keys+1] = '%value%'
      end
    end
    out.instr(p,'table',keys)
  end
  function comp.eventm(p,out) out.instr(p,'eventm',p.evid,p.event) end
  
  function comp.rule(p,out) out.instr(p,'rule',p.cond,p.action) end
  
  function compile(p,out)
    if p == nil then
      error("compile: nil parse node")
    end
    --print(json.encode(p))
    if comp[p.type] then
      comp[p.type](p,out)
    else
      error("Unknown parse node type: "..json.encode(p.type))
    end
  end
  
  local fID = 0
  function ER:compile(input,options) --> codeString/ParseTree -> Function
    currentSource = options.src
    local parseTree
    if type(input) == 'string' then -- assume we got a code, parse to parseTree
      local token = ER:tokenize(input)
      parseTree = ER:parse(token)
    elseif type(input) == 'table' then -- we got a parseTree
      parseTree = input
    else 
      error("compile: bad input type to compile: "..type(input)) 
    end
    local out = makeOut()
    compile(parseTree,out)
    fID = fID+1
    local codestr = {name = options.name or fID, src = options.src, code = out.code, dbg = out.dbg, timestamp =os.time()}
    return ER:createFun(codestr,options)
  end
  
end