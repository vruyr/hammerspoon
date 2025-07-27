hs.loadSpoon("ScreensAndWindows")

spoon.ScreensAndWindows:startScreenWatcher()

hs.hotkey.bind({"cmd", "ctrl"}, "A", function()
	spoon.ScreensAndWindows:maximizeFrontmostWindowOnScreenWithMouse()
end)

hs.hotkey.bind({"cmd", "ctrl"}, "Z", function()
	spoon.ScreensAndWindows:moveFrontmostWindowToMousePosition()
end)
