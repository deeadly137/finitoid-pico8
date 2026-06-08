pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- tower defense pico-8

function _init()
  gold = 500
  base_hp = 10
  wave = 0
  wave_active = false
  wave_timer = 0
  enemies_to_spawn = 0
  spawn_cooldown = 0
  current_spawn_rate = 40
  auto_wave = false
  
  enemies = {}
  turrets = {}
  bullets = {}
  
  cx = 64
  cy = 64
  
  menu_active = false
  selected_tile_x = 0
  selected_tile_y = 0
  menu_selection = 1 
  
  -- coordenadas dos portais (-1 significa nao encontrado ainda)
  portal_in_x = -1 portal_in_y = -1
  portal_out_x = -1 portal_out_y = -1
  
  find_special_tiles()
end

function find_special_tiles()
  spawn_x = 0 spawn_y = 0 base_x = 0 base_y = 0
  for x=0,15 do
    for y=0,15 do
      local t = mget(x,y)
      
      -- verifica os portais combinando as flags com a flag 0 (caminho)
      if fget(t, 0) and fget(t, 1) then
        portal_in_x = x portal_in_y = y -- entrada (f0+f1)
      elseif fget(t, 0) and fget(t, 2) then
        portal_out_x = x portal_out_y = y -- saida (f0+f2)
      elseif fget(t, 2) then 
        spawn_x = x*8 spawn_y = y*8 -- spawn padrao (apenas f2)
      end
      
      if fget(t, 3) then base_x = x base_y = y end
    end
  end
end

function get_enemy_max_hp(enemy_type)
  local multiplier = 1.0
  for i=1,wave do multiplier *= 1.02 end
  local blocks_of_10 = flr(wave / 10)
  for i=1,blocks_of_10 do multiplier *= 1.20 end
  
  local hps = {2, 8, 1, 1, 2, 4} -- 1=base, 2=strong, 3=fast, 4=fly, 5=jet, 6=poison
  return max(1, flr(hps[enemy_type] * multiplier))
end

function get_dmg_mult(t_type, e_type)
  if t_type == 1 then -- base
    if e_type == 4 or e_type == 5 then return 0 end
    if e_type == 6 or e_type == 1 then return 1.5 end
    if e_type == 2 then return 0.5 end
    return 1.0
  elseif t_type == 2 then -- sniper
    if e_type == 4 or e_type == 5 then return 0 end
    if e_type == 2 then return 1.5 end
    if e_type == 3 then return 0.25 end
    return 1.0
  elseif t_type == 3 then -- multi
    if e_type == 2 then return 0 end
    if e_type == 3 then return 1.5 end
    if e_type == 5 then return 0.5 end
    return 1.0
  elseif t_type == 4 then -- anti-aereo
    if e_type == 4 then return 1.5 end
    if e_type == 5 then return 1.0 end
    return 0
  end
  return 1.0
end

function start_next_wave()
  if not wave_active and #enemies == 0 and enemies_to_spawn == 0 then
    wave += 1
    enemies_to_spawn = 5 + wave + (flr(wave / 5) * 5)
    current_spawn_rate = max(15, 35 - flr(wave/3)) 
    wave_active = true
    spawn_cooldown = 0
  end
end

------------------------------------------------
-- atualizacao (update)
------------------------------------------------

