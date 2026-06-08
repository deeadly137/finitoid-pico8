pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- tower defense pico-8: ultimate multiplayer
-- pathfinding inteligente (dijkstra field) e balanceamento calibrado

function _init()
  -- limpa espelhamentos antigos na memoria do mapa
  reload(0x2000, 0x2000, 0x1000) 
  
  state = 0 
  g_mode = 1 
  menu_sel = 1
end

function start_game(mode)
  g_mode = mode
  state = 1
  wave = 0
  wave_act = false
  spawn_cd = 0
  auto_w = false
  
  gold = {100, 100}
  -- buff de ouro inicial para o modo co-op
  if g_mode == 2 then gold[1] = 200 end 
  
  hp = {10, 10}
  
  enemies = {}
  turrets = {}
  bullets = {}
  
  -- listas de tiles importantes separadas por lado (1 = cima, 2 = baixo)
  spawners = {}
  bases = {}
  portals_in = {}
  portals_out = {}
  
  pl = {
    {act=true, cx=64, cy=32, g=1, h=1, m_act=false, m_sel=1},
    {act=false,cx=64, cy=96, g=1, h=1, m_act=false, m_sel=1}
  }
  
  pvp_slots = 5
  pvp_sel = 1
  pvp_cd = 0
  
  if g_mode == 2 then 
    pl[2].act = true 
  elseif g_mode == 3 then
    pl[2].act = true pl[2].g = 2 pl[2].h = 2
    -- correcao: espelha perfeitamente as 8 linhas da metade de cima (0 a 7)
    for x=0,15 do
      for y=0,7 do mset(x, 15-y, mget(x,y)) end
    end
  elseif g_mode == 4 then
    pl[2].act = true 
  end
  
  find_tiles()
  calc_path() -- calcula o mapa de pathfinding inteligente
end

function find_tiles()
  for x=0,15 do
    for y=0,15 do
      local t = mget(x,y)
      -- correcao: divisao simetrica de lados baseada em 8 blocos de altura
      local side = (y < 8) and 1 or 2
      
      -- f2: spawner (apenas f2, sem f0)
      if fget(t,2) and not fget(t,0) then add(spawners, {x=x, y=y, s=side}) end
      -- f3 ou f7: base
      if fget(t,3) or fget(t,7) then add(bases, {x=x, y=y, s=side}) end
      -- f0 e f1: portal de entrada (spr 018)
      if fget(t,0) and fget(t,1) then add(portals_in, {x=x, y=y, s=side}) end
      -- f0 e f2: portal de saida (spr 034)
      if fget(t,0) and fget(t,2) then add(portals_out, {x=x, y=y, s=side}) end
    end
  end
end

-- gera o mapa de fluxo de distancias a partir da base
function calc_path()
  dist_map = {}
  for x=0,15 do
    dist_map[x] = {}
    for y=0,15 do
      dist_map[x][y] = 9999
    end
  end
  
  local q = {}
  -- as bases comecam com distancia 0
  for b in all(bases) do
    dist_map[b.x][b.y] = 0
    add(q, {x=b.x, y=b.y})
  end
  
  local head = 1
  while head <= #q do
    local curr = q[head]
    head += 1
    local cd = dist_map[curr.x][curr.y]
    
    -- se passarmos por um portal de saida, teleportamos a busca para a entrada com penalidade
    for po in all(portals_out) do
      if curr.x == po.x and curr.y == po.y then
        for pi in all(portals_in) do
          if g_mode != 3 or pi.s == po.s then
            local p_dist = cd + 1000 -- penalidade para so usar se nao houver caminho direto
            if p_dist < dist_map[pi.x][pi.y] then
              dist_map[pi.x][pi.y] = p_dist
              add(q, {x=pi.x, y=pi.y})
            end
          end
        end
      end
    end
    
    -- espalha para os 4 vizinhos diretos
    local dirs = {{0,-1},{0,1},{-1,0},{1,0}}
    for d in all(dirs) do
      local nx, ny = curr.x + d[1], curr.y + d[2]
      if nx >= 0 and nx <= 15 and ny >= 0 and ny <= 15 then
        local nt = mget(nx, ny)
        -- verifica se o tile e caminhavel
        if fget(nt,0) or fget(nt,3) or fget(nt,7) then
          local can_m = true
          if g_mode == 3 then
            local c_side = (curr.y < 8) and 1 or 2
            local n_side = (ny < 8) and 1 or 2
            if c_side != n_side then can_m = false end
          end
          
          if can_m then
            if cd + 1 < dist_map[nx][ny] then
              dist_map[nx][ny] = cd + 1
              add(q, {x=nx, y=ny})
            end
          end
        end
      end
    end
  end
