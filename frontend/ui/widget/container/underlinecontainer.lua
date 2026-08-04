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
    -- Painted while focused. It grows upwards, into the room linesize already reserves,
    -- so switching focus repaints the line and nothing else.
    focus_linesize = nil,
    focused = false,
    padding = Size.padding.tiny,
    -- We default to white to be invisible by default for FocusManager use-cases (only switching to black @ onFocus)
    color = Blitbuffer.COLOR_WHITE,
    vertical_align = "top",
    line_width = nil, -- (Don't use this, it's there because of the complex and ugly layout in TouchMenuItem)
    line_x_offset = nil, -- shifts the line right (left in RTL), to keep it clear of other content
    background = nil, -- what to clear the line's own area with, when its thickness varies
}

function UnderlineContainer:getSize()
    local contentSize = self[1]:getSize()
    return Geom:new{
        w = contentSize.w,
        h = contentSize.h + self.linesize + 2*self.padding
    }
end

--- The strip this container paints its line and focus bar into, in screen coordinates.
--- Only meaningful once we've been painted at least once.
function UnderlineContainer:getLineRegion()
    if not self.dimen then return end
    local h = self:_focusBarHeight()
    if h == 0 then return end
    local line_x, line_width = self:_lineGeometry(self.dimen.x)
    return Geom:new{
        x = line_x,
        y = self:_focusBarTop(self.dimen.y + self:getSize().h),
        w = line_width,
        h = h,
    }
end

function UnderlineContainer:_lineGeometry(x)
    local line_width = self.line_width or self.dimen.w
    local line_x_offset = self.line_x_offset or 0
    if BD.mirroredUILayout() then
        return x + self.dimen.w - line_width - line_x_offset, line_width
    end
    return x + line_x_offset, line_width
end

--- Height of the focus bar itself: the line keeps its own thickness out of the total,
--- so the two together always occupy focus_linesize and the line is never overdrawn.
function UnderlineContainer:_focusBarHeight()
    if not self.focus_linesize then return 0 end
    return math.max(self.focus_linesize - self.linesize, 0)
end

--- Where the focus bar lives: directly on top of our own line, so dropping the bar leaves
--- that line untouched and there is nothing to restore.
function UnderlineContainer:_focusBarTop(bottom)
    return bottom - self.linesize - self:_focusBarHeight()
end

function UnderlineContainer:_paintFocusBar(bb, line_x, bottom, line_width)
    local h = self:_focusBarHeight()
    if h == 0 then return end
    -- Clear its own strip first: a focus-only repaint has no parent to do that for us.
    bb:paintRect(line_x, self:_focusBarTop(bottom), line_width, h,
        self.focused and self.color or self.background)
end

--- Repaint just the focus bar, without touching the rest of the widget.
--- Used when only the focus moved: nothing else on the row has changed.
function UnderlineContainer:repaintFocusBar(bb)
    if not self.dimen or not self.background then return false end
    if self:_focusBarHeight() == 0 then return false end
    local line_x, line_width = self:_lineGeometry(self.dimen.x)
    self:_paintFocusBar(bb, line_x, self.dimen.y + self:getSize().h, line_width)
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

    local line_x, line_width = self:_lineGeometry(x)

    local content_size = self[1]:getSize()
    local p_y = y
    if self.vertical_align == "center" then
        p_y = math.floor((container_size.h - content_size.h) / 2) + y
    elseif self.vertical_align == "bottom" then
        p_y = (container_size.h - content_size.h) + y
    end
    self[1]:paintTo(bb, x, p_y)
    local bottom = y + container_size.h
    bb:paintRect(line_x, bottom - self.linesize, line_width, self.linesize, self.color)
    self:_paintFocusBar(bb, line_x, bottom, line_width)
end

return UnderlineContainer
