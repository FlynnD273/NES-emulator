bit = bit
emu = {}
local k = 1024

---@alias register
---| "a"
---| "x"
---| "y"
---| "s"
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
  emu.maxAddr = 64 * k
  emu.mem = string.rep(string.char(0), emu.maxAddr)
  emu.pc = 0
  emu.sp = 0xFF
  emu.acc = 0
  emu.irx = 0
  emu.iry = 0
  emu.flags = {
    carry = false,
    zero = false,
    interruptDisable = false,
    decimalMode = false,
    brk = false,
    overflow = false,
    negative = false
  }
end

---@param addr number?
local function getByte(addr)
  if addr == nil then
    addr = emu.pc
    emu.pc = emu.pc + 1
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
    emu.mem = emu.mem:sub(1, addr - 1) .. val .. emu.mem:sub(addr + val:len() + 1)
  end
end

local function popStack()
  local val = getByte(0x0100 + emu.sp)
  emu.sp = emu.sp + 1
  return val
end

---@param val number
local function pushStack(val)
  setByte(val, 0x0100 + emu.sp)
  emu.sp = emu.sp - 1
end

---@param from register
---@param to register
local function t(from, to)
  local getVal = function() return popStack() end
  local setVal = function(val) return pushStack(val) end
  if from == "a" then
    getVal = function() return emu.acc end
  elseif from == "x" then
    getVal = function() return emu.irx end
  elseif from == "y" then
    getVal = function() return emu.iry end
  end

  if to == "a" then
    setVal = function(val) emu.acc = val end
  elseif to == "x" then
    setVal = function(val) emu.irx = val end
  elseif to == "y" then
    setVal = function(val) emu.iry = val end
  end

  local val = getVal()
  print(("Transfer from %s to %s (set to %x)"):format(from, to, val))
  setVal(val)
end

---@param reg register
---@param mode addressMode
local function ld(reg, mode)
  print("LDA " .. mode)
  local val = 0
  if mode == "immediate" then
    local byte = getByte()
    val = byte
  end

  local setVal = nil
  if reg == "a" then
    setVal = function(v) emu.acc = v end
  elseif reg == "x" then
    setVal = function(v) emu.irx = v end
  elseif reg == "y" then
    setVal = function(v) emu.iry = v end
  end
  if setVal == nil then
    error("Invalid register 's' for LD")
  end
  setVal(val)
  print(("Set R%s to %x"):format(reg, val))
end

---@param mode addressMode
local function cmp(mode)
  print("CMP " .. mode)
  if mode == "immediate" then
    local byte = getByte()
    emu.flags.carry = emu.acc >= byte
    emu.flags.zero = emu.acc == byte
    emu.flags.negative = emu.acc < byte
  end
end

---@param mode addressMode
local function beq(mode)
  print("BEQ " .. mode)
  if mode == "relative" then
    local byte = getByte()
    if emu.flags.zero then
      emu.pc = emu.pc + byte
      print(("Jump to: %x"):format(emu.pc))
    else
      print("No jump")
    end
  end
end

local function sei()
  print("SEI")
  emu.flags.interruptDisable = true
end

local function cld()
  print("CLD")
  emu.flags.decimalMode = false
end

local function rti()
  print("RTI")
  print("TODO: Handle the stack")
end

local opTable = {}
opTable[0x9a] = function() t("x", "s") end

opTable[0xa2] = function() ld("x", "immediate") end

opTable[0xa9] = function() ld("a", "immediate") end
opTable[0xa5] = function() ld("a", "zeropage") end
opTable[0xb5] = function() ld("a", "zeropagex") end
opTable[0xad] = function() ld("a", "absolute") end
opTable[0xbd] = function() ld("a", "absolutex") end
opTable[0xb9] = function() ld("a", "absolutey") end
opTable[0xa1] = function() ld("a", "indirectx") end
opTable[0xb1] = function() ld("a", "indirecty") end

opTable[0xf0] = function() beq("relative") end

opTable[0xc9] = function() cmp("immediate") end

opTable[0x40] = function() rti() end
opTable[0x78] = function() sei() end
opTable[0xd8] = function() cld() end

function emu.processCurrentOp()
  local op = getByte()
  local opFunc = opTable[op]
  if opFunc == nil then
    error(("Opcode $%x not implemented"):format(op))
    emu.pc = emu.pc + 1
  else
    opFunc()
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
  idx = 17
  local prg = string.sub(cart, idx, idx + prgRomSize - 1)
  idx = idx + prgRomSize
  local chr = string.sub(cart, idx, idx + chrRomSize - 1)
  if mapperMode == 0 then
    if prg:len() == 16 * k then
      print("16k")
      setByteString(prg, 0x8000)
      setByteString(prg, 0xC000)
    else
      print("32k")
      setByteString(prg, 0x8000)
    end
  else
    error(("Unsupported mapper mode %x"):format(mapperMode))
  end
  emu.resetVectors = {
    nmi = bit.bor(getByte(0xFFFA), bit.lshift(getByte(0xFFFB), 8)),
    reset = bit.bor(getByte(0xFFFC), bit.lshift(getByte(0xFFFD), 8)),
    irq = getByte(0xFFFE),
    brk = getByte(0xFFFF),
  }
  emu.pc = emu.resetVectors.reset
  print(string.format("Starting program counter at address %x", emu.pc))
end

---@param path string
function emu.dumpMem(path)
  local file = io.open(path, "wb")
  if file == nil then
    return
  end
  file:write(emu.mem)
  file:close()
end

return emu
