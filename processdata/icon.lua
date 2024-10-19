local Icon = {}
Icon.__index = Icon

function Icon.new(d)
	local icons
	if d.icon then
		icons = {{icon = d.icon}}
	elseif d.icons then
		icons = {}
		for i, subicon in ipairs(d.icons) do
			local icon = {icon = subicon.icon}
			if subicon.tint then
				local tint = subicon.tint
				local r
				local g
				local b
				local a
				if tint.r then
					r = tint.r
					g = tint.g
					b = tint.b
					if tint.a then
						a = tint.a
					end
				else
					r = tint[1]
					g = tint[2]
					b = tint[3]
					if #tint > 3 then
						a = tint[4]
					end
				end
				icon.tint = {r, g, b, a}
			end
			table.insert(icons, icon)
		end
		--icons = d.icons
	else
		msg("no icon for", d.name)
		return nil
	end
	local icon = {
		icon_list = icons
	}
    return setmetatable(icon, Icon)
end

function Icon:add_sources(data)
	for _, icon in ipairs(self.icon_list) do
		local mod_name, icon_path = string.match(icon.icon, "__([%w%s_%-]+)__/(.*)")
		local mod = data.module_info[mod_name]
		if mod.localPath ~= nil then
			local fullpath = mod.localPath .. "/" .. icon_path
			icon.source = "file"
			icon.path = fullpath
		else
			icon.source = "zip"
			icon.zipfile = mod.zip_path
			icon.path = mod.mod_name .. "/" .. icon_path
		end
	end
end

function Icon:key()
	local k = ""
	for _, icon in ipairs(self.icon_list) do
		if k ~= "" then
			k = k .. "~"
		end
		k = k .. icon.icon
		if icon.tint then
			local tint = icon.tint
			local r = tint[1]
			local g = tint[2]
			local b = tint[3]
			local a
			if #tint > 3 then
				a = tint[4]
			end
			k = k .. string.format(",%f,%f,%f", r, g, b)
			if a then
				k = k .. string.format(",%f", a)
			end
		end
	end
	return k
end

function Icon:equal(other)
	return self.key() == other.key()
end

local function path_stem(path)
	return string.match(path, ".*/([^/]*)%.[^/%.]+$")
end

function Icon:comparator()
	return path_stem(self.icon_list[1].path) .. "!" .. self:key()
end

return Icon