function _update60()
  if base_hp <= 0 then return end
  
  local tx = flr(cx/8)
  local ty = flr(cy/8)
  local tile = mget(tx, ty)
  local existing_turret = get_turret_at(tx, ty)
  
  if btnp(5) and not menu_active then
    auto_wave = not auto_wave
  end
  
  -- 1. controle do cursor e menu
  if menu_active then
    local max_selections = existing_turret and 2 or 4
    if btnp(2) then menu_selection -= 1 end 
    if btnp(3) then menu_selection += 1 end 
    if menu_selection < 1 then menu_selection = max_selections end
    if menu_selection > max_selections then menu_selection = 1 end
  else
    if btnp(0) and cx > 0 then cx -= 8 end
    if btnp(1) and cx < 120 then cx += 8 end
    if btnp(2) and cy > 0 then cy -= 8 end
    if btnp(3) and cy < 120 then cy += 8 end
  end
  
  -- 2. logica de clique e upgrades/venda
  if btnp(4) then
    if cy >= 112 and cx >= 64 and cx <= 120 and not menu_active then
      start_next_wave()
    elseif menu_active then
      if not existing_turret then
        local costs = {50, 80, 120, 100}
        local cost = costs[menu_selection]
        if gold >= cost then
          gold -= cost
          local ranges = {28, 45, 24, 40}
          local rates = {45, 90, 20, 30}
          local dmgs = {1, 3, 0.5, 2}
          
          add(turrets, {
            type=menu_selection, tx=selected_tile_x, ty=selected_tile_y, 
            lvl=1, range=ranges[menu_selection], fire_rate=rates[menu_selection], 
            timer=0, base_dmg=dmgs[menu_selection], angle=0, 
            next_cost=flr(cost*1.5), total_spent=cost
          })
          menu_active = false
        end
      else
        if menu_selection == 1 then
          if gold >= existing_turret.next_cost then
            gold -= existing_turret.next_cost
            existing_turret.total_spent += existing_turret.next_cost
            existing_turret.lvl += 1
            existing_turret.base_dmg *= 1.25
            existing_turret.fire_rate = max(4, flr(existing_turret.fire_rate / 1.1)) 
            existing_turret.range *= 1.05 
            existing_turret.next_cost = flr(existing_turret.next_cost * 1.5)
            menu_active = false
          end
        elseif menu_selection == 2 then
          gold += flr(existing_turret.total_spent * 0.25)
          del(turrets, existing_turret)
          menu_active = false
        end
      end
    else
      if (fget(tile, 1) and not fget(tile, 0)) or existing_turret then
        menu_active = true
        selected_tile_x = tx
        selected_tile_y = ty
        menu_selection = 1
      end
    end
  end
  
  if btnp(5) and menu_active then menu_active = false end
  
  -- 3. controle de spawn
  if wave_active then
    if enemies_to_spawn > 0 then
      spawn_cooldown -= 1
      if spawn_cooldown <= 0 then
        local chosen_type = 1 
        if wave > 2 then chosen_type = flr(rnd(3)) + 1 end
        if wave > 5 then chosen_type = flr(rnd(6)) + 1 end
        
        local h = get_enemy_max_hp(chosen_type)
        local sprs = {3, 19, 20, 35, 36, 51}
        local speeds = {0.5, 0.25, 0.75, 0.6, 1.0, 0.4}
        
        add(enemies, {
          type=chosen_type, x=spawn_x, y=spawn_y, hp=h, max_hp=h, 
          speed=speeds[chosen_type], dx=0, dy=0, ldx=-1, ldy=0, 
          spr=sprs[chosen_type], last_hit=0,
          dist=0 -- novo: controla quando ele deve decidir curvar
        })
        
        enemies_to_spawn -= 1
        spawn_cooldown = current_spawn_rate
      end
    elseif #enemies == 0 then
      wave_active = false
    end
  else
    if auto_wave and #enemies == 0 and enemies_to_spawn == 0 then
      start_next_wave()
    end
  end
  
  -- 4. mover inimigos e habilidades
  for e in all(enemies) do
    
    -- novo: em vez de verificar modulo de 8, verifica se andou 8 pixels
    if e.dist <= 0 then
      
      -- encaixa perfeitamente no grid para limpar as casas decimais (ex: 8.25 vira 8.0)
      e.x = flr(e.x/8 + 0.5) * 8
      e.y = flr(e.y/8 + 0.5) * 8
      
      local etx = flr(e.x / 8)
      local ety = flr(e.y / 8)
      
      -- logica do teletransporte (portal)
      if etx == portal_in_x and ety == portal_in_y then
        e.x = portal_out_x * 8
        e.y = portal_out_y * 8
        etx = portal_out_x
        ety = portal_out_y
        e.ldx = 0 e.ldy = 0 
      end
      
      if etx == base_x and ety == base_y then
        base_hp -= 1 
        del(enemies, e)
        goto next_enemy
      end
      
      local best_dx, best_dy = 0, 0
      local min_dist = 9999
      local dirs = {{0,-1},{0,1},{-1,0},{1,0}}
      
      for d in all(dirs) do
        local nx = etx + d[1]
        local ny = ety + d[2]
        local nt = mget(nx, ny)
        if fget(nt, 0) or fget(nt, 3) then
          if d[1] != -e.ldx or d[2] != -e.ldy then
            local dist = abs(nx - base_x) + abs(ny - base_y)
            if dist < min_dist then
              min_dist = dist; best_dx = d[1]; best_dy = d[2]
            end
          end
        end
      end
      e.dx = best_dx e.dy = best_dy
      if best_dx != 0 or best_dy != 0 then e.ldx = best_dx e.ldy = best_dy end
      
      -- reseta a distれけncia para o prれはximo bloco
      e.dist = 8 
    end
    
    -- movimentaれせれこo normal
    e.x += e.dx * e.speed 
    e.y += e.dy * e.speed
    e.dist -= e.speed -- subtrai a velocidade da distれけncia restante
    
    if e.type == 6 then
      e.last_hit += 1
      if e.last_hit > 60 then 
        if e.last_hit % 30 == 0 then 
           e.hp = min(e.hp + (e.max_hp * 0.05), e.max_hp)
        end
      end
    end
    
    if e.hp <= 0 then 
      gold += flr(rnd(5)) + 1 
      del(enemies, e) 
    end
    ::next_enemy::
  end
  
  -- 5. logica das torres e miras
  for t in all(turrets) do
    t.timer -= 1
    local target = nil
    local closest_dist = t.range
    
    for e in all(enemies) do
      if get_dmg_mult(t.type, e.type) > 0 then
        local dx = (e.x+4) - (t.tx*8+4)
        local dy = (e.y+4) - (t.ty*8+4)
        local dist = sqrt(dx*dx + dy*dy)
        if dist < closest_dist then
          closest_dist = dist
          target = e
        end
      end
    end
    
    if target then
      local dx = (target.x+4) - (t.tx*8+4)
      local dy = (target.y+4) - (t.ty*8+4)
      t.angle = atan2(dx, dy)
      
      if t.timer <= 0 then
        add(bullets, {x=t.tx*8+4, y=t.ty*8+4, tx=target.x+4, ty=target.y+4, base_dmg=t.base_dmg, speed=4, t_type=t.type})
        t.timer = t.fire_rate
      end
    end
  end
  
  -- 6. mover projeteis e calcular dano
  for b in all(bullets) do
    local dx = b.tx - b.x
    local dy = b.ty - b.y
    local dist = sqrt(dx*dx + dy*dy)
    if dist < 3 then
      for e in all(enemies) do
        if abs(e.x+4 - b.x) < 6 and abs(e.y+4 - b.y) < 6 then
          local mult = get_dmg_mult(b.t_type, e.type)
          if mult > 0 then
            e.hp -= (b.base_dmg * mult)
            e.last_hit = 0 
          end
        end
      end
      del(bullets, b)
    else
      b.x += (dx/dist) * b.speed
      b.y += (dy/dist) * b.speed
    end
  end