end

function get_enemy_hp(e_type)
  local mult = 1.0
  for i=1,wave do mult *= (g_mode==2 and 1.04 or 1.02) end 
  local blocks = flr(wave / 10)
  for i=1,blocks do mult *= 1.20 end
  local hps = {2, 8, 1, 1, 2, 4}
  return max(1, flr(hps[e_type] * mult))
end

-- novo balanceamento de tipos de dano aplicado aqui
-- inimigos: 1=basico, 2=forte, 3=fast, 4=aereo, 5=jet, 6=poison
function get_dmg_mult(t_type, e_type)
  if t_type == 1 then -- torre basica
    if e_type == 1 or e_type == 6 then return 1.5 end
    if e_type == 3 then return 1.0 end
    if e_type == 2 then return 0.5 end
    if e_type == 4 or e_type == 5 then return 0 end
  elseif t_type == 2 then -- sniper
    if e_type == 2 then return 1.5 end
    if e_type == 3 then return 0.25 end
    if e_type == 4 or e_type == 5 then return 0 end
    return 1.0 -- basico (base) e poison
  elseif t_type == 3 then -- multishot
    if e_type == 3 then return 1.5 end
    if e_type == 5 then return 0.5 end
    return 1.0 -- basico (base), poison, aereo e forte
  elseif t_type == 4 then -- antiaereo
    if e_type == 4 then return 1.5 end
    if e_type == 5 then return 1.0 end
    return 0 -- basico, poison, fast e forte
  end
  return 1.0
end

function nxt_wave()
  if not wave_act and #enemies == 0 then
    wave += 1
    local base_amt = 5 + wave + (flr(wave/5)*5)
    e_to_spwn = (g_mode == 2) and (base_amt * 2) or base_amt
    spwn_rate = max(15, 35 - flr(wave/3))
    wave_act = true
    spawn_cd = 0
    if g_mode == 4 then pvp_slots += 5 + (wave * 2) end 
  end
end

