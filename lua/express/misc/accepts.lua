-- very simple implementation of npm [accepts](https://github.com/jshttp/accepts/blob/master/index.js) <br>
-- #todo make it better and move to lua-express-middlewares
---@param acceptHeader string value of Accept header
---@param search string full mime type or only subtype to search. Example: "text/*" or "html"
---@return false|string `false` if not accepted, or mime type `string` if accepted
local function accepts(acceptHeader, search)
	if not acceptHeader then return false end

	local mediaTypes = {} -- {"text/*;q=.5", "application/json"}
	-- for mediaType in acceptHeader:gmatch("[^%s,/]/[^/]+") do
	for mediaType in acceptHeader:gmatch("[^%s,]+") do
		local is_correct = mediaType:match("([^/]+)/([^/]+)")
		if is_correct then
			table.insert(mediaTypes, mediaType)
		end
	end

	table.sort(mediaTypes, function(a, b) -- {"application/json", "text/*;q=.5"}
		local q1 = tonumber(a:match("q=([%d.]+)")) or 1
		local q2 = tonumber(b:match("q=([%d.]+)")) or 1
		return q1 > q2
	end)

	for _, mediaType in ipairs(mediaTypes) do
		mediaType = mediaType:match("([^;]+)") -- text/*;q=.5 > text/*
		if mediaType == "*/*" or search == "*/*" or search == "*" then
			return mediaType
		end

		local search_type, search_subtype = search:match("([^/]+)/([^/]+)") -- {"text", "*"}
		local mime_type, mime_subtype  = mediaType:match("([^/]+)/([^/]+)") -- {"application", "xhtml+xml"}
		if not (mime_type and mime_subtype) then
			print("express: malformed Accept header received: " .. acceptHeader)
			return false
		end

		local mime_subtypes = {}
		for subtype in mime_subtype:gmatch("[^+]+") do -- "xhtml+xml" > {"xhtml", "xml"}
			table.insert(mime_subtypes, subtype)
		end

		if search_type == "*" and search_subtype ~= "*" then -- searching "*/something"
			error("express. incorrect search type: " .. search)
		end

		if mime_type == "*" and mime_subtype ~= "*" then -- "*/something" received
			print("express. incorrect Accept header received: " .. acceptHeader)
			return false
		end

		-- search is only subtype
		if not search_type then
			-- html == text/html
			if search == mime_subtype then return mediaType end

			-- html == text/xml+html (second part)
			for _, subtype in ipairs(mime_subtypes) do -- {"xhtml", "xml"}
				if search == subtype then return mediaType end
			end

		-- "text/..." == "text/..."
		elseif search_type == mime_type then
			-- text/* == text/html, text/xml == text/*
			if search_subtype == "*" or mime_subtype == "*" then
				return mediaType
			end

			-- text/html == text/html
			if search_subtype == mime_subtype then
				return mediaType
			end

			-- text/html == text/xml+html (second part)
			for _, subtype in ipairs(mime_subtypes) do -- {"xhtml", "xml"}
				if search_subtype == subtype then return mediaType end
			end
		end
	end

	return false
end

-- -- Tests
-- local hdr = "text/html, application/xml;q=0.9, application/xhtml+xml, */*;q=.8, something/foo+bar"
-- assert( accepts(hdr, "json") == "*/*" )
-- assert( accepts(hdr, "html") == "text/html" )
-- assert( accepts(hdr, "bar") == "something/foo+bar" )
-- assert( accepts(hdr, "application/xhtml") == "application/xhtml+xml" )
-- assert( accepts(hdr, "xml") == "application/xhtml+xml" ) -- application/xml is less priority
-- assert( accepts(hdr, "application/*") == "application/xhtml+xml" )
-- assert( accepts("incorrect header", "*") == false )
-- assert( accepts("anything/blabla;q=.9, any2/bla2", "*") == "any2/bla2" )
-- assert( accepts("text/html", "fake") == false )
-- assert( accepts("application/json", "application") == false ) -- seaching only subtype
-- print("all ok")

return accepts
