-- https://github.com/jshttp/proxy-addr/blob/master/index.js

-- https://github.com/whitequark/ipaddr.js/blob/fb169615d04bb5f1c6042a07d85f9b09bef69af6/lib/ipaddr.js#L182-L211
local IP_RANGES = {
	linklocal   = {"169.254.0.0/16", "fe80::/10"},
	loopback    = {"127.0.0.1/8", "::1/128"},
	uniquelocal = {"10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7"}
}

local maskHasIP do
	local ipToInt = function(ip)
		local int = 0
		local p1,p2,p3,p4 = ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
		int = int + bit.lshift(p1,24)
		int = int + bit.lshift(p2,16)
		int = int + bit.lshift(p3,8)
		int = int + p4
		return int
	end

	maskHasIP = function(mask, ip)
		local maskip,bits = mask:match("(%d+%.%d+%.%d+%.%d+)/(%d+)")
		maskip = ipToInt(maskip)

		local netmask = bit.lshift(0xFFFFFFFF, 32 - bits)
		return bit.band(maskip,netmask) == bit.band(ipToInt(ip), netmask)
	end
end

local function is_ip(val)
	return val:match("%d+%.%d+%.%d+%.%d+") or val:match("%x+:%x+:%x+:%x+:%x+:%x+:%x+:%x+")
end

local function trustSingle(subnet)

	return function(addr)
		if not is_ip(addr) then return false end
		return maskHasIP(subnet, addr)
	end
end

local function trustMulti(subnets)
	return function(addr)
		if not is_ip(addr) then return false end

		for _, subnet in ipairs(subnets) do
			if maskHasIP(subnet, addr) then
				return true
			end
		end

		return false
	end
end


local function compile(ips_or_subnets)
	local trust = {}
	for _, val in ipairs(ips_or_subnets) do -- replaces some values like loopback with their values
		if IP_RANGES[val] then
			for _, subnet in ipairs(IP_RANGES[val]) do
				table.insert(trust, subnet)
			end
		else
			table.insert(trust, val)
		end
	end

	if #ips_or_subnets == 0 then
		return function() return false end
	else
		return #ips_or_subnets == 1 and trustSingle(trust[1]) or trustMulti(trust)
	end
end

local function proxyaddr(req, trust)
	assert(req.pg_req.ip, "req.pg_req.ip is nil. Probably it's a luasocket error")

	local check_trust = {req.pg_req.ip}
	local xff = req:get("x-forwarded-for") or ""
	for ip in xff:gmatch("[^,]+") do
		ip = ip:match("^%s*(.-)%s*$") -- trim
		table.insert(check_trust, ip)
	end

	local trusted = {}
	for i, ip in ipairs(check_trust) do
		if i == 1 or trust(ip) then
			table.insert(trusted, ip)
		end
	end

	return trusted[#trusted]
end

return {
	proxyaddr = proxyaddr,
	compile = compile,
}