function _update60()
  if state == 0 then update_menu() return end
  if hp[1] <= 0 and (g_mode != 3 or hp[2] <= 0) then
    if btnp(5) then _init() end
    return
  end
  
  if btnp(5, 0) then auto_w = not auto_w end
  
  -- 1. controles dos jogadores
  for i=1,2 do
    local p = pl[i]
    if p.act and not (g_mode == 4 and i == 2) then
      local min_y = (g_mode == 3 and i == 2) and 72 or 0
      local max_y = (g_mode == 3 and i == 1) and 48 or 120
      if g_mode != 3 then max_y = 104 end 
      
      local tx, ty = flr(p.cx/8), flr(p.cy/8)
      local ext_t = get_t(tx, ty)
      local tile = mget(tx, ty)
      
      if p.m_act then
        local max_sel = ext_t and 2 or 4
        if btnp(2, i-1) then p.m_sel -= 1 end
        if btnp(3, i-1) then p.m_sel += 1 end
        if p.m_sel < 1 then p.m_sel = max_sel end
        if p.m_sel > max_sel then p.m_sel = 1 end
      else
        if btnp(0, i-1) and p.cx > 0 then p.cx -= 8 end
        if btnp(1, i-1) and p.cx < 120 then p.cx += 8 end
        if btnp(2, i-1) and p.cy > min_y then p.cy -= 8 end
        if btnp(3, i-1) and p.cy < max_y then p.cy += 8 end
      end
      
      if btnp(4, i-1) then
        if p.m_act then
          if not ext_t then
            local costs = {50, 80, 120, 100}
            local c = costs[p.m_sel]
            if gold[p.g] >= c then
              gold[p.g] -= c
              -- atributos calibrados (range do multi de 18 para 25 | anti-aereo com mais cadencia e menos dano base)
              local ranges, rates, dmgs = {28,45,25,40}, {45,90,20,15}, {1,3,2.0,0.6}
              add(turrets, {
                type=p.m_sel, tx=tx, ty=ty, lvl=1, range=ranges[p.m_sel], fire_rate=rates[p.m_sel],
                timer=0, dmg=dmgs[p.m_sel], ang=0, n_cost=flr(c*1.5), spent=c, s=i
              })
              p.m_act = false
            end
          else
            if p.m_sel == 1 and gold[p.g] >= ext_t.n_cost then
              gold[p.g] -= ext_t.n_cost
              ext_t.spent += ext_t.n_cost
              ext_t.lvl += 1
              ext_t.dmg *= 1.25
              ext_t.fire_rate = max(4, flr(ext_t.fire_rate/1.1))
              ext_t.range *= 1.05
              ext_t.n_cost = flr(ext_t.n_cost*1.5)
              p.m_act = false
            elseif p.m_sel == 2 then
              gold[p.g] += flr(ext_t.spent * 0.25)
              del(turrets, ext_t)
              p.m_act = false
            end
          end
        else
          if (fget(tile, 1) and not fget(tile,0)) or ext_t then
            p.m_act = true p.m_sel = 1
          end
        end
      end
      if btnp(5, i-1) and p.m_act then p.m_act = false end
    end
  end
  
  -- 2. modo pvp
  if g_mode == 4 then
    if btnp(0, 1) then pvp_sel = max(1, pvp_sel-1) end
    if btnp(1, 1) then pvp_sel = min(6, pvp_sel+1) end
    if pvp_cd > 0 then pvp_cd -= 1 end
    
    local csts = {1, 3, 2, 2, 3, 4}
    if btnp(4, 1) and pvp_slots >= csts[pvp_sel] and pvp_cd <= 0 then
      pvp_slots -= csts[pvp_sel]
      pvp_cd = 30
      spawn_enm(pvp_sel, 1) 
    end
  end

  -- 3. spawn do jogo natural
  if wave_act then
    if e_to_spwn > 0 then
      spawn_cd -= 1
      if spawn_cd <= 0 then
        local c_type = 1
        if wave > 2 then c_type = flr(rnd(3))+1 end
        if wave > 5 then c_type = flr(rnd(6))+1 end
        
        if g_mode == 3 then
          spawn_enm(c_type, 1) spawn_enm(c_type, 2)
        else spawn_enm(c_type, 1) end
        
        e_to_spwn -= 1 spawn_cd = spwn_rate
      end
    elseif #enemies == 0 then wave_act = false end
  else
    if auto_w and #enemies == 0 then nxt_wave() end
  end
  
  -- 4. inimigos e pathfinding inteligente com dijkstra field
  for e in all(enemies) do
    if e.dist <= 0 then
      e.x = flr(e.x/8 + 0.5) * 8
      e.y = flr(e.y/8 + 0.5) * 8
      local etx, ety = flr(e.x/8), flr(e.y/8)
      
      -- verifica se pisou em um portal de entrada para teletransporte imediato
      for pi in all(portals_in) do
        if (g_mode != 3 or pi.s == e.s) and etx == pi.x and ety == pi.y then
          for po in all(portals_out) do
            if g_mode != 3 or po.s == e.s then
              e.x = po.x * 8
              e.y = po.y * 8
              etx = po.x
              ety = po.y
              e.ldx = 0
              e.ldy = 0
              break
            end
          end
        end
      end
      
      -- chegou na base
      for b in all(bases) do
        if (g_mode != 3 or b.s == e.s) and etx == b.x and ety == b.y then
          hp[e.s] -= 1
          if g_mode == 4 and e.s == 1 then pvp_slots += 2 end
          del(enemies, e)
          goto nxt_e
        end
      end
      
      -- escolhe o proximo passo baseando-se no menor valor do dist_map
      local bdx, bdy, mdst = 0, 0, 9999
      local dirs = {{0,-1},{0,1},{-1,0},{1,0}}
      
      for d in all(dirs) do
        local nx, ny = etx + d[1], ety + d[2]
        if nx >= 0 and nx <= 15 and ny >= 0 and ny <= 15 then
          local nt = mget(nx, ny)
          
          if fget(nt,0) or fget(nt,3) or fget(nt,7) then
            -- evita andar para tras para manter a fluidez do caminho
            if d[1] != -e.ldx or d[2] != -e.ldy then
              local dist = dist_map[nx][ny]
              if dist < mdst then 
                mdst = dist 
                bdx = d[1] 
                bdy = d[2] 
              end
            end
          end
        end
      end
      
      -- se ficar encurralado por nao poder voltar (ajuste de curvas fechadas), permite retroceder
      if bdx == 0 and bdy == 0 then
        for d in all(dirs) do
          local nx, ny = etx + d[1], ety + d[2]
          if nx >= 0 and nx <= 15 and ny >= 0 and ny <= 15 then
            local nt = mget(nx, ny)
            if fget(nt,0) or fget(nt,3) or fget(nt,7) then
              local dist = dist_map[nx][ny]
              if dist < mdst then
                mdst = dist
                bdx = d[1]
                bdy = d[2]
              end
            end
          end
        end
      end
      
      e.dx = bdx 
      e.dy = bdy
      if bdx != 0 or bdy != 0 then e.ldx = bdx e.ldy = bdy end
      e.dist = 8
    end
    
    e.x += e.dx * e.speed 
    e.y += e.dy * e.speed 
    e.dist -= e.speed
    
    if e.hp <= 0 then
      local g_id = (g_mode == 3) and e.s or 1
      local gold_drop = flr(rnd(5))+1
      if g_mode == 2 then gold_drop *= 2 end 
      
      gold[g_id] += gold_drop
      del(enemies, e)
    end
    
    ::nxt_e::
  end
  
  -- 5. torres e balas
  for t in all(turrets) do
    t.timer -= 1
    local tgt, c_dist = nil, t.range
    for e in all(enemies) do
      if (g_mode != 3) or (t.s == e.s) then
        if get_dmg_mult(t.type, e.type) > 0 then
          local dx, dy = (e.x+4)-(t.tx*8+4), (e.y+4)-(t.ty*8+4)
          local dist = sqrt(dx*dx + dy*dy)
          if dist < c_dist then c_dist = dist tgt = e end
        end
      end
    end
    
    if tgt then
      t.ang = atan2((tgt.x+4)-(t.tx*8+4), (tgt.y+4)-(t.ty*8+4))
      if t.timer <= 0 then
        if t.type == 3 then
          local n_b, ang_s = 5, 55/360
          if t.lvl>=4 then n_b+=1 end
          if t.lvl>=7 then n_b+=1 ang_s-=5/360 end
          if t.lvl>=10 then n_b+=2 end
          if t.lvl>=15 then n_b+=6 ang_s-=10/360 end
          
          local st_a = t.ang - (ang_s/2)
          local stp = n_b>1 and (ang_s/(n_b-1)) or 0
          for i=0,n_b-1 do
            local ba = st_a + (i*stp)
            -- mudanca: o dano total da torre e dividido pela quantidade de balas disparadas (t.dmg/n_b)
            -- mudanca: adicionado o parametro max_d limitando o alcance a no maximo 125% da range atual
            add(bullets, {
              x=t.tx*8+4, y=t.ty*8+4, 
              tx=(t.tx*8+4)+cos(ba)*100, ty=(t.ty*8+4)+sin(ba)*100, 
              dmg=t.dmg/n_b, spd=4, t_type=3, max_d=t.range*1.25
            })
          end
        else
          add(bullets, {x=t.tx*8+4, y=t.ty*8+4, tx=tgt.x+4, ty=tgt.y+4, dmg=t.dmg, spd=4, t_type=t.type})
        end
        t.timer = t.fire_rate
      end
    end
  end
  
  for b in all(bullets) do
    local dx, dy = b.tx - b.x, b.ty - b.y
    local dist = sqrt(dx*dx + dy*dy)
    
    if dist < 3 and b.t_type != 3 then
      for e in all(enemies) do
        if abs(e.x+4-b.x)<6 and abs(e.y+4-b.y)<6 then
          local mult = get_dmg_mult(b.t_type, e.type)
          if mult > 0 then e.hp -= (b.dmg * mult) end
        end
      end
      del(bullets, b)
    elseif b.t_type == 3 then
      local hit = false
      for e in all(enemies) do
        if abs(e.x+4-b.x)<5 and abs(e.y+4-b.y)<5 then
          local mult = get_dmg_mult(b.t_type, e.type)
          if mult>0 then e.hp -= (b.dmg*mult) hit = true end
        end
      end
      
      -- atualiza e consome a distancia limite do projetil do multi (125% do range)
      b.max_d -= b.spd
      if hit or b.max_d <= 0 or b.x<0 or b.x>128 or b.y<0 or b.y>128 then 
        del(bullets, b)
      else 
        b.x += (dx/dist)*b.spd b.y += (dy/dist)*b.spd 
      end
    else
      b.x += (dx/dist)*b.spd b.y += (dy/dist)*b.spd
    end
  end
