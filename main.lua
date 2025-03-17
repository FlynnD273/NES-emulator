local emu = require("emulator")

local function update_render_scale()
  Scale = math.min(WindowDimensions.w / RenderDimensions.w, WindowDimensions.h / RenderDimensions.h)
end

local function apply_render_scale()
  love.graphics.setDefaultFilter("linear", "nearest")
  love.graphics.translate((WindowDimensions.w - RenderDimensions.w * Scale) / 2,
    (WindowDimensions.h - RenderDimensions.h * Scale) / 2)
  love.graphics.scale(Scale, Scale)
end

function love.resize(w, h)
  WindowDimensions.w = w
  WindowDimensions.h = h
  update_render_scale()
end

function love.load()
  emu.init()
  emu.loadCart("./testdata/nestest.nes")
  emu.dumpMem("emu.bin")
  Scale = 0.5
  RenderDimensions = { w = 256, h = 240 }
  WindowDimensions = { w = RenderDimensions.w * Scale, h = RenderDimensions.h * Scale }

  love.window.setMode(WindowDimensions.w, WindowDimensions.h, { resizable = true })
end

function love.update()
  emu.processCurrentOp()
end

function love.draw()
  love.graphics.push()
  apply_render_scale()
  love.graphics.setColor(0.25, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, RenderDimensions.w, RenderDimensions.h)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Hello World", 128, 120)
  love.graphics.pop()
end
