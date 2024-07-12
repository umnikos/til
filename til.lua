-- Copyright umnikos (Alex Stefanov) 2024
-- Licensed under MIT license
local version = "0.11"

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
  if not inv2.items[ident] then
    -- new kind of item to accept
    inv2.items[ident] = {count=0, slots={}, slots_nils={}}
  end
  local dests_partial = inv2.items[ident].slots
  local dlp = #dests_partial
  local dests_empty = inv2.empty_slots
  local dle = #dests_empty

  local si = sl
  local di = 1
  local transferred = 0
  local s
  local d
  while amount > 0 and si >= 1 and di <= (dlp+dle) do
    if not s then
      s = sources[si]
    end
    if not d then
      if di <= dlp then 
        d = dests_partial[di]
      else
        d = dests_empty[dle-(di-dlp)+1]
      end
    end

    if not s or s.count <= 0 then
      si = si - 1
      s = nil
    elseif not d or d.count >= stacksize then
      di = di + 1
      d = nil
    else
      local to_transfer = math.min(amount, s.count, stacksize-d.count)
      local real_transfer = peripheral.wrap(s.chest).pushItems(d.chest,s.slot,to_transfer,d.slot)
      -- we will work with the real transfer amount
      -- if it doesn't match the planned amount we'll error *after* updating everything
      -- because if only one of the storages is inconsistent we want to maintain consistency on the other one

      transferred = transferred + real_transfer
      amount = amount - real_transfer
      s.count = s.count - real_transfer
      inv1.items[ident].count = inv1.items[ident].count - real_transfer
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

      d.count = d.count + real_transfer
      if di > dlp and d.count > 0 then
        -- it's not an empty slot now
        if #(inv2.items[ident].slots_nils) == 0 then
          table.insert(inv2.items[ident].slots,d)
        else
          inv2.items[ident].slots[inv2.items[ident].slots_nils[#inv2.items[ident].slots_nils]] = d
          inv2.items[ident].slots_nils[#inv2.items[ident].slots_nils] = nil
        end

        inv2.empty_slots[dle-(di-dlp)+1] = nil
        table.insert(inv2.empty_slots_nils, di-dlp)
      end
      inv2.items[ident].count = inv2.items[ident].count + real_transfer

      if to_transfer ~= real_transfer then
        error("Inconsistency detected during ail transfer")
      end
    end
  end
  return transferred
end

-- transfer from a chest
-- from_slot is a required argument (might change in the future)
-- to_slot does not exist as an argument, if passed it'll simply be ignored
-- list_cache is optionally a .list() of the source chest
local function pullItems(inv,chest,from_slot,amount,_to_slot,list_cache)
  if type(from_slot) ~= "number" then
    error("from_slot is a required argument")
  end
  local sources = list_cache or peripheral.wrap(chest).list()
  local si = from_slot
  local sl = from_slot
  local s = sources[si]
  if not s or not s.name or s.count <= 0 then
    return 0
  end
  local ident = s.name..";"..(s.nbt or "")
  local stacksize = inv.stack_sizes[s.name]

  if not inv.items[ident] then
    -- new kind of item to accept
    inv.items[ident] = {count=0, slots={}, slots_nils={}}
  end
  local dests_partial = inv.items[ident].slots
  local dlp = #dests_partial
  local dests_empty = inv.empty_slots
  local dle = #dests_empty
  local di = 1

  -- skip partials if they're all full
  if inv.items[ident].count >= stacksize * listLength(inv.items[ident].slots) then
    di = dlp+1
  end

  -- TODO: put this optimization in transfer() as well.
  -- skip partials if source is full, there's an empty dest, and amount is a full stack
  if s.count >= stacksize and #inv.empty_slots > 0 and amount >= stacksize then
    di = dlp+1
  end

  local transferred = 0
  local d
  while amount > 0 and si <= sl and di <= (dlp+dle) do
    if not d then
      if di <= dlp then 
        d = dests_partial[di]
      else
        d = dests_empty[dle-(di-dlp)+1]
      end
    end

    if not s or s.count <= 0 then
      si = si + 1
      s = nil
    elseif not d or d.count >= stacksize then
      di = di + 1
      d = nil
    else
      local to_transfer = math.min(amount, s.count, stacksize-d.count)
      local real_transfer = peripheral.wrap(d.chest).pullItems(chest,si,to_transfer,d.slot)

      transferred = transferred + real_transfer
      amount = amount - real_transfer
      s.count = s.count - real_transfer

      d.count = d.count + real_transfer
      if di > dlp and d.count > 0 then
        -- it's not an empty slot now
        if #(inv.items[ident].slots_nils) == 0 then
          table.insert(inv.items[ident].slots,d)
        else
          inv.items[ident].slots[inv.items[ident].slots_nils[#inv.items[ident].slots_nils]] = d
          inv.items[ident].slots_nils[#inv.items[ident].slots_nils] = nil
        end

        inv.empty_slots[dle-(di-dlp)+1] = nil
        table.insert(inv.empty_slots_nils, di-dlp)
      end
      inv.items[ident].count = inv.items[ident].count + real_transfer

      if to_transfer ~= real_transfer then
        error("Inconsistency detected during ail transfer")
      end
    end
  end
  return transferred
end

-- transfer to a chest
-- from_slot is a required argument, and determines the type of item transferred
-- if from_slot is a number it will transfer the type of item at that entry in inv.list()
-- if from_slot is a "name;nbt" string then it'll transfer that type of item
-- list_cache is optionally a .list() of the destination chest
local function pushItems(inv,chest,from_slot,amount,to_slot,list_cache)
  local name,nbt
  if type(from_slot) == "number" then
    local l = list(inv)
    if l[from_slot] then
      name = l[from_slot].name
      nbt = l[from_slot].nbt
    end
  elseif type(from_slot) == "string" then
    name,nbt = splitIdent(from_slot)
  end
  if not name then
    error("item name is nil")
  end
  if not nbt then nbt = "" end
  local stacksize = inv.stack_sizes[name]
  if not stacksize then
    error("Unknown stack size?!?")
  end

  local ident = name..";"..nbt
  local sources = inv.items[ident].slots
  local sl = #sources
  local si = sl
  local dests = list_cache or peripheral.wrap(chest).list()
  local dl,di
  if to_slot then
    dl = to_slot
    di = to_slot
  else
    dl = peripheral.wrap(chest).size()
    di = 1
  end
  local transferred = 0
  local s
  local d
  while amount > 0 and si >= 1 and di <= dl do
    if not s then
      s = sources[si]
    end
    if not d then
      d = dests[di]
    end
    if not d or not d.name then
      d = {count=0,name=name,nbt=nbt}
    end
    if not s or s.count <= 0 then
      si = si - 1
      s = nil
    elseif d.name ~= name or (d.nbt or "") ~= nbt or d.count >= stacksize then
      di = di + 1
      d = nil
    else
      local to_transfer = math.min(amount, s.count, stacksize-d.count)
      local real_transfer = peripheral.wrap(s.chest).pushItems(chest,s.slot,to_transfer,di)

      transferred = transferred + real_transfer
      amount = amount - real_transfer
      s.count = s.count - real_transfer
      inv.items[ident].count = inv.items[ident].count - real_transfer
      if s.count == 0 then
        -- it's an empty slot now
        if #(inv.empty_slots_nils) == 0 then
          table.insert(inv.empty_slots,s)
        else
          inv.empty_slots[inv.empty_slots_nils[#inv.empty_slots_nils]] = s
          inv.empty_slots_nils[#inv.empty_slots_nils] = nil
        end

        inv.items[ident].slots[si] = nil
        table.insert(inv.items[ident].slots_nils, si)
      end

      d.count = d.count + real_transfer
      if to_transfer ~= real_transfer then
        error("Inconsistency detected during ail transfer")
      end
    end
  end
  return transferred
end


-- create an inv object out of a list of chests
local function new(chests, indexer_threads)
  indexer_threads = math.min(indexer_threads or 32, #chests)

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

  do -- index chests
    local chestsClone = {}
    for _,v in ipairs(chests) do
      chestsClone[#chestsClone+1] = v
    end

    local function indexerThread()
      while true do
        if #chestsClone == 0 then return end
        local cname = chestsClone[#chestsClone]
        chestsClone[#chestsClone] = nil

        local c = peripheral.wrap(cname)
        -- 1.12 cc + plethora calls getItemDetail "getItemMeta"
        if not c.getItemDetail then
          c.getItemDetail = c.getItemMeta
        end

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
    end

    local threads = {}
    for i=1, indexer_threads do
      threads[#threads+1] = indexerThread
    end

    parallel.waitForAll(table.unpack(threads))
  end

  -- add methods to the inv
  inv.informStackSize = function(name,stacksize) return informStackSize(inv,name,stacksize) end
  inv.spaceFor = function(name,nbt) return spaceFor(inv,name,nbt) end
  inv.amountOf = function(name,nbt) return amountOf(inv,name,nbt) end
  inv.transfer = function(inv2,name,nbt,amount) return transfer(inv,inv2,name,nbt,amount) end
  inv.pushItems = function(chest,from_slot,amount,to_slot,list_cache) return pushItems(inv,chest,from_slot,amount,to_slot,list_cache) end
  inv.pullItems = function(chest,from_slot,amount,_to_slot,list_cache) return pullItems(inv,chest,from_slot,amount,_to_slot,list_cache) end
  inv.list = function() return list(inv) end
  return inv
end




local exports = {
  version=version,
  new=new
}

return exports
