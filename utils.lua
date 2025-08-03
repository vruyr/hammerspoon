local ALERT_SETTINGS = {
	error = {
		style = {
			fillColor = { red = 0.82, green = 0.0, blue = 0.12, alpha = 1 },
			strokeColor = { red = 0, green = 0, blue = 0, alpha = 1 },
			strokeWidth = 4,
			radius = 12,

			textColor = { red = 0.98, green = 0.98, blue = 0.98, alpha = 1 },
		},
		duration = 2,
	}
}

function showError(text, screen, duration)
	print("ERROR: " .. tostring(text))
	if not duration or duration == 0 then
		duration = ALERT_SETTINGS.error.duration
	end
	if not screen then
		screen = hs.screen.primaryScreen()
	end
	hs.alert.show(text, ALERT_SETTINGS.error.style, screen, duration)
end


function dedentMultilineString(s)
	local lastLineIndent = s:match("\n(%s+)[^\n]*$")
	if not lastLineIndent then
		return s
	end
	-- `lastLineIndent` is all whitespace, so okay to use as a pattern
	return s:gsub("^" .. lastLineIndent, ""):gsub("\n" .. lastLineIndent, "\n")
end


return {
	showError = showError,
	dedentMultilineString = dedentMultilineString,
}
