LCD_W=128
LCD_H=64

PIXEL_SCALE = 4
bit32 = require("bit")
function getFieldInfo()
    return {
        id=123
    }
end

function getValue()
    return {
        lat= 37.23333456, 
        lon= -115.8083333 -- 7 digits, ~1.1cm
        -- lat=5,
        -- lon=5
    }
end

function getTime()
    return love.timer.getTime() / 10
end

lcd = {
    clear = function()
        love.graphics.clear(0, 0, 0, 1)
    end,
    drawPoint = function(x, y)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", x * PIXEL_SCALE, y * PIXEL_SCALE, PIXEL_SCALE, PIXEL_SCALE)
    end,
    drawFilledRectangle = function(x, y, w, h)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", x * PIXEL_SCALE, y * PIXEL_SCALE, w * PIXEL_SCALE, h * PIXEL_SCALE)
    end,
    drawText = function(x, y, text)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(text, x * PIXEL_SCALE, y * PIXEL_SCALE)
    end
}

local gps_qr = require("gps_qr_src")

function love.load()
    love.window.setMode(LCD_W * PIXEL_SCALE, LCD_H * PIXEL_SCALE + 400)
    gps_qr.init()
    
end

function love.draw()
    gps_qr.background()
    gps_qr.run()
end
