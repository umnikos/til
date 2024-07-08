-- Copyright umnikos (Alex Stefanov) 2024
-- Licensed under MIT license
local version = "0.3"

local function listLength(list)
  local len = 0
  for _,_ in pairs(list) do
    len = len + 1
  end
  return len
end

local function splitIdent(ident)
  local i = string.find(ident,";")
  local nbt = string.sub(ident,i+1)
  local name = string.sub(ident,0,i-1)
  return name,nbt
end

-- returns a list of {name,nbt,count}
local function list(inv)
  local l = {}
  for k,v in pairs(inv.items) do
    local name,nbt = splitIdent(k)
    local count = v.count
    table.insert(l,{name=name,nbt=nbt,count=count})
  end
  return l
end

-- inform the storage of the stack size of an item it has not seen yet
-- DO NOT LIE! (even if it's convenient)
local function informStackSize(inv,name,stacksize)
  inv.stack_sizes[name] = stacksize
end

-- additional amounts of that item the storage is able to store
local function spaceFor(inv,name,nbt)
  -- partial slots
  local stacksize = inv.stack_sizes[name]
  if not stacksize then
    return nil
  end
  local ident = name..";"..(nbt or "")
  local partials = inv.items[ident] or {slots={},slots_nils={}, count = 0}
  local partial_slot_space = listLength(partials.slots)*stacksize - partials.count
  local empty_slot_space = listLength(inv.empty_slots)*stacksize

  return partial_slot_space + empty_slot_space
end

-- amount of a particular item in storage
local function amountOf(inv,name,nbt)
  local ident = name..";"..(nbt or "")
  if not inv.items[ident] then
    return 0
  end
  return inv.items[ident].count
end

-- transfer from one storage to another
local function transfer(inv1,inv2,name,nbt,amount)
  local stacksize = inv1.stack_sizes[name]
  if not stacksize then
    error("Unknown stack size?!?")
  end
  inv2.stack_sizes[name] = stacksize

  local ident = name..";"..(nbt or "")
  inv1.items[ident] = inv1.items[ident] or {count=0,slots={},slots_nils={}}
  inv2.items[ident] = inv2.items[ident] or {count=0,slots={},slots_nils={}}
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
        if #(inv1.empty_slots_nils) == 0 then
          table.insert(inv1.empty_slots,s)
        else
          inv1.empty_slots[inv1.empty_slots_nils[#inv1.empty_slots_nils]] = s
          inv1.empty_slots_nils[#inv1.empty_slots_nils] = nil
        end

        inv1.items[ident].slots[si] = nil
        table.insert(inv1.items[ident].slots_nils, si)
      end

      d.count = d.count + to_transfer
      if di > dlp then
        -- it's not an empty slot now
        if #(inv2.items[ident].slots_nils) == 0 then
          table.insert(inv2.items[ident].slots,d)
        else
          inv2.items[ident].slots[inv2.items[ident].slots_nils[#inv2.items[ident].slots_nils]] = d
          inv2.items[ident].slots_nils[#inv2.items[ident].slots_nils] = nil
        end

        inv2.empty_slots[di-dlp] = nil
        table.insert(inv2.empty_slots_nils, di-dlp)
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
  inv.empty_slots_nils = {}
  -- cache of stack sizes, name -> number
  inv.stack_sizes = {}

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
        inv.items[ident] = inv.items[ident] or {count=0,slots={},slots_nils={}}
        inv.items[ident].count = inv.items[ident].count + count
        table.insert(inv.items[ident].slots,{count=count,chest=cname,slot=i})

        -- inform stack sizes cache if it doesn't know this item
        -- this is slow but it's only done once per item type
        if not inv.stack_sizes[name] then
          inv.stack_sizes[name] = c.getItemDetail(i).maxCount
        end
      end
    end
  end

  -- add methods to the inv
  inv.informStackSize = function(name,stacksize) return informStackSize(inv,name,stacksize) end
  inv.spaceFor = function(name,nbt) return spaceFor(inv,name,nbt) end
  inv.amountOf = function(name,nbt) return amountOf(inv,name,nbt) end
  inv.transfer = function(inv2,name,nbt,amount) return transfer(inv,inv2,name,nbt,amount) end
  inv.list = function() return list(inv) end
  return inv
end




local exports = {
  version=version,
  new=new
}

return exports
