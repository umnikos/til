local version = "0.1"

local function listLength(list)
  local len = 0
  for _,_ in pairs(list) do
    len = len + 1
  end
  return len
end

local function spaceFor(inv,name,nbt,stacksize)
  -- partial slots
  stacksize = stacksize or 64
  local ident = name..";"..(nbt or "")
  local partials = inv.items[ident] or {slots={}, count = 0}
  local partial_slot_space = listLength(partials.slots)*stacksize - partials.count
  local empty_slot_space = listLength(inv.empty_slots)*stacksize

  return partial_slot_space + empty_slot_space
end

local function amountOf(inv,name,nbt)
  local ident = name..";"..(nbt or "")
  return inv.items[ident].count
end

local function transfer(inv1,inv2,name,nbt,amount,stacksize)
  stacksize = stacksize or 64
  local ident = name..";"..(nbt or "")
  inv1.items[ident] = inv1.items[ident] or {count=0,slots={}}
  inv2.items[ident] = inv2.items[ident] or {count=0,slots={}}
  local sources = inv1.items[ident].slots
  local sl = #sources -- intentionally take incorrect length to take into account nils
  local dests_partial = inv2.items[ident].slots
  local dlp = #dests_partial
  local dests_empty = inv2.empty_slots
  local dle = #dests_empty

  local si = 1
  local di = 1
  local transferred = 0
  while amount > 0 and si <= sl and di <= (dlp+dle) do
    local s = sources[si]
    local d
    if di <= dlp then d = dests_partial[di] else d = dests_empty[di] end

    if not s or s.count <= 0 then
      si = si + 1
    elseif not d or d.count >= stacksize then
      di = di + 1
    else
      local to_transfer = math.min(amount, s.count, stacksize-d.count)
      peripheral.wrap(s.chest).pushItems(d.chest,s.slot,to_transfer,d.slot)
      -- we can just assume this is what happened
      transferred = transferred + to_transfer
      amount = amount - to_transfer
      s.count = s.count - to_transfer
      inv1.items[ident].count = inv1.items[ident].count - to_transfer
      if s.count == 0 then
        -- it's an empty slot now
        table.insert(inv1.empty_slots,s)
        inv1.items[ident].slots[si] = nil
      end

      d.count = d.count + to_transfer
      if di > dlp then
        -- it's not an empty slot now
        table.insert(inv2.items[ident].slots,d)
        inv2.empty_slots[di-dlp] = nil
      end
      inv2.items[ident].count = inv2.items[ident].count + to_transfer
    end
  end
  return transferred
end


-- create an inv object out of a list of chests
local function new(chests)
  local inv = {}
  -- list of chest names
  inv.chests = chests
  -- name;nbt -> total item count + list of slots with counts
  inv.items = {}
  -- list of empty slots
  inv.empty_slots = {}

  for _,cname in pairs(chests) do
    local c = peripheral.wrap(cname)
    local l = c.list()
    local size = c.size()
    for i = 1,size do
      local item = l[i]
      if not item then
        -- empty slot
        table.insert(inv.empty_slots,{count=0,chest=cname,slot=i})
      else
        -- slot with an item
        local nbt = item.nbt or ""
        local name = item.name
        local count = item.count
        local ident = name..";"..nbt -- identifier
        inv.items[ident] = inv.items[ident] or {count=0,slots={}}
        inv.items[ident].count = inv.items[ident].count + count
        table.insert(inv.items[ident].slots,{count=count,chest=cname,slot=i})
      end
    end
  end

  -- add methods to the inv
  inv.spaceFor = function(name,nbt,stacksize) return spaceFor(inv,name,nbt,stacksize) end
  inv.amountOf = function(name,nbt) return amountOf(inv,name,nbt) end
  inv.transfer = function(inv2,name,nbt,amount,stacksize) return transfer(inv,inv2,name,nbt,amount,stacksize) end
  return inv
end




local exports = {
  version=version,
  new=new
}

return exports