end

------------------------------------------------
-- renderizacao (draw)
------------------------------------------------

function _draw()
  cls(0)
  map(0,0,0,0,16,16)
  
  for e in all(enemies) do
    local is_flipped = e.ldx < 0
    spr(e.spr, e.x, e.y, 1, 1, is_flipped)
    rectfill(e.x, e.y-2, e.x+7, e.y-1, 8)
    rectfill(e.x, e.y-2, e.x+flr((e.hp/e.max_hp)*7), e.y-1, 11)
  end
  
  for t in all(turrets) do
    local sprs = {6, 22, 38, 54}
    local base_spr = sprs[t.type]
    local cano_spr = base_spr + 1
    
    spr(base_spr, t.tx*8, t.ty*8)
    
    local ox = cos(t.angle) * 2
    local oy = sin(t.angle) * 2
    spr(cano_spr, t.tx*8+ox, t.ty*8+oy)
    
    print("l"..t.lvl, t.tx*8+1, t.ty*8-6, 7)
  end
  
  local hover_turret = get_turret_at(flr(cx/8), flr(cy/8))
  if hover_turret then
    circ(hover_turret.tx*8+4, hover_turret.ty*8+4, hover_turret.range, 13)
  end
  
  for b in all(bullets) do circfill(b.x, b.y, 1, 10) end
  rect(cx, cy, cx+7, cy+7, 9)
  
  -- hud inferior
  rectfill(0, 112, 128, 128, 0)
  line(0, 112, 128, 112, 7)
  print("oro:"..gold, 2, 115, 10)
  print("hp:"..base_hp, 2, 122, 8)
  print("on:"..wave, 40, 115, 7)
  
  if auto_wave then print("auto:on", 40, 122, 11)
  else print("auto:off", 40, 122, 5) end
  
  if not wave_active then
    rectfill(68, 115, 124, 125, 2)
    rect(68, 115, 124, 125, 7)
    print("nxt wave", 74, 118, 12)
  else
    print("onda viva", 74, 118, 8)
  end
  
  if menu_active then
    local mx = selected_tile_x * 8
    local my = selected_tile_y * 8
    if (mx > 80) mx = 80
    if (my < 48) my = 48 
    
    local t = get_turret_at(selected_tile_x, selected_tile_y)
    if not t then
      rectfill(mx-4, my-44, mx+44, my-2, 5)
      rect(mx-4, my-44, mx+44, my-2, 7)
      
      print((menu_selection == 1 and ">" or " ").."t1(bas): 50g", mx-2, my-40, 11)
      print((menu_selection == 2 and ">" or " ").."t2(snp): 80g", mx-2, my-30, 14)
      print((menu_selection == 3 and ">" or " ").."t3(mul): 120g",mx-2, my-20, 9)
      print((menu_selection == 4 and ">" or " ").."t4(ant): 100g",mx-2, my-10, 12)
    else
      rectfill(mx-4, my-24, mx+44, my-2, 5)
      rect(mx-4, my-24, mx+44, my-2, 7)
      
      print((menu_selection == 1 and ">" or " ").."up: "..t.next_cost.."g", mx-2, my-20, 12)
      print((menu_selection == 2 and ">" or " ").."vender: "..flr(t.total_spent*0.25).."g", mx-2, my-10, 10)
    end
  end
  
  if base_hp <= 0 then
    rectfill(16, 40, 112, 80, 0)
    rect(16, 40, 112, 80, 8)
    print("game over", 46, 52, 8)
    print("ondas defendidas: "..wave, 24, 64, 7)
  end
