local obsidianReadyHandlerRegistered = false

local function ensureObsidianReadyHandler()
	if obsidianReadyHandlerRegistered or not (hs and hs.urlevent) then
		return
	end

	local uiInteractionDelay = 0.01

	hs.urlevent.bind("obsidianReady", function(_, params)
		coroutine.wrap(function()
			hs.application.get("md.obsidian"):activate()
			hs.eventtap.keyStroke({}, "F2")
			hs.eventtap.keyStroke({}, "return")
			hs.eventtap.keyStroke({"cmd"}, "down")
			hs.eventtap.keyStroke({}, "pagedown")
		end)()
	end)

	hs.urlevent.bind("obsidianError", function(_, params)
		print("[Obsidian] x-error callback invoked:", hs.inspect(params))
		hs.alert.show("Obsidian x-error")
	end)

	obsidianReadyHandlerRegistered = true
end

local function experimentsObsidianAdd()
	ensureObsidianReadyHandler()

	local now = os.time()

	local nowIso8601 = tostring(os.date("%Y-%m-%dT%H:%M:%S%z", now))
	nowIso8601 = nowIso8601:gsub("([%+%-]%d%d)(%d%d)$", "%1:%2")

	local params = {
		append = "true",
		-- vault = "The Vault Name",
		name = os.date("%Y-%m-%d", now),
		content = "(date::" .. nowIso8601 .. ")\n",
		["x-success"] = "hammerspoon://obsidianReady",
		["x-error"] =   "hammerspoon://obsidianError",
	}

	local parts = {}
	for k, v in pairs(params) do
		parts[#parts + 1] = hs.http.encodeForQuery(k) .. "=" .. hs.http.encodeForQuery(v)
	end
	local query = table.concat(parts, "&")
	local url = "obsidian://new?" .. query

	hs.urlevent.openURL(url)
end

return {
	experimentsObsidianAdd = experimentsObsidianAdd
}
