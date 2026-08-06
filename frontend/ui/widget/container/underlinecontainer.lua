--[[--
An UnderlineContainer is a WidgetContainer that is able to paint
a line under its child node.
--]]


local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local UnderlineContainer = WidgetContainer:extend{
    linesize = Size.line.thick,
    focus_linesize = nil, -- thickness while focused; grows upwards, so nothing reflows
    focused = false,
    padding = Size.padding.tiny,
    -- We default to white to be invisible by default for FocusManager use-cases (only switching to black @ onFocus)
    color = Blitbuffer.COLOR_WHITE,
    vertical_align = "top",
    line_width = nil, -- (Don't use this, it's there because of the complex and ugly layout in TouchMenuItem)
    line_x_offset = nil, -- shifts the line right (left in RTL), to keep it clear of other content
    background = nil, -- what to clear the strip with; without it, the bar can only be drawn
}

function UnderlineContainer:getSize()
    local contentSize = self[1]:getSize()
    return Geom:new{
        w = contentSize.w,
        h = contentSize.h + self.linesize + 2*self.padding
    }
end

--- The strip this container paints its line and focus bar into, in screen coordinates.
--- Only after paintTo: dimen may be set from the outside, its coordinates are not.
function UnderlineContainer:getFocusIndicatorRegion()
    if not self._painted then return end
    local h = self:_focusBarHeight()
    if h == 0 then return end
    local line_x, line_width = self:_lineGeometry()
    return Geom:new{
        x = line_x,
        y = self:_focusBarTop(self.dimen.y + self:getSize().h),
        w = line_width,
        h = h + self.linesize,
    }
end

function UnderlineContainer:_lineGeometry()
    local line_width = self.line_width or self.dimen.w
    local line_x_offset = self.line_x_offset or 0
    if BD.mirroredUILayout() then
        return self.dimen.x + self.dimen.w - line_width - line_x_offset, line_width
    end
    return self.dimen.x + line_x_offset, line_width
end

-- The bar, without the line: together they occupy focus_linesize.
function UnderlineContainer:_focusBarHeight()
    if not self.focus_linesize then return 0 end
    return math.max(self.focus_linesize - self.linesize, 0)
end

-- Right on top of our line, so dropping the bar leaves the line untouched.
function UnderlineContainer:_focusBarTop(bottom)
    return bottom - self.linesize - self:_focusBarHeight()
end

function UnderlineContainer:_paintFocusBar(bb, line_x, bottom, line_width)
    local h = self:_focusBarHeight()
    if h == 0 then return end
    -- An unfocused bar is erased with the background: only a focus-only repaint asks
    -- for that, a full repaint has the parent clearing the row for us.
    local color = self.focused and self.color or self.background
    if not color then return end
    bb:paintRect(line_x, self:_focusBarTop(bottom), line_width, h, color)
end

--- Repaint the strip -- our line and the bar above it -- and nothing else of the widget.
function UnderlineContainer:repaintFocusIndicator(bb)
    if not self._painted or not self.background then return false end
    if self:_focusBarHeight() == 0 then return false end
    local line_x, line_width = self:_lineGeometry()
    local bottom = self.dimen.y + self:getSize().h
    self:_paintFocusBar(bb, line_x, bottom, line_width)
    bb:paintRect(line_x, bottom - self.linesize, line_width, self.linesize, self.color)
    return true
end

function UnderlineContainer:paintTo(bb, x, y)
    local container_size = self:getSize()
    if not self.dimen then
        self.dimen = Geom:new{
            x = x, y = y,
            w = container_size.w,
            h = container_size.h
        }
    else
        self.dimen.x = x
        self.dimen.y = y
    end
    self._painted = true

    local line_x, line_width = self:_lineGeometry()
    local bottom = y + container_size.h

    -- Erase a bar left over from a previous focus before the content goes in: the strip
    -- has no room of its own, so clearing it afterwards would cut into what we just drew.
    if not self.focused and self.background then
        self:_paintFocusBar(bb, line_x, bottom, line_width)
    end

    local content_size = self[1]:getSize()
    local p_y = y
    if self.vertical_align == "center" then
        p_y = math.floor((container_size.h - content_size.h) / 2) + y
    elseif self.vertical_align == "bottom" then
        p_y = (container_size.h - content_size.h) + y
    end
    self[1]:paintTo(bb, x, p_y)
    bb:paintRect(line_x, bottom - self.linesize, line_width, self.linesize, self.color)
    if self.focused then
        self:_paintFocusBar(bb, line_x, bottom, line_width)
    end
end

return UnderlineContainer
