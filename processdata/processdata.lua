local Process = {}

local missing_icon = "__core__/graphics/too-far.png"

local function get_icon(data, path)
	local mod_name, icon_path = string.match(path, "__([%w%s_%-]+)__/(.*)")
	local mod = data.module_info[mod_name]
	if mod.localPath ~= nil then
		local fullpath = mod.localPath .. "/" .. icon_path
		return {source = "file", path = fullpath}
	else
		return {source = "zip", zipfile = mod.zip_path, path = mod.mod_name .. "/" .. icon_path}
	end
end

local conversion_factor = {
	[""] = 1,
	["k"] = 1000,
	["M"] = 1000000,
	["G"] = 1000000000,
}

local function convert_power(s)
	local quantity, unit = string.match(s, "([^%a]+)(%a?)[WJ]")
	local factor = conversion_factor[unit]
	return tonumber(quantity) * factor
end

local function convert(d, attr)
	d[attr] = convert_power(d[attr])
end

local function copytable(t)
	local new = {}
	for k, v in pairs(t) do
		new[k] = v
	end
	return new
end

local function path_stem(path)
	return string.match(path, ".*/([^/]*)%.[^/%.]+$")
end

local function icon_compare(a, b)
	local stem_a = path_stem(a)
	local stem_b = path_stem(b)
	if stem_a == stem_b then
		return a < b
	end
	return stem_a < stem_b
end

local function resolve_key(locale, key)
	local i = string.find(key, "%.")
	if i == nil then
		local s = locale[""][key]
		if s == nil then
			return key
		end
		return s
	end
	local section = string.sub(key, 1, i-1)
	local item_key = string.sub(key, i+1)
	return locale[section][item_key]
end

local function localize_name_fallback(locale, name)
	local format_key = name[1]
	local args = name[2]
	format = resolve_key(locale, format_key)
	local literal = false
	if args == nil then
		return format
	elseif type(args) ~= "table" then
		literal = true
		local new_args = {}
		for i = 2, #args do
			table.insert(new_args, args[i])
		end
		args = new_args
	end
	local s = string.gsub(format, "__(%d+)__", function(d)
		local key = args[tonumber(d)]
		if literal then
			return key
		else
			return resolve_key(locale, key)
		end
	end)
	return s
end

-- Returns a table of the form {en = localized name} for the given raw_object,
-- or for fallback_key (if given) if raw_object has no defined localized name.
local function localized_name(locale, raw_object, fallback_key)
	local locale_sections = {"recipe-name", "item-name", "fluid-name", "equipment-name", "entity-name"}
	if raw_object.localised_name then
		return {en = localize_name_fallback(locale, raw_object.localised_name)}
	else
		local result = nil
		for _, key in ipairs({raw_object.name, fallback_key}) do
			for _, section in ipairs(locale_sections) do
				result = locale[section][key]
				if result ~= nil then
					goto found
				end
			end
		end
		::found::
		if result == nil then
			msg("no localized name for", raw_object.type, "named", raw_object.name)
		else
			result = result:gsub("__(%S*)__(%S*)__", function(section, name)
				section = section:lower() .. "-name"
				return locale[section][name]
			end)
			return {en = result}
		end
	end
end

local function make_icon(d)
	return d.icon
	--return {
	--	path = d.icon,
	--}
end

-- Makes item entry, but still lacking:
--  - group
--  - icon_col/icon_row
--  - localized_name.en
local function make_item(locale, d)
	local subgroup = d.subgroup
	if subgroup == nil then
		subgroup = "other"
	end
	local name = localized_name(locale, d)
	if name == nil then
		return nil
	end
	return {
		icon = make_icon(d),
		key = d.name,
		localized_name = name,
		order = d.order,
		stack_size = d.stack_size,
		subgroup = subgroup,
		type = d.type,
	}
end

local function make_fluid(d)
	return {
		default_temperature = d.default_temperature,
		fuel_value = d.fuel_value,
		heat_capacity = d.heat_capacity,
		item_key = d.name,
		max_temperature = d.max_temperature,
	}
end

local function make_fuel(d)
	return {
		item_key = d.name,
		category = d.fuel_category,
		value = convert_power(d.fuel_value),
	}
end

local function make_module(locale, d)
	local e = d.effect
	local effect = {}
	if major_version == "1" then
		if e.consumption then
			effect.consumption = e.consumption.bonus
		end
		if e.pollution then
			effect.pollution = e.pollution.bonus
		end
		if e.productivity then
			effect.productivity = e.productivity.bonus
		end
		if e.quality then
			effect.quality = e.quality.bonus
		end
		if e.speed then
			effect.speed = e.speed.bonus
		end
	else
		effect.consumption = e.consumption
		effect.pollution = e.pollution
		effect.productivity = e.productivity
		effect.speed = e.speed
	end
	return {
		category = d.category,
		effect = effect,
		item_key = d.name,
		--limitation = d.limitation,
	}
