hs.hotkey.bind({"cmd", "ctrl"}, "M", function()
	dragWindowToNewSpaceOnScreen(
		hs.window.frontmostWindow(),
		hs.mouse.getCurrentScreen()
	)
end)


function dragWindowToNewSpaceOnScreen(theWindow, theScreen)
	-- https://github.com/Hammerspoon/hammerspoon/issues/3213#issuecomment-1127779102
	local coro = coroutine.wrap(function()
		hs.coroutineApplicationYield()

		local spacesBeforeAdding = hs.spaces.spacesForScreen(theScreen:getUUID())

		local startPoint = getWindowGrabPoint(theWindow)

		local event = hs.eventtap.event

		-- mouseDown
		event.newMouseEvent(event.types.leftMouseDown, startPoint):post()
		hs.coroutineApplicationYield()

		-- startDrag
		event.newMouseEvent(event.types.leftMouseDragged, startPoint):post()
		hs.coroutineApplicationYield()

		hs.spaces.openMissionControl()
		hs.coroutineApplicationYield(hs.spaces.MCwaitTime)

		local theScreenFrame = theScreen:fullFrame()
		local endPoint = {
			x = theScreenFrame.x2 - (64) / 2,
			y = theScreenFrame.y1 + 75 -- approximate position of center of the "plus" tile
		}

		-- endDrag
		event.newMouseEvent(
			event.types.leftMouseDragged, endPoint)
		:setProperty(event.properties.mouseEventDeltaX, endPoint.x - startPoint.x)
		:setProperty(event.properties.mouseEventDeltaY, endPoint.y - startPoint.y)
		:post()
		hs.coroutineApplicationYield()

		-- mouseUp
		event.newMouseEvent(event.types.leftMouseUp, endPoint):post()
		hs.coroutineApplicationYield(hs.spaces.MCwaitTime)
	end)

	coro() -- start the coroutine

	return coro
end


function getWindowGrabPoint(theWindow)
	-- Returns the point where the mouse should grab the window to drag
	if not theWindow then
		return nil
	end

	local theWindowFrame = theWindow:frame()
	return {
		x = theWindowFrame.x + 100,
		y = theWindowFrame.y + 10
	}
end
