utils = require("utils")

hs.loadSpoon("ScreensAndWindows")

spoon.ScreensAndWindows:startScreenWatcher()

hs.hotkey.bind({"cmd", "ctrl"}, "A", function()
	spoon.ScreensAndWindows:maximizeFrontmostWindowOnScreenWithMouse()
end)

hs.hotkey.bind({"cmd", "ctrl"}, "Z", function()
	spoon.ScreensAndWindows:moveFrontmostWindowToMousePosition()
end)


hs.hotkey.bind({"cmd", "ctrl"}, "N", function()
	local ok, _, _, err = spoon.ScreensAndWindows:addSpaceToScreenWithMouseAndSwitchToIt()
	if not ok then
		utils.showError(err, hs.mouse.getCurrentScreen())
	end
end)


if spoon.ScreensAndWindows:didSystemChecksPass() then
	hs.hotkey.bind({"cmd", "ctrl"}, "X", function()
		local ok, err = spoon.ScreensAndWindows:removeCurrentSpaceOnScreenWithMouse()
		if not ok then
			utils.showError(err, hs.mouse.getCurrentScreen())
		end
	end)
else
	utils.showError("Incorrect Keyboard Shortcuts in System Settings", nil, 20)
	print("Not assiing a hotkey to spoon.ScreensAndWindows:removeCurrentSpaceOnScreenWithMouse()")
end

