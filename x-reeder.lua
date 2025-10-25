hs.hotkey.bind({"cmd", "shift"}, "E", function()
	-- Make sure we only move forward if it is the Reeder app
	local frontApp = hs.application.frontmostApplication()
	if not frontApp or frontApp:name() ~= "Reeder" then
		return
	end
	local win = frontApp:mainWindow()
	if not win then
		return
	end

	-- Open the context menu at the mouse position
	local mousePos = hs.mouse.absolutePosition()
	hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, mousePos):post()
	hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, mousePos):post()
	hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.rightMouseDown, mousePos):post()
	hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.rightMouseUp, mousePos):post()

	hs.timer.usleep(250000)

	function keyEvent(key, down)
		local event = hs.eventtap.event.newKeyEvent(key, down)
		event:setProperty(
			hs.eventtap.event.properties.eventTargetUnixProcessID,
			frontApp:pid()
		)
		return event
	end

	-- Go to the “Mark above as read” context menu item
	for i = 1, 2 do
		keyEvent("down", true):post()
		keyEvent("down", false):post()
	end

	-- Select the context menu item
	keyEvent("return", true):post()
	keyEvent("return", false):post()
end)