end

local function make_belt(locale, d)
	return {
		key = d.name,
		icon = make_icon(d),
		localized_name = localized_name(locale, d),
		speed = d.speed,
	}
end

local function startswith(s, prefix)
	return string.sub(s, 1, string.len(prefix)) == prefix
end

-- Creates a normalized recipe table.
-- Args:
--		locale: The current locale.
--		mode: "normal" or "expensive".
--		d: The raw datum.
--		item_map: A table mapping {[item_key] = item}
local function make_recipe(locale, mode, d, item_map, prod_recipes)
	if startswith(d.name, "parameter-") then
		msg("ignoring recipe", d.name)
		return nil
	end
	-- Apply the normal/expensive mode, if present.
	if d[mode] ~= nil then
		d = copytable(d)
		for k, v in pairs(d[mode]) do
			d[k] = v
		end
	end

	local results = {}
	if d.results ~= nil then
		for _, result in ipairs(d.results) do
			if result.amount == nil then
				table.insert(results, {name = result[1], amount = result[2]})
			else
				table.insert(results, {
					name = result.name,
					amount = result.amount,
					-- Usually nil.
					probability = result.probability,
				})
			end
		end
	elseif d.result ~= nil then
		local amount = d.result_count
		if amount == nil then
			amount = 1
		end
		results = {{name = d.result, amount = amount}}
	end
	local allow_productivity = d.allow_productivity or prod_recipes[d.name] or false
	local energy_required = d.energy_required
	if energy_required == nil then
		energy_required = 0.5
	end
	local category = d.category
	if category == nil then
		category = "crafting"
	end
	local ings = {}
	for i, ing in ipairs(d.ingredients) do
		if ing.name == nil then
			table.insert(ings, {name = ing[1], amount = ing[2]})
		else
			table.insert(ings, {name = ing.name, amount = ing.amount})
		end
	end
	local main_product = nil
	if #results == 1 then
		main_product = item_map[results[1].name]
	end
	-- If any of the icon, subgroup, or order are not provided, inherit
	-- them from the result item. If there is more than one result item,
	-- then complain.
	local icon
	if d.icon == nil and d.icons == nil then
		if main_product == nil then
			msg("main_product unexpectedly nil [icon] for", d.name)
			return nil
		end
		icon = main_product.icon
	else
		icon = make_icon(d)
	end
	local subgroup
	if d.subgroup == nil then
		if main_product == nil then
			msg("main_product unexpectedly nil [subgroup] for", d.name)
			return nil
		end
		subgroup = main_product.subgroup
	else
		subgroup = d.subgroup
	end
	local order
	if d.order == nil then
		if main_product == nil then
			msg("main_product unexpectedly nil [order] for", d.name)
			return nil
		end
		order = main_product.order
	else
		order = d.order
	end
	local main_product_key = nil
	if main_product == nil then
		--msg("main_product is nil for", d.name)
	else
		main_product_key = main_product.key
	end
	return {
		allow_productivity = allow_productivity,
		category = category,
		energy_required = energy_required,
		icon = icon,
		ingredients = ings,
		key = d.name,
		localized_name = localized_name(locale, d, main_product_key),
		order = order,
		results = results,
		subgroup = subgroup,
	}
end

local function make_source(d)
	if d.energy_source ~= nil then
		local s = d.energy_source
		if type(s.emissions_per_minute) == "table" then
			-- Factorio 2
			return {
				emissions_per_minute = s.emissions_per_minute,
				fuel_category = s.fuel_category,
				type = s.type,
			}
		else
			-- Factorio 1
			return {
				emissions_per_minute = {pollution = s.emissions_per_minute},
				fuel_category = s.fuel_category,
				type = s.type,
			}
		end
	end
end

local function get_slots(d)
	if major_version == "1" then
		if d.module_specification and d.module_specification.module_slots ~= nil then
			return d.module_specification.module_slots
		end
	else
		if d.module_slots ~= nil then
			return d.module_slots
		end
	end
	return 0
end

local function make_crafting_machine(locale, d)
	return {
		allowed_effects = d.allowed_effects,
		crafting_categories = d.crafting_categories,
		crafting_speed = d.crafting_speed,
		energy_source = make_source(d),
		energy_usage = convert_power(d.energy_usage),
		icon = make_icon(d),
		key = d.name,
		localized_name = localized_name(locale, d),
		module_slots = get_slots(d),
	}
end

local function make_mining_drill(locale, d)
	return {
		allowed_effects = d.allowed_effects,
		energy_source = make_source(d),
		energy_usage = convert_power(d.energy_usage),
		icon = make_icon(d),
		key = d.name,
		localized_name = localized_name(locale, d),
		mining_speed = d.mining_speed,
		module_slots = get_slots(d),
		resource_categories = d.resource_categories,
		takes_fluid = d.input_fluid_box ~= nil,
	}
end

local function make_rocket_silo(locale, d)
	return {
		allowed_effects = d.allowed_effects,
		crafting_categories = d.crafting_categories,
		crafting_speed = d.crafting_speed,
		--energy_source = make_source(d),
		energy_usage = convert_power(d.energy_usage),
		icon = make_icon(d),
		key = d.name,
		localized_name = localized_name(locale, d),
		module_slots = get_slots(d),
	}
end

local function make_resource(locale, d)
	local m = d.minable
	local results
	if m.result ~= nil then
		results = {{name = m.result, amount = 1}}
	else
		results = {}
		for _, r in pairs(m.results) do
			table.insert(results, {
				name = r.name,
				amount = r.amount,
				amount_max = r.amount_max,
				amount_min = r.amount_min,
				probability = r.probability,
			})
		end
	end
	return {
		category = d.category,
		fluid_amount = m.fluid_amount,
		icon = make_icon(d),
		key = d.name,
		localized_name = localized_name(locale, d),
		mining_time = m.mining_time,
		required_fluid = m.required_fluid,
		results = results,
	}
end

local _verbose = false
function msg(...)
	if _verbose then
		print(...)
	end
end

local function sorted_keys(t)
	local a = {}
	for key, value in pairs(t) do
		table.insert(a, key)
	end
	table.sort(a)
	return a
end

local function sorted_pairs(t)
	local keys = sorted_keys(t)
	local key_indexes = {}
	for index, key in ipairs(keys) do
		key_indexes[key] = index
	end
	return function(s, var)
		if var == nil then
			return keys[1], t[keys[1]]
		end
		local i = key_indexes[var] + 1
		if i > #keys then
			return nil
		end
		local key = keys[i]
		return key, t[key]
	end, nil, nil
end

local major_version

function Process.process_data(data, locales, verbose)
	_verbose = verbose
	local version = data["module_info"]["core"]["version"]
	major_version = string.sub(version, 1, 1)

	-- Limit it to English for now.
	local locale = locales["en"]

	local item_types
	local no_module_icon
	if major_version == 1 then
		item_types = {"ammo", "armor", "blueprint", "blueprint-book", "capsule", "deconstruction-item", "fluid", "gun", "item", "item-with-entity-data", "mining-tool", "module", "rail-planner", "repair-tool", "spidertron-remote", "tool"}
		no_module_icon = data["utility-sprites"]["default"]["slot_icon_module"]["filename"]
	else
		item_types = {"ammo", "armor", "blueprint", "blueprint-book", "capsule", "deconstruction-item", "fluid", "generator", "gun", "item", "item-with-entity-data", "module", "rail-planner", "repair-tool", "spidertron-remote", "tool"}
		no_module_icon = data["utility-sprites"]["default"]["empty_module_slot"]["filename"]
	end
	msg("slot_icon_module:", no_module_icon)
	local clock_icon = data["utility-sprites"]["default"]["clock"]["filename"]
	local icon_paths = {[no_module_icon] = true, [clock_icon] = true}
	-- Normalize items
	local item_groups = {}
	for name, d in pairs(data["item-group"]) do
		item_groups[d.name] = {order = d.order, subgroups = {}}
	end
	local item_subgroups = data["item-subgroup"]
	for name, d in pairs(item_subgroups) do
		item_groups[d["group"]]["subgroups"][name] = d["order"]
	end
	local items = {}
	local fuel = {}
	for i, item_type in ipairs(item_types) do
		if data[item_type] == nil then
			msg("bad item_type:", item_type)
		end
		for name, item in sorted_pairs(data[item_type]) do
			local subgroup
			if item.subgroup ~= nil then
				subgroup = item["subgroup"]
			else
				subgroup = "other"
				item["subgroup"] = "other"
			end
--			if subgroup == "fill-barrel" or subgroup == "bob-gas-bottle" then
--				goto continue
--			end
			local new_item = make_item(locale, item)
			if new_item == nil then
				goto continue
			end
			new_item["group"] = item_subgroups[subgroup]["group"]
			if item.icon == nil then
				if item.icons == nil then
					msg("skipped:", item)
					goto continue
				end
				-- XXX: Temporary hack.
				msg("hack icon:", name)
				new_item["icon"] = item["icons"][1]["icon"]
				if new_item.icon == nil then
					print("icon still nil:", name)
				end
			end
			if item.fuel_value ~= nil and item.fuel_category ~= nil then
				table.insert(fuel, make_fuel(item))
			end
			if new_item.order == nil then
				msg("item.order is nil for", new_item.key)
			else
				table.insert(items, new_item)
			end
			::continue::
		end
	end
	table.sort(items, function(a, b) return a.order < b.order end)
	local fluids = {}
	for name, d in sorted_pairs(data.fluid) do
		table.insert(fluids, make_fluid(d))
	end
	local modules = {}
	local prod_recipes = nil
	local prod_recipe_count = 0
	for name, d in sorted_pairs(data.module) do
		local m = make_module(locale, d)
		table.insert(modules, m)
		if d.limitation ~= nil and m.effect.productivity ~= nil then
			if prod_recipes == nil then
				prod_recipes = {}
				for _, key in ipairs(d.limitation) do
					prod_recipes[key] = true
					prod_recipe_count = prod_recipe_count + 1
				end
			else
				local match = #d.limitation == prod_recipe_count
				if match then
					for _, key in ipairs(d.limitation) do
						if not prod_recipes[key] then
							match = false
							break
						end
					end
				end
				if not match then
					msg("prod module limit list mismatch:", d.name)
				end
			end
		end
	end
	if prod_recipes == nil then
		prod_recipes = {}
	end
	local belts = {}
	for name, d in sorted_pairs(data["transport-belt"]) do
		table.insert(belts, make_belt(locale, d))
	end
	local item_map = {}
	for _, item in ipairs(items) do
		if item_map[item.key] ~= nil then
			print("duplicate item key:", item.key)
		end
		item_map[item.key] = item
	end
	
	local crafters = {}
	for _, cat in ipairs({"assembling-machine", "furnace"}) do
		for name, d in sorted_pairs(data[cat]) do
			table.insert(crafters, make_crafting_machine(locale, d))
		end
	end
	local drills = {}
	for name, d in sorted_pairs(data["mining-drill"]) do
		table.insert(drills, make_mining_drill(locale, d))
	end
	local silo = {}
	for name, d in sorted_pairs(data["rocket-silo"]) do
		table.insert(silo, make_rocket_silo(locale, d))
	end
	local resources = {}
	for name, d in sorted_pairs(data["resource"]) do
		table.insert(resources, make_resource(locale, d))
	end

	local new_data = {
		items = items,
		fluids = fluids,
		fuel = fuel,
		belts = belts,
		modules = modules,
		groups = item_groups,
		resources = resources,
		crafting_machines = crafters,
		mining_drills = drills,
		rocket_silo = silo,
	}

	-- Normalize recipes
	local normal_recipes = {}
	local expensive_recipes = {}
	for name, raw_recipe in sorted_pairs(data["recipe"]) do
		for i, r in ipairs({{recipe_type = "normal", recipes = normal_recipes}, {recipe_type = "expensive", recipes = expensive_recipes}}) do
			local recipe = make_recipe(locale, r.recipe_type, raw_recipe, item_map, prod_recipes)
			if not recipe or recipe.subgroup == "empty-barrel" or recipe.subgroup == "fill-barrel" then
				goto continue
			end
			table.insert(r.recipes, recipe)
			::continue::
		end
	end

	local icon_groups = {
		items,
		belts,
		crafters,
		drills,
		resources,
		silo,
		normal_recipes,
		expensive_recipes,
	}
	for i, group in ipairs(icon_groups) do
		for _, obj in ipairs(group) do
			if obj.icon == nil then
				msg("nil icon:", i, obj.key)
			else
				icon_paths[obj.icon] = true
			end
		end
	end
	local icons = {}
	for path, v in pairs(icon_paths) do
		table.insert(icons, path)
	end
	table.sort(icons, icon_compare)
	local width = math.floor(math.sqrt(#icons))
	local icon_map = {}
	local resolved_icons = {}
	for i, path in ipairs(icons) do
		local row = math.floor((i - 1) / width)
		local col = (i - 1) % width
		icon_map[path] = {col = col, row = row}
		table.insert(resolved_icons, get_icon(data, path))
	end
	local mod = icon_map[no_module_icon]
	local clock = icon_map[clock_icon]
	-- The hash gets added later.
	new_data["sprites"] = {
		extra = {
			slot_icon_module = {
				name = "no module",
				icon_col = mod.col,
				icon_row = mod.row,
			},
			clock = {
				name = "time",
				icon_col = clock.col,
				icon_row = clock.row,
			},
		},
	}
	for i, group in ipairs(icon_groups) do
		for _, d in ipairs(group) do
			if d.icon ~= nil then
				local i = icon_map[d.icon]
				d["icon_col"] = i.col
				d["icon_row"] = i.row
				d.icon = nil
			end
		end
	end
	return {
		data = new_data,
		normal = normal_recipes,
		expensive = expensive_recipes,
		icons = resolved_icons,
		width = width,
		version = version,
	}
end

return Process
