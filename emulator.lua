require("util")
---Redeclare here to avoid editor complaining about lowercase global everywhere else
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
  emu.sc = 0xFF
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

---@param val string|number
---@param addr number?
local function setByte(val, addr)
  if type(val) == "number" then
    val = string.char(val)
  end
  addr = addr + 1
  if addr == 1 then
    emu.mem = val .. emu.mem:sub(1 + val:len())
  elseif addr + val:len() == emu.maxAddr then
    emu.mem = emu.mem:sub(1, addr - 1) .. val
  else
    emu.mem = emu.mem:sub(1, addr - 1) .. val .. emu.mem:sub(addr + val:len())
  end
end

---@param addr number
local function getInt16(addr)
  return bytesToInt16(getByte(addr), getByte(addr + 1))
end

local function popStack()
  emu.sc = emu.sc + 1
  local val = getByte(0x0100 + emu.sc)
  return val
end

---@param val number|boolean
local function pushStack(val)
  if type(val) == "boolean" then
    if val then
      val = 1
    else
      val = 0
    end
  end
  setByte(val, 0x0100 + emu.sc)
  emu.sc = emu.sc - 1
end


local function pushPC()
  pushStack(bit.band(emu.pc, 0xFF))
  pushStack(bit.band(bit.rshift(emu.pc, 8), 0xFF))
end

local function popPC()
  local high = popStack()
  local low = popStack()
  emu.pc = bytesToInt16(low, high)
end

local function pushStatus()
  pushStack(emu.flags.carry)
  pushStack(emu.flags.zero)
  pushStack(emu.flags.interruptDisable)
  pushStack(emu.flags.decimalMode)
  pushStack(emu.flags.brk)
  pushStack(emu.flags.overflow)
  pushStack(emu.flags.negative)
end

local function popStatus()
  emu.flags.negative = popStack() == 1
  emu.flags.overflow = popStack() == 1
  emu.flags.brk = popStack() == 1
  emu.flags.decimalMode = popStack() == 1
  emu.flags.interruptDisable = popStack() == 1
  emu.flags.zero = popStack() == 1
  emu.flags.carry = popStack() == 1
end

---@param from register
---@param to register
local function t(from, to)
  local getVal = function() return popStack() end
  local setVal = function(val) pushStack(val) end
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
  emu.flags.zero = val == 0
  emu.flags.negative = val < 0
  print(("Transfer from %s to %s (set to 0x%x)"):format(from, to, val))
  setVal(val)
end

---@param reg register
---@param mode addressMode
local function ld(reg, mode)
  local val = 0
  if mode == "immediate" then
    val = getByte()
  elseif mode == "absolute" then
    local low = getByte()
    local high = getByte()
    val = getByte(bytesToInt16(low, high))
  else
    error(("ld%s with mode %s is not implemented"):format(reg, mode))
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
  emu.flags.zero = val == 0
  emu.flags.negative = val < 0
  print(("ld%s %s set r%s to 0x%x"):format(reg, mode, reg, val))
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
local function jmp(mode)
  print("JMP " .. mode)
  if mode == "absolute" then
    local low = getByte()
    local high = getByte()
    emu.pc = bytesToInt16(low, high)
  elseif mode == "indirect" then
    local low = getByte()
    local high = getByte()
    local addr = bytesToInt16(low, high)
    local val = getInt16(addr)
    print(("Value at address %x is %x"):format(addr, val))
    emu.pc = val
  end
end

---@param mode "eq"|"pl"
local function b(mode)
  local byte = uintToInt(getByte())
  local shouldJump = false
  if mode == "eq" then
    shouldJump = emu.flags.zero
  elseif mode == "pl" then
    shouldJump = not emu.flags.negative
  end
  local jumpStatus = ""
  if shouldJump then
    emu.pc = emu.pc + byte
    jumpStatus = ("jump by %d to: %x"):format(byte, emu.pc)
  else
    jumpStatus = "no jump"
  end
  print(("b%s %s"):format(mode, jumpStatus))
end

local function sei()
  print("SEI")
  emu.flags.interruptDisable = true
end

local function cld()
  print("CLD")
  emu.flags.decimalMode = false
end

local function brk()
  print("BRK")
  pushPC()
  pushStatus()
  emu.flags.brk = true
  emu.pc = getInt16(emu.resetVectors.irq)
end

local function rti()
  print("RTI")
  popStatus()
  popPC()
  emu.pc = emu.pc + 1
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

opTable[0xf0] = function() b("eq") end
opTable[0x10] = function() b("pl") end

opTable[0xc9] = function() cmp("immediate") end

opTable[0x4c] = function() jmp("absolute") end
opTable[0x6c] = function() jmp("indirect") end

opTable[0x40] = function() rti() end
opTable[0x78] = function() sei() end
opTable[0xd8] = function() cld() end
opTable[0x00] = function() brk() end

function emu.processCurrentOp()
  local op = getByte()
  print(("pc: %x (%x)"):format(emu.pc - 1, op))
  emu.dumpMem("emu.bin")
  local opFunc = opTable[op]
  if opFunc == nil then
    emu.dumpMem("err.bin")
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
      print(("%x"):format(prg:byte(1)))
      setByte(prg, 0x8000)
      setByte(prg, 0xC000)
    else
      print("32k")
      setByte(prg, 0x8000)
    end
  else
    error(("Unsupported mapper mode %x"):format(mapperMode))
  end
  emu.resetVectors = {
    nmi = 0xFFFA,
    reset = 0xFFFC,
    irq = 0xFFFE,
    brk = 0xFFFF,
  }
  emu.pc = getInt16(emu.resetVectors.reset)
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
