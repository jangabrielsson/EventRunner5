---@diagnostic disable: need-check-nil
fibaro.__ER  = fibaro.__ER or { modules={} }

function fibaro.__ER.modules.parser(ER)
  
  local fmt = string.format
  
  local stack,stream,errorMsg,isErrorMsg,e_error,e_pcall,errorLine,
  marshallFrom,marshallTo,toTime,midnight,encodeFast,argsStr,eventStr,
  PrintBuffer,sunData,LOG,LOGERR,htmlTable,evOpts,eventCustomToString =
  table.unpack(ER.utilities.export)
  
  local opers0 = {
    ['%neg']={op=false, prio=14, arity=1, trans='neg'},           -- unary minus
    ['t/']  ={op=true,  prio=14,  arity=1, trans='t_today'},      -- today time constant, t/10:00
    ['n/']  ={op=true,  prio=14,  arity=1, trans='t_next'},       -- next today time constant, n/10:00
    ['+/']  ={op=true,  prio=14,  arity=1, trans='t_plus'},       -- from today time constant, +/10:00
    ['$']   ={op=true,  prio=14,  arity=1, trans='gv'},           -- global variable, $var
    ['$$']  ={op=true,  prio=14,  arity=1, trans='qv'},           -- quickApp variable, $var
    ['.']   ={op=true,  prio=12.9,arity=2, trans='aref',la=true}, -- table accessor
    [':']   ={op=true,  prio=12.9,arity=2, trans='prop',la=true}, -- property accessor
    ['..']  ={op=true,  prio=9,   arity=2, trans='betw'},         -- between operator, 10:00..11:00
    ['...'] ={op=true,  prio=9,   arity=2, trans='betwo'},  
    ['@']   ={op=true,  prio=9,   arity=1, trans='daily'},        -- day rule, @10:00
    ['jmp'] ={op=false, prio=9,   arity=1, trans='jmp'},
    ['::']  ={op=false, prio=9,   arity=1, trans='label'},
    ['@@']  ={op=true,  prio=9,   arity=1, trans='interv'},       -- interval rule, @@00:05
    ['+']   ={op=true, prio=11,   arity=2, trans='add'},
    ['-']   ={op=true, prio=11,   arity=2, trans='sub'},
    ['*']   ={op=true, prio=12,   arity=2, trans='mul'},
    ['/']   ={op=true, prio=12,   arity=2, trans='div'},
    ['++']  ={op=true, prio=10,   arity=2, trans='conc'},         -- string concatenation
    ['==='] ={op=true, prio=9,    arity=2, trans='match'},        -- string match
    ['%']   ={op=true, prio=12,   arity=2, trans='mod'},          -- modulo
    ['==']  ={op=true, prio=6,    arity=2, trans='eq'},           -- equal
    ['<=']  ={op=true, prio=6,    arity=2, trans='lte'},
    ['>=']  ={op=true, prio=6,    arity=2, trans='gte'},
    ['~=']  ={op=true, prio=6,    arity=2, trans='neq'},          -- not equal
    ['>']   ={op=true, prio=6,    arity=2, trans='gt'},
    ['<']   ={op=true, prio=6,    arity=2, trans='lt'},
    ['&']   ={op=true, prio=5,    arity=2, trans='f_and'},        -- logical and
    ['|']   ={op=true, prio=4,    arity=2, trans='f_or'},         -- logical or
    ['!']   ={op=true, prio=5.1,  arity=1, trans='f_not'},        -- logical not
    [',']   ={op=true, prio=0.2,  arity=2, trans='elist'},        -- expression list
    ['local']  ={op=true, prio=0.1,  arity=1, trans='f_local'},
    ['in']  ={op=true, prio=0.1,  arity=2, trans='f_in'},
    ['=']   ={op=true, prio=0,    arity=2, trans='assign'},       -- assignment
    ['+=']  ={op=true, prio=0,    arity=2, trans='addto'},
    ['-=']  ={op=true, prio=0,    arity=2, trans='subto'},
    ['*=']  ={op=true, prio=0,    arity=2, trans='multo'},
    [';']   ={op=true, prio=-1,   arity=2, trans='progn'},
    [';;']  ={op=true, prio=-1.1, arity=2, trans='dprogn'},
    ['=>']  ={op=true, prio=-10,  arity=2, trans='rule'},
  }
  local opers = {}
  for k,v in pairs(opers0) do v.org = k; opers[v.trans] = v end
  ER.opers0 = opers0
  ER.opers = opers
  
  -- <EXPR> := IF <EXPR> THEN <EXPR> ELSE <EXPR> END
  -- <EXPR> := WHILE <EXPR> DO <EXPR> END
  -- <EXPR> := REPEAT <EXPR> DO <EXPR> END
  -- <EXPR> := <EXPR> <OP> <EXPR>
  -- <EXPR> := <EXPR> <OP> <EXPR>
  -- <EXPR> := <EXPR> <OP> <EXPR>
  
  --
  
  local pExpr
  local transform
  local GS = 789790
  local function gensym() GS = GS + 1; return "GSV"..GS end
  local currentSource,currentRule = "",nil

  local function DB(t) return t.d and {from=t.d.from,to=t.d.to} or {from=t.from,to=t.to} end
  local function errorf(tk,fm,...)
    if tk.d then tk = tk.d end
    local err = errorMsg{type="Parser",msg=fmt(fm,...):lower(),from=tk.from,to=tk.to,src=currentSource,rule=currentRule}
    e_error(err) 
  end
  local function assertf(tk,cond,fm,...)
    if not cond then errorf(tk,fm,...) end
  end
  
  local function prio(t) return opers[t.opval].prio end
  local function higherPrio(op1,op2)
    local la = opers[op1.opval].la
    if op1.op ~= op2.op or not la then return prio(op1) > prio(op2)
    else return prio(op1) >= prio(op2) end
  end
  
  local function isConst(p)
    return (p.type == 'num' or p.type == 'str' or p.type == 'const') and {p.value} or nil
  end
  ER.isParseConst = isConst
  
  local function pArgs(ops,st,tkns,stop)
    local args,tkn = {},tkns.peek()
    while tkns.peek().type ~= stop do
      if tkns.peek().type=='eof' then errorf(tkn,'Missing %s',stop) end
      args[#args+1] = pExpr(tkns,{['comma']=true,[stop]=true,eof=true})
      if tkns.peek().type == 'comma' then tkns.next() end
    end
    tkns.next()
    return args
  end
  local function pStruct(ops,st,tkns,stop)
    local args,tkn = {},tkns.peek()
    while tkns.peek().type ~= stop do
      if tkns.peek().type=='eof' then errorf(tkn,'Missing %s',stop) end
      if tkns.peek().type == 'lbra' then 
        local nt = tkns.next()
        local k = pExpr(tkns,{['rbra']=true,eof=true})
        if tkns.next().type~='rbra' then errorf(nt,"Missing ']' for value key") end
        nt = tkns.next()
        if nt.opval~='assign' then errorf(nt,"Missing '=' for value key") end
        local v = pExpr(tkns,{['comma']=true,[stop]=true,eof=true})
        args[#args+1] = {type='op', op='assign', args={k,v},d=DB(nt)}
      else
        args[#args+1] = pExpr(tkns,{['comma']=true,[stop]=true,eof=true})
      end
      if tkns.peek().type == 'comma' then tkns.next() end
    end
    tkns.next()
    return args
  end
  local function apply(op,st)
    if ER.opers[op.opval].arity == 1 then
      local a = st.pop()
      if a==nil then errorf(op,'Missing argument for %s',opers[op.val].org) end
      st.push({type='op', op=op.opval, args={a},d=DB(op)})
    else
      local b,a = st.pop(),st.pop()
      if a==nil then errorf(op,'Missing first argument for %s',opers[op.opval].org) end
      if b==nil then errorf(op,'Missing second argument for %s',opers[op.opval].org) end
      st.push({type='op', op=op.opval, abra=op.abra, args={a,b},d=DB(op)})
    end
  end
  
  local ptable = {}
  function ptable.num(nt,ops,st,tkns,stop) st.push({type='num', value=nt.value,d=DB(nt)}) end
  function ptable.str(nt,ops,st,tkns,stop) st.push({type='str', value=nt.value,d=DB(nt)}) end
  function ptable.event(nt,ops,st,tkns,stop)
    local keyvalues = {
      type='op', op='assign',
      args={
        {type='var', name='type',d=DB(nt)},
        {type='str', value=nt.value,d=DB(nt)},
      },
      d=DB(nt)
    }
    keyvalues = {keyvalues}
    if tkns.peek().type == 'lcur' then
      tkns.next()
      local args = pStruct(ops,st,tkns,'rcur')
      table.insert(args,1,keyvalues[1])
      keyvalues = args
    end
    st.push({type='table', args=keyvalues,d=DB(nt)})
  end
  function ptable.lpar(nt,ops,st,tkns,stop)
    st.push(pExpr(tkns,{['rpar']=true,eof=true}))
    if tkns.next().type~='rpar' then errorf(nt,"Missing ')'") end
  end
  local makeForList
  local function makeProgn(...)
    local args = {...}
    local t = args[#args]
    for i=#args-1,1,-1 do
      local e = args[i]
      t = {type = 'op', op='progn', args={e,t}, d=DB(e)}
    end
    return t
  end
  local function filter(expr,list,nt)   -- lo cal r={}; fo r G,_ in ipairs(list) d o filter(<expr>,r) en d; r
    local res,k = gensym(),gensym()
    local out = {type='var', name='_', d=DB(nt)}
    if expr.op == 'elist' then
      out = expr.args[2]
      expr = expr.args[1]
    end
    list = transform(list)
    local liste = {type='call', name='ipairs',args={list},d=DB(nt)}
    local r = makeProgn(
        {type='setvar', name=res, createLocal=true, value={type='const', value={},d=DB(nt)}},
        makeForList(k,'_',liste,{type='call', name='filter', args={expr,{type='var',name=res},out},d=DB(nt)},nt),
        {type='var', name=res,d=DB(nt)}
      )
    return r
  end
  function ptable.lbra(nt,ops,st,tkns,stop)
    local sub = pExpr(tkns,{['rbra']=true,eof=true})
    if tkns.next().type~='rbra' then errorf(nt,"Missing ']'") end
    if sub.op == 'f_in' then
      st.push(filter(sub.args[1],sub.args[2],nt))
    else
      st.push(sub)
      ops.push({type='op', opval='aref',abra=true, d=DB(nt)})
    end
  end
  function ptable.lcur(nt,ops,st,tkns,stop)
    local args = pStruct(ops,st,tkns,'rcur')
    st.push({type='table', args=args,d=DB(nt)})
  end
  
  local constants = {['true']={true},['false']={false},['nil']={nil}}
  function ptable.name(nt,ops,st,tkns,stop)
    local name = nt.value
    if constants[name] then
      st.push({type='const', value=constants[name][1],d=DB(nt)})
    elseif tkns.peek().type=='lpar' then
      tkns.next()
      local args = pArgs(ops,st,tkns,'rpar')
      local po = ops.peek() or {}
      if po.opval == 'prop' or po.opval == 'aref' then
        ops.pop()
        ops.push({type='op', opval='aref',d=DB(nt)})
        st.push({type='var', name=name,d=DB(nt)})
        while not ops.isEmpty() and higherPrio(ops.peek(),{type='op', opval='aref'}) do apply(ops.pop(),st) end
        st.push({type=po.opval == 'aref' and 'callexpr' or 'callobj', expr=st.pop(), args=args,d=DB(nt)})
        return
      end
      st.push({type='call', name=name, args=args,d=DB(nt)})
    else
      st.push({type='var', name=name,d=DB(nt)})
    end
  end
  
  function ptable.op(nt,ops,st,tkns,stop)
    local lt = tkns.prev().type
    if nt.opval == 'sub' and not(lt == 'name' or lt == 'num' or lt == '()' or lt == 'rpar' or lt == 'rbra') then nt.opval='neg' end
    while not ops.isEmpty() and higherPrio(ops.peek(),nt) do apply(ops.pop(),st) end
    ops.push(nt)
  end
  function ptable.t_dprogn(nt,ops,st,tkns,stop)
    nt = {type='op', opval='dprogn'}
    ptable.op(nt,ops,st,tkns,stop)
  end
  function ptable.t_if(nt,ops,st,tkns,stop)
    local cond = pExpr(tkns,{['t_then']=true,eof=true})
    assertf(nt,tkns.next().type== 't_then',"missing 'THEN' for 'IF'")
    local th = pExpr(tkns,{['t_else']=true,['t_elseif']=true,['t_end']=true,eof=true})
    local res = {type='f_if', cond=cond, th=th,d=DB(nt)}
    local r = res
    assertf(nt,tkns.peek().type~='eof',"missing 'END' for 'IF'")
    while tkns.peek().type=='t_elseif' do
      local nt2 = tkns.next()
      local cond = pExpr(tkns,{['t_then']=true,eof=true})
      assertf(nt2,tkns.next().type=='t_then',"missing 'THEN' for 'ELSEIF'")
      local th = pExpr(tkns,{['t_else']=true,['t_elseif']=true,['t_end']=true,eof=true})
      r.els = {type='f_if', cond=cond, th=th,d=DB(nt2)}
      r = r.els
      assertf(nt2,tkns.peek().type~='eof',"missing 'END' for 'ELSEIF'")
    end 
    if tkns.peek().type=='t_else' then
      local nt3 = tkns.next()
      local f = pExpr(tkns,{['t_end']=true,eof=true})
      assertf(nt3,tkns.peek().type=='t_end',"missing 'END' for 'ELSE'")
      r.els = f
    elseif tkns.peek().type=='t_end' then
    else
      errorf(nt,"missing 'end' for 'if'")
    end
    tkns.next()
    st.push(res)
  end
  function ptable.t_vv(nt,ops,st,tkns,stop)
    local cond = pExpr(tkns,{['t_gg']=true,eof=true})
    assertf(nt,tkns.next().type== 't_gg',"missing '>>' for '||'")
    local body = pExpr(tkns,{['t_vv']=true,['t_dprogn']=true,eof=true})
    local t2,res = tkns.peek()
    if t2.type=='eof' or t2.type=='t_dprogn' then
      res = {type='f_if', cond=cond, th=body, d=DB(nt)}
    -- elseif t2.type=='t_dprogn' then
    --   tkns.next()
    --   res = {type='f_if', cond=cond, th=body, d=DB(nt)}
    --   st.push(res)
    --   nt = {type='op',opval='progn'}
    --   while not ops.isEmpty() and higherPrio(ops.peek(),nt) do apply(ops.pop(),st) end
    --   ops.push(nt)
    --   return
    elseif t2.type=='t_vv' then
      stop = table.copyShallow(stop)
      stop['t_dprogn'] = true
      local els = pExpr(tkns,stop)
      res = {type='f_if', cond=cond, th=body, els = els, d=DB(nt)}
    else errorf(nt,"bad ||>> expression") end
    st.push(res)
  end
  function ptable.t_while(nt,ops,st,tkns,stop)
    local cond = pExpr(tkns,{['t_do']=true,eof=true})
    assertf(nt,tkns.next().type=='t_do',"missing 'DO' for 'WHILE'")
    local body = pExpr(tkns,{['t_end']=true,eof=true})
    assertf(nt,tkns.next().type=='t_end',"missing 'end' for 'WHILE'")
    st.push({type='f_while', cond=cond, body=body,d=DB(nt)})
  end
  function ptable.t_repeat(nt,ops,st,tkns,stop)
    local body = pExpr(tkns,{['t_until']=true,eof=true})
    assertf(nt,tkns.next().type=='t_until',"missing 'UNTIL' for 'REPEAT'")
    local cond = pExpr(tkns,{progn=true,eof=true})
    st.push({type='f_repeat', cond=cond, body=body, d=DB(nt)}) 
  end
  
  local function for_fun(name,const,exprs)
    return {type='forfun', name=name, const=const or {}, exprs=exprs or {}}
  end
  
  function makeForList(kvar,vvar,expr,body,nt)
    if expr.type ~= 'call' then errorf(nt,"Bad for loop list - expected pairs/ipairs") end
    local fvar,lvar,svar = gensym(),gensym(),gensym()
    local setup = for_fun('flsetup',{kvar,vvar,fvar,lvar,svar},{expr})
    local flinc = for_fun('flinc',{kvar,vvar,fvar,lvar},{})
    local pwhile = {
      type = 'f_while',
      cond = {type='var', name=kvar},
      body = {type='op', op='progn', args={body,flinc}}
    }
    return {type='op', op='progn', args = {
      setup,
      {type='op', op='progn', args = {flinc,pwhile}, d=DB(nt)},
      d=DB(nt)
    }}
  end
  function ptable.t_for(nt,ops,st,tkns,stop)
    local args = pExpr(tkns,{['t_do']=true,eof=true})
    assertf(nt,tkns.next().type=='t_do',"missing 'do' in 'for do .. end'")
    local body = pExpr(tkns,{t_end=true,eof=true})
    assertf(nt,tkns.next().type=='t_end',"missing 'end' in 'for do .. end'")
    if args.op == 'assign' then
      if args.args[1].type ~= 'var' then errorf(nt,"expected variable as index in for loop") end
      local idx = args.args[1].name
      local params = transform(args.args[2])
      if params.op ~= 'elist' then errorf(nt,"expected start,stop in for loop") end
      local sav,sov,se = params.args[1],params.args[2],params.args[3] or {type='num',value=1}
      local sgv,stopv,stepv = gensym(),gensym(),gensym()
      local setup = for_fun('idxsetup',{idx,sgv,stopv,stepv},{sav,sov,se})
      local pwhile = {
        type = 'f_while',
        cond = for_fun('idxcond',{idx,sgv,stopv}),
        body = {type='op', op='progn', args={body,for_fun('idxinc',{idx,stepv})}}
      }
      st.push({type='op', op='progn', args = {setup,pwhile}, d=DB(nt)})
      return
    elseif args.op == 'f_in' then
      local vars = args.args[1]
      if vars.op == 'elist' then
        for _,v in ipairs(vars.args) do
          if v.type ~= 'var' then errorf(nt,"Bad for loop variable") end
          vars[#vars+1] = v.name
        end
      elseif vars.type 'var' then
        vars[1] = vars.name
      else end
        local expr = transform(args.args[2])
        st.push(makeForList(vars[1],vars[2],expr,body,nt))
    else
      errorf(nt,"bad 'for' expression")
    end
  end
  
  
  local stopReturn = {t_end=true,progn=true,eof=true}
  function ptable.t_return(nt,ops,st,tkns,stop)
    local t = tkns.peek()
    if stopReturn[t.type] then
      st.push({type='f_return',d=DB(nt)})
    else
      local pexpr = pExpr(tkns,stopReturn)
      st.push({type='f_return', args=pexpr,d=DB(nt)})
    end
  end
  
  local function pExpr2(ops,st,tkns,stop)
    while true do
      local nt = tkns.peek()
      if stop[nt.type] or stop[nt.opval]  then return end
      if nt.type == 'comma' then nt.type,nt.opval='op','elist' end
      if ptable[nt.type] then
        tkns.next()
        ptable[nt.type](nt,ops,st,tkns,stop)
      else
        errorf(nt,"Unknown token type: "..nt.type)
      end
    end
  end
  
  function pExpr(tkns,stop)
    local ops,st = stack (),stack()
    pExpr2(ops,st,tkns,stop)
    while not ops.isEmpty() do apply(ops.pop(),st) end
    if st.size() > 1 then
      errorf(st.pop(),"Bad expression") 
    end
    return st.pop()
  end
  
  local trans,trans_op = {},{}
  
  local function trans_flatten(p,typ,op)
    local  t1 = transform(p.args[1])
    local t2 = p.args[2]
    if t2 == nil then return t1 end
    local  t2 = transform(t2)
    if t2.type == typ and t2.op==op then
      table.insert(t2.args,1,t1)
      return t2
    else
      return {type=typ, op=op, d=p.d, args={t1,t2}}
    end
  end
  
  local function assertType(t,v,msg) if not(type(v)=='table' and v.type==t) then errorf(v,msg or ("Expected "..t)) end end
  function trans_op.gv(p) assertType('var',p.args[1],"Expected name");    return {type='gv', name=p.args[1].name} end
  function trans_op.qv(p) assertType('var',p.args[1],"Expected name");    return {type='qv', name=p.args[1].name} end
  function trans_op.progn(p) return trans_flatten(p,'op','progn') end
  function trans_op.dprogn(p) return trans_flatten(p,'op','progn') end
  function trans_op.elist(p) return trans_flatten(p,'op','elist') end
  function trans_op.f_and(p) return trans_flatten(p,'op','f_and') end
  function trans_op.f_or(p) return trans_flatten(p,'op','f_or') end
  function trans_op.f_local(p) p.args[1] = transform(p.args[1]) return p end
  function trans_op.prop(p) 
    p.args[1] = transform(p.args[1])
    if p.args[2].type~='var' then errorf(p,'Property must be a name') end
    p.args[2] = p.args[2].name
    return p 
  end
  
  -- ToDo, optimize these
  function trans_op.addto(p) return transform({type='op', op='assign', d=p.d, args={p.args[1],{type='op', op='add', args={p.args[1],p.args[2]}}}}) end
  function trans_op.subto(p) return transform({type='op', op='assign', d=p.d, args={p.args[1],{type='op', op='sub', args={p.args[1],p.args[2]}}}}) end
  function trans_op.multo(p) return transform({type='op', op='assign', d=p.d, args={p.args[1],{type='op', op='mul', args={p.args[1],p.args[2]}}}}) end

  local tops = {}
  function tops.add(a,b) return a+b end
  function tops.sub(a,b) return a-b end
  function tops.mul(a,b) return a*b end
  function tops.div(a,b) return a/b end
  function tops.mod(a,b) return a%b end
  
  local arithSingle = {add='addto',mul='multo',sub='subto',div='divto',mod='modto'}
  local function trans_op_calc(p)
    local  t1 = transform(p.args[1])
    local  t2 = transform(p.args[2])
    if t1.type == 'num' and t2.type=='num' and tops[p.op] then
      return {type='num', value=tops[p.op](t1.value,t2.value) ,d=p.d}
    elseif not arithSingle[p.op] then
      return {type='op', op=p.op, args={t1,t2}, d=p.d}
    elseif t1.type == 'num' then
      return {type=arithSingle[p.op], const=t1.value, arg=t2, rev=false, d=p.d}
    elseif t2.type == 'num' then
      return {type=arithSingle[p.op], const=t2.value, arg=t1, rev=true, d=p.d}
    end
    return {type='op', op=p.op, args={t1,t2}, d=p.d}
  end
  
  trans_op.add = trans_op_calc
  trans_op.sub = trans_op_calc
  trans_op.mul = trans_op_calc
  trans_op.div = trans_op_calc
  trans_op.mod = trans_op_calc
  function trans_op.neg(p)
    local t1 = transform(p.args[1])
    if t1.type == 'num' then return {type='num', value=-t1.value, d=p.d}
    else return {type='op', op='neg', args={t1}, d=p.d} end
  end
  
  local _rvalues = {var='var',aref='aref',prop='prop',gv='gv',qv='qv'}
  local function isRvalue(p) return _rvalues[p.type] or _rvalues[p.op] end
  local _l2rvalue = {
    var = function(p,value) return {type='setvar', name=p.name, value=value, d=DB(p)} end,
    gv = function(p,value) return {type='setgv', name=p.name, value=value, d=DB(p)} end,
    qv = function(p,value) return {type='setqv', name=p.name, value=value, d=DB(p)} end,
    aref = function(p,value) return {type='aset', tab=p.tab, key=p.key, value=value,d=DB(p)} end,
    prop = function(p,value) return {type='putprop', device=p.args[1], prop=p.args[2], value=value, d=DB(p)} end,
  }
  local function LtoRvalue(p,value) local l=isRvalue(p) return l and _l2rvalue[l](p,value) end

  local cID = 1
  function trans_op.assign(p)
    local  t1 = transform(p.args[1])
    local  t2 = transform(p.args[2])
    local lv = LtoRvalue(t1,t2)
    if lv then return lv
    elseif t1.type == 'op' then
      local createLocal
      if t1.op=='prop' then return LtoRvalue(t1,t2) end
      if t1.op=='f_local' then
        if t1.args[1].type=='var' then 
          return {type='setvar', name=t1.args[1].name, value=t2, createLocal=true, d=DB(p)}
        elseif t1.args[1].op == 'elist' then
          t1.op = 'elist' -- treat it as an elist
          t1.args = t1.args[1].args
          createLocal = true
        end
      end
      if t1.op=='elist' then -- multiple value, make right hand a collect statement
        local tag = "c"..cID; cID = cID +1
        if t2.op=='elist' then
          t2 = {type='collect', args=t2.args, tag=tag}
        else
          t2 = {type='collect', args={t2}, tag=tag}
        end
        local dest,n = {},#t1.args
        for i,d in ipairs(t1.args) do
          if not isRvalue(d) then errorf(p,'Left hand side of multiple assignment must be a variable or table accessor') end
          local lv = LtoRvalue(d,{type='mv', id=i, tag=tag, size=n, free=i==n})
          lv.createLocal = createLocal
          dest[#dest+1] = lv
        end
        return {type='massign', dest=dest, arg=t2}
      end
    end
    errorf(p,'Left hand side of assignment unsupported')
  end
  
  function trans_op.rule(p) 
    local cond = transform(p.args[1])
    local action = transform(p.args[2])
    return {type='rule', cond=cond, action = action} 
  end
  
  function trans_op.daily(p)
    p.args[1] = transform(p.args[1])
    local arg = p.args[1]
    if arg.type ~= 'table' then
      local narg = transform({type='table', args={arg}, d=arg.d})
      p.args[1] = narg
    end
    return p
  end

  function trans_op.aref(p)
    local key = transform(p.args[2])
    if not p.abra then
      if key.type ~= 'var' then errorf(key,"Table .key must be a name") end
      key = {type='const', value=key.name, d=DB(p)}
    end
    local tab = transform(p.args[1])
    return {type='aref', tab=tab, key=key, d=DB(p)}
  end
  
  function trans.putprop(p)
    p.device = transform(p.device)
    p.prop = transform(p.prop)
    p.value = transform(p.value)
    return p
  end
  
  local function transformList(l) for i,v in pairs(l) do l[i] = transform(v) end end
  
  function trans.call(p) transformList(p.args); return p end
  function trans.callexpr(p) transformList(p.args); p.expr = transform(p.expr); return p end
  function trans.callobj(p) transformList(p.args); p.expr = transform(p.expr); return p end
  
  -- function trans.filter(p)
  --   p.expr = transform(p.expr)
  --   p.list = transform(p.list)
  --   return p
  -- end
  function trans.f_while(p) 
    p.cond = transform(p.cond)
    p.body = transform(p.body)
    return p
  end
  function trans.f_repeat(p)
    p.cond = transform(p.cond)
    p.body = transform(p.body)
    return p
  end
  function trans.f_if(p)
    p.cond = transform(p.cond)
    p.th = transform(p.th)
    if p.els then p.els = transform(p.els) end
    return p
  end
  function trans.f_return(p) p.args = transform(p.args) return p end
  function trans.op(p)
    if trans_op[p.op] then return trans_op[p.op](p) 
    else
      for i=1,#p.args do p.args[i] = transform(p.args[i]) end
      return p
    end
  end
  
  function trans.table(p) -- split up assignments and check if constant table
    local args,nargs,ct,index = p.args,{},{},0
    local const = true
    if #args == 0 then return {type='const', value={}, d=p.d} end
    for _,v in ipairs(args) do
      if v.op == 'assign' then
        local v1 = transform(v.args[1])
        local v2 = transform(v.args[2])
        if v1.type == 'var' then
          const = const and isConst(v2)~=nil 
          nargs[#nargs+1]={'const',v1.name,v2}
        else
          local c1 = isConst(v1)
          const = const and c1~=nil and isConst(v2)~=nil
          if c1 and c1[1]~=nil then nargs[#nargs+1]={'const',c1[1],v2}
          else nargs[#nargs+1]={'comp',v1,v2} end
        end
      else
        index = index+1
        v = transform(v)
        const = const and isConst(v)~=nil
        nargs[#nargs+1]={'const',index,v}
      end
    end
    if const then 
      for _,v in ipairs(nargs) do
        ct[v[2]] = isConst(v[3])[1]
      end
      return {type='const', value=ct, d=p.d}
    end
    return {type='table', value=nargs, d=p.d}
  end
  
  function trans.num(p) return p end
  function trans.str(p) return p end
  function trans.var(p) return p end
  function trans.const(p) return p end
  function trans.forfun(p) return p end
  
  function transform(p)
    if trans[p.type] then return trans[p.type](p) else 
      return p 
    end
  end
  
  local simpTab,simp,simpList = {},nil,nil
  function simpTab.num(v) return v.value end
  function simpTab.str(v) return v.value end
  function simpTab.name(v) return v.value end
  function simpTab.const(v) return tostring(v.value) end
  function simpTab.event(v) return {'ev',v.value} end
  function simpTab.setvar(v) return {'setvar',v.name,simp(v.value)} end
  function simpTab.f_if(v) return {'if',simp(v.cond),simp(v.th),v.els and simp(v.els) or nil} end
  function simpTab.f_while(v) return {'while',simp(v.cond),simp(v.body)} end
  function simpTab.f_repeat(v) return {'repeat',simp(v.cond),simp(v.body)} end
  function simpTab.call(v) return {'call',v.name,simpList(v.args)} end
  function simpTab.callexpr(v) return {'call',simp(v.expr),simpList(v.args)} end
  function simpTab.callobj(v) return {'callobj',simp(v.expr),simpList(v.args)} end
  function simpTab.assign(v) return {'set',simp(v.dest),simp(v.arg)} end
  function simpTab.massign(v) return {'mset',simpList(v.dest),simp(v.arg)} end
  function simpTab.aset(v) return {'aset',simp(v.tab),simp(v.key),simp(v.value)} end
  function simpTab.putprop(v) return {'puprop',simp(v.device),simp(v.key),simp(v.value)} end
  function simpTab.collect(v) return {'collect',simpList(v.args)} end
  function simpTab.op(v)
    local p = simpList(v.args)
    table.insert(p,1,v.op)
    return p
  end
  
  function simp(v) v.d=nil return simpTab[v.type] and simpTab[v.type](v) or v[1] and simpList(v) or v end
  function simpList(l) local r = {}; for _,v in ipairs(l) do r[#r+1]=simp(v) end; return r end
  ER.simplifyParseTree = function (p) return simp(p) end

  function ER:parse(input,options) -- codeStr/tokens -> parseTree
    local tkns,pexpr,sf 
    local source = ""
    currentRule = options.rule
    local stat,res = e_pcall(function() 
      if type(input) == 'string' then
        currentSource = input
        tkns = ER:tokenize(input)
        source = input
      elseif type(input) == 'table' then
        if options.src then source = options.src end
        tkns = input
      else
        error("Parser expected string or token stream")
      end
      currentSource = source

      pexpr = pExpr(tkns,{eof=true})
      pexpr = transform(pexpr)
      if options.simplifyParseTree then pexpr = simp(pexpr) sf=true end
      return pexpr
    end)

    if stat then -- Valid result, return printable table (i.g. parse tree)
      return type(res)=='table' and setmetatable(res,{__tostring=function (t) return encodeFast(t) end}) or res
    else
      local err = res   -- error, return informative error msg
      if not sf and pexpr then -- try to simplify parse tree
        local stat,nexpr = pcall(simp,pexpr) -- but it could crash...
        pexpr = stat and nexpr or pexpr
      end
      if not isErrorMsg(err) then
        local last = tkns.last()
        err = errorMsg{type="Parser",msg=err,from=last.from,to=last.to,src=source,rule=options.rule}
      end
      e_error(err)
    end
  end
  
end