---@param low number
---@param high number
function bytesToInt16(low, high)
  return bit.bor(bit.lshift(high, 8), low)
end

---@param val number
function uintToInt(val)
  local isNegative = bit.band(0x80, val) > 0
  if not isNegative then return val end
  return val - 0x100
end
