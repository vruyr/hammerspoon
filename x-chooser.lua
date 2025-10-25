function showSampleChooser()
	local choices = {
		{ text = "Hammerspoon Docs", subText = "subtext", url = "https://www.hammerspoon.org/docs" },
		{ text = "jq manual", subText = "", url = "http://jqlang.org/manual/" },
		{ text = "GitHub", subText = "github.com bar", url = "https://www.github.com" }
	}

	local chooser = hs.chooser.new(function(choice)
		if not choice then
			return
		end
		hs.execute("open " .. choice.url)
	end)

	chooser:choices(choices)
	chooser:searchSubText(true)
	chooser:show()
end