end

function spawn_enm(c_type, side)
  local sps = {}
  for s in all(spawners) do 
    if g_mode != 3 or s.s == side then add(sps, s) end 
  end
  if #sps == 0 then return end
  local sp = sps[flr(rnd(#sps))+1]
  
  local h = get_enemy_hp(c_type)
  local sprts = {3,19,20,35,36,51}
  local spds = {0.5, 0.25, 0.75, 0.6, 1.0, 0.4}
  
  add(enemies, {
    type=c_type, x=sp.x*8, y=sp.y*8, hp=h, max_hp=h, speed=spds[c_type],
    dx=0, dy=0, ldx=0, ldy=0, spr=sprts[c_type], dist=0, s=side
  })
end

function get_t(tx, ty)
  for t in all(turrets) do if t.tx==tx and t.ty==ty then return t end end
  return nil
end

function update_menu()
  if btnp(2) then menu_sel = max(1, menu_sel-1) end
  if btnp(3) then menu_sel = min(4, menu_sel+1) end
  if btnp(4) or btnp(5) then start_game(menu_sel) end
end

function _draw()
  cls(0)
  if state == 0 then
    print("pico-8 tower defense", 24, 20, 11)
    print((menu_sel==1 and ">" or " ").."1. singleplayer", 30, 50, 7)
    print((menu_sel==2 and ">" or " ").."2. co-op (2p)", 30, 60, 12)
    print((menu_sel==3 and ">" or " ").."3. versus (2p split)", 30, 70, 8)
    print((menu_sel==4 and ">" or " ").."4. pvp (2p as enemy)", 30, 80, 9)
    print("x ou z para comecar", 26, 110, 5)
    return
  end

  map(0,0,0,0,16,16)
  
  for e in all(enemies) do
    spr(e.spr, e.x, e.y, 1, 1, e.ldx<0)
    rectfill(e.x, e.y-2, e.x+7, e.y-1, 8)
    rectfill(e.x, e.y-2, e.x+flr((e.hp/e.max_hp)*7), e.y-1, 11)
  end
  
  for t in all(turrets) do
    local sprs = {6, 22, 38, 54}
    spr(sprs[t.type], t.tx*8, t.ty*8)
    spr(sprs[t.type]+1, t.tx*8+cos(t.ang)*2, t.ty*8+sin(t.ang)*2)
    print("l"..t.lvl, t.tx*8+1, t.ty*8-6, 7)
  end
  
  for b in all(bullets) do circfill(b.x, b.y, 1, 10) end
  
  -- hud
  if g_mode == 3 then
    rectfill(0, 56, 128, 71, 0) line(0, 56, 128, 56, 7) line(0, 71, 128, 71, 7)
    print("p1 g:"..gold[1].." hp:"..hp[1], 2, 59, 9)
    print("p2 g:"..gold[2].." hp:"..hp[2], 2, 65, 12)
    print("wv:"..wave, 80, 59, 7)
    if not wave_act then print("btn x", 80, 65, 5) end
    if hp[1] <= 0 then print("p2 win", 100, 62, 10) end
    if hp[2] <= 0 then print("p1 win", 100, 62, 10) end
  else
    rectfill(0, 112, 128, 128, 0) line(0, 112, 128, 112, 7)
    print("g:"..gold[1].." hp:"..hp[1], 2, 115, 10)
    print("wv:"..wave, 50, 115, 7)
    if not wave_act then print("nxt", 50, 122, 12) end
    if auto_w then print("auto", 70, 115, 11) end
    
    if g_mode == 4 then
      print("p2 slots:"..pvp_slots, 80, 115, 12)
      local csts = {1, 3, 2, 2, 3, 4}
      print("sel:"..pvp_sel.." cst:"..csts[pvp_sel], 80, 122, 8)
    end
  end
  
  -- visual menu (z-index)
  local c_colors = {9, 12}
  for i=1,2 do
    local p = pl[i]
    if p.act and not (g_mode==4 and i==2) then
      local ht = get_t(flr(p.cx/8), flr(p.cy/8))
      if ht then circ(ht.tx*8+4, ht.ty*8+4, ht.range, c_colors[i]) end
      rect(p.cx, p.cy, p.cx+7, p.cy+7, c_colors[i])
      
      if p.m_act then
        local mx, my = p.cx, p.cy
        if mx > 80 then mx = 80 end
        
        local my1
        if i == 1 then
           my1 = my + 10 
           if g_mode == 3 and my1 > 12 then my1 = 12 end 
        else
           my1 = my - 44 
           if g_mode == 3 and my1 < 76 then my1 = 76 end 
        end

        if not ht then
          rectfill(mx-4, my1, mx+44, my1+42, 0) 
          rect(mx-4, my1, mx+44, my1+42, c_colors[i])
          print((p.m_sel==1 and ">" or " ").."t1: 50g", mx-2, my1+4, 11)
          print((p.m_sel==2 and ">" or " ").."t2: 80g", mx-2, my1+14, 14)
          print((p.m_sel==3 and ">" or " ").."t3: 120g",mx-2, my1+24, 9)
          print((p.m_sel==4 and ">" or " ").."t4: 100g",mx-2, my1+34, 12)
        else
          rectfill(mx-4, my1, mx+44, my1+22, 0) 
          rect(mx-4, my1, mx+44, my1+22, c_colors[i])
          print((p.m_sel==1 and ">" or " ").."up: "..ht.n_cost.."g", mx-2, my1+4, 12)
          print((p.m_sel==2 and ">" or " ").."sell: "..flr(ht.spent*0.25).."g", mx-2, my1+14, 10)
        end
      end
    end
  end
  
  if (hp[1] <= 0 and g_mode != 3) or (g_mode == 3 and hp[1]<=0 and hp[2]<=0) then
    rectfill(20, 50, 108, 78, 0) rect(20, 50, 108, 78, 8)
    print("game over", 46, 56, 8)
    print("waves: "..wave, 48, 66, 7)
  end
end
__gfx__
0000000066666666dddddddd00000000dddddddddddddddd00000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000065555551dddddddd00033000dd12222dddc11cdd0cccccc000000000000aa00000000000000000000000000000000000000000000000000000000000
0070070065555551dddddddd003bb300d12e888ddccccccd0c1111c000ccc1000099a90000a99a00000000000000000000000000000000000000000000000000
0007700065555551dddddddd03bbbb30d2e1221dd1c11c1d0c1ccdc000c11d000a9a9a900099a900000000000000000000000000000000000000000000000000
0007700065555551dddddddd03bbbb30d2828e2dd1c11c1d0c1ccdc000111d000aa99aa0009aa900000000000000000000000000000000000000000000000000
0070070065555551dddddddd003bb300d281282ddccccccd0c1dddc0001ddd00009aaa0000a99900000000000000000000000000000000000000000000000000
0000000065555551dddddddd00033000d128821dddc11cdd0cccccc0000000000009a00000000000000000000000000000000000000000000000000000000000
0000000061111111dddddddd00000000dd1221dddddddddd00000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000dd888ddd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000d88188dd0222222000099000000000000003b000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000d811188d0288882000099000000000000003b000003003000000000000000000000000000000000000000000000000000000000000000000
0000000000000000d811118d02888820009aa90000000000003bbb0000333b000000000000000000000000000000000000000000000000000000000000000000
0000000000000000d811118d02888820009aa90000000000003bbb000003b0000000000000000000000000000000000000000000000000000000000000000000
0000000000000000d881118d0288882009aaaa900000000003bbbbb000b00b000000000000000000000000000000000000000000000000000000000000000000
0000000000000000dd8118dd02222220099999900000000003333330000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000ddd888dd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000dddccddd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000ddc11ccd000cc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000dcc111cd00c101000001c0000000000009aaaaa0000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000dc1111cd011cc0c00001c0000000000009aaaaa00009a0000000000000000000000000000000000000000000000000000000000000000000
0000000000000000dc1111cd0101c1c0001ccc0000000000009aaa00000a90000000000000000000000000000000000000000000000000000000000000000000
0000000000000000dcc111cd00101c00001ccc00000000000099aa00000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000ddcc1ccd0001100001111110000000000009a000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000dddcccdd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000cc000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000003b000000000000000000000c11c00000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000003bbb0000000000000000000c11cdc00011cc000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000033bbbb000000000000000000c1ccdc000cc11000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000003300bb0000000000000000000cddc00000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000030000b00000000000000000000cc000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
00020180040800000000000000000000000003c0a0000000000000000000000000000590b000000000000000000000000000008800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0005020000010202020202000102000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000020100011200010002020202010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002020001010001000002010401002200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002010002020202020102010200000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002020102000101040002000201010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001020102010001000102010202010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002020002020202020202000002020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002000100010100010000000101010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002020202020202020202020202020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
