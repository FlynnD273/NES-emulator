bit = bit
emu = {}
local k = 1024

---@alias addressMode
---| "accumulator"
---| "absolute"
---| "absolutex"
---| "absolutey"
---| "immediate"
---| "implied"
---| "indirect"
---| "indirectx"
---| "indirecty"
---| "relative"
---| "zeropage"
---| "zeropagex"
---| "zeropagey"


function emu.init()
  emu.currentOp = nil
  emu.maxAddr = 64 * k
  emu.mem = string.rep(string.char(0), emu.maxAddr)
  emu.pc = 0
  emu.sc = 0x01FF
  emu.acc = 0
  emu.irx = 0
  emu.iry = 0
  emu.status = {
    carry = false,
    zero = false,
    interruptDisable = false,
    -- Not needed in NES
    -- decimalMode = false,
    brk = false,
    overflow = false,
    negative = false
  }
end

---@param mode addressMode
local function lda(mode)
  print("LDA " .. mode)
end

local opTable = {}
opTable[0xa9] = function() lda("immediate") end
opTable[0xa5] = function() lda("zeropage") end
opTable[0xb5] = function() lda("zeropagex") end
opTable[0xad] = function() lda("absolute") end
opTable[0xbd] = function() lda("absolutex") end
opTable[0xb9] = function() lda("absolutey") end
opTable[0xa1] = function() lda("indirectx") end
opTable[0xb1] = function() lda("indirecty") end

---@param addr number?
local function getByte(addr)
  if addr == nil then
    addr = emu.pc
  end
  addr = addr + 1
  return string.byte(emu.mem, addr)
end

---@param val number
---@param addr number?
local function setByte(val, addr)
  val = bit.band(val, 0xFF)
  if addr == nil then
    addr = emu.pc
  end
  addr = addr + 1
  if addr == 1 then
    emu.mem = string.char(val) .. emu.mem:sub(addr + 1, emu.mem:len())
  elseif addr == emu.maxAddr then
    emu.mem = emu.mem:sub(addr - 1) .. string.char(val)
  else
    emu.mem = emu.mem:sub(addr - 1) .. string.char(val) .. emu.mem:sub(addr + 1, emu.mem:len())
  end
end

---@param val string
---@param addr number?
local function setByteString(val, addr)
  if addr == nil then
    addr = emu.pc
  end
  addr = addr + 1
  if addr == 1 then
    emu.mem = val .. emu.mem:sub(addr + val:len())
  elseif addr + val:len() == emu.maxAddr then
    emu.mem = emu.mem:sub(1, addr - 1) .. val
  else
    emu.mem = emu.mem:sub(1, addr - 1) .. val .. emu.mem:sub(addr + val:len())
  end
end

function emu.cycle()
  if emu.currentOp == nil then
    local op = getByte()
    local opFunc = opTable[op]
    if opFunc == nil then
      emu.pc = emu.pc + 1
    else
      opFunc()
    end
  end
end

---@param path string
function emu.loadCart(path)
  print("Loading cart " .. path)
  local file = io.open(path, "rb")
  if file == nil then
    print("No such file")
    return nil
  end
  local cart = ""
  cart = file:read("*a")
  local header = "NES" .. string.char(0x1a)
  local cartHeader = string.sub(cart, 1, header:len())
  if cartHeader == header then
    print("Cartridge is valid")
  else
    print("Cartridge is invalid with header " .. cartHeader)
    print("Expected " .. header)
  end
  local idx = header:len() + 1
  local prgRomSize = string.byte(cart, idx) * 16 * k
  idx = idx + 1
  local chrRomSize = string.byte(cart, idx) * 8 * k
  idx = idx + 1
  local mapperMode = string.byte(cart, idx)
  idx = 16
  local prg = string.sub(cart, idx, idx + prgRomSize - 1)
  print(("prog size: %x"):format(prgRomSize))
  idx = idx + prgRomSize
  print(("chr start: %x"):format(idx))
  local chr = string.sub(cart, idx, idx + chrRomSize - 1)
  if mapperMode == 0 then
    if prg:len() == 16 * k then
      print("16k")
      setByteString(prg, 0x8000)
      setByteString(prg, 0x8000 + 16 * k)
    else
      print("32k")
      setByteString(prg, 0x8000)
    end
  else
    error(("Unsupported mapper mode %x"):format(mapperMode))
  end
  emu.resetVectors = {
    nmi = bit.band(getByte(0xFFFB), bit.lshift(getByte(0xFFFA), 8)),
    reset = bit.band(getByte(0xFFFD), bit.lshift(getByte(0xFFFC), 8)),
    irq = getByte(0xFFFE),
    brk = getByte(0xFFFF),
  }
  emu.pc = emu.resetVectors.reset
  print(string.format("Starting program counter at address %x", emu.pc))
  print(string.format("mem size: %x", emu.mem:len()))
  print(("last mem: %x"):format(getByte(0xFFFe)))
  file = io.open("mem.bin", "wb")
  file:write(emu.mem)
  file:close()
end

return emu