end

function get_turret_at(tx, ty)
  for t in all(turrets) do
    if t.tx == tx and t.ty == ty then return t end
  end
  return nil
end
__gfx__
0000000066666666dddddddd00000000dddddddddddddddd00000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000065555551dddddddd00033000dd12222dddc11cdd0cccccc0000000000000000000000000000000000000000000000000000000000000000000000000
0070070065555551dddddddd003bb300d12e888ddccccccd0c1111c000ccc1000000000000000000000000000000000000000000000000000000000000000000
0007700065555551dddddddd03bbbb30d2e1221dd1c11c1d0c1ccdc000c11d000000000000000000000000000000000000000000000000000000000000000000
0007700065555551dddddddd03bbbb30d2828e2dd1c11c1d0c1ccdc000111d000000000000000000000000000000000000000000000000000000000000000000
0070070065555551dddddddd003bb300d281282ddccccccd0c1dddc0001ddd000000000000000000000000000000000000000000000000000000000000000000
0000000065555551dddddddd00033000d128821dddc11cdd0cccccc0000000000000000000000000000000000000000000000000000000000000000000000000
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
00000000000000000000000000033000000000000000000000c11c00000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000003bbb0000000000000000000c11cdc00011cc000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000003bbb0000000000000000000c1ccdc000cc11000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000333b00000000000000000000cddc00000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000cc000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
00020180040800000000000000000000000003c0a0000000000000000000000000000590b000000000000000000000000000008800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0005010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002000000000000000000000001220100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002010000000000000000000001020100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002010000000000000000000001020100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0102010101010101010101010101020100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002020202020202020202020202020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001010000010101010101010000010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0400010000000001000100000212000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0202020202020202020202020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
