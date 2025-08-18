hs.hotkey.bind({"cmd", "ctrl"}, "M", function()
	moveFrontmostWindowToNewSpaceOnScreenWithMouse()
end)


function moveFrontmostWindowToNewSpaceOnScreenWithMouse()
	local theWindow = hs.window.frontmostWindow()
	if not theWindow then
		hs.alert.show("No frontmost window to move.")
		return
	end

	local theWindowFrame = theWindow:frame()

	local theWindowGrabPosition = {
		x = theWindowFrame.x + 100,
		y = theWindowFrame.y + 10
	}

	-- local destPosition = spaceThumbnailPosition(screenWithMouse, spaceIndex)
	local destPosition = {
		x = theWindowGrabPosition.x + 100,
		y = theWindowGrabPosition.y + 100
	}

	local coro = mouseDrag(theWindowGrabPosition, destPosition)
end


function mouseDrag(startPoint, endPoint)
	-- Simulate a mouse drag from startPoint to endPoint

	-- https://github.com/Hammerspoon/hammerspoon/issues/3213#issuecomment-1127779102
	local coro = coroutine.wrap(function()
		local event = hs.eventtap.event

		-- mouseDown
		coroutine.applicationYield()
		event.newMouseEvent(event.types.leftMouseDown, startPoint):post()

		-- startDrag
		coroutine.applicationYield()
		event.newMouseEvent(event.types.leftMouseDragged, startPoint):post()

		local theWindow = hs.window.frontmostWindow()
		local screenWithMouse = hs.mouse.getCurrentScreen()
		hs.spaces.openMissionControl()
		coroutine.applicationYield(hs.spaces.MCwaitTime)
		local spaceId, spaceIndex, spaceCount, err = spoon.ScreensAndWindows:addSpaceToScreen(screenWithMouse, false)
		if not spaceId then
			util.showError("Failed to create a new space: " .. tostring(err))
			return
		end
		coroutine.applicationYield(hs.spaces.MCwaitTime)
		endPoint = spaceThumbnailPosition(screenWithMouse, spaceIndex)

		-- endDrag
		coroutine.applicationYield()
		event.newMouseEvent(
			event.types.leftMouseDragged, endPoint)
		:setProperty(event.properties.mouseEventDeltaX, endPoint.x - startPoint.x)
		:setProperty(event.properties.mouseEventDeltaY, endPoint.y - startPoint.y)
		:post()

		-- mouseUp
		coroutine.applicationYield()
		event.newMouseEvent(event.types.leftMouseUp, endPoint):post()

		-- Switch to the new space
		coroutine.applicationYield()
		hs.spaces.gotoSpace(spaceId)

		coroutine.applicationYield(hs.spaces.MCwaitTime)
		spoon.ScreensAndWindows:setWindowFrame(theWindow, spoon.ScreensAndWindows:fitRectInFrame(
			theWindow:frame(),
			screenWithMouse:frame()
		))
	end)

	coro() -- start the coroutine

	return coro
end


-- Guess the on-screen coordinates of Nth space's thumbnail
function spaceThumbnailPosition(screen, spaceIndex)
	local spaceCount = #hs.spaces.spacesForScreen(screen:getUUID())
	local screenFrame = screen:fullFrame()
	local thumbnailWidth = 140 -- approximate thumbnail width
	local gap = 32 -- fixed gap between thumbnails
	local offset = (screenFrame.w - (thumbnailWidth + gap) * spaceCount + gap) / 2
	return {
		x = screenFrame.x + offset + (thumbnailWidth + gap) * (spaceIndex - 1) + thumbnailWidth / 2,
		y = screenFrame.y + 92
	}
end
