--[[

	TechAge
	=======

	Copyright (C) 2019-2022 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

	TA4 Electrolyzer - Модифицированная версия с потреблением воды

]]--

-- for lazy programmers
local M = minetest.get_meta
local S = techage.S

local Cable = techage.ElectricCable
local power = networks.power
local Pipe = techage.LiquidPipe
local liquid = networks.liquid

local CYCLE_TIME = 2
local STANDBY_TICKS = 3
local PWR_NEEDED = 35
local PWR_UNITS_PER_HYDROGEN_ITEM = 80
local WATER_PER_HYDROGEN = 10 -- Количество воды для производства 1 единицы водорода
local CAPACITY = 200
local INPUT_CAPACITY = 1000 -- Вместимость для входной воды
local TURNOFF_THRESHOLD = "40%"

local function evaluate_percent(s)
	return (tonumber(s:sub(1, -2)) or 0) / 100
end

local function formspec(self, pos, nvm)
	local amount = (nvm.liquid and nvm.liquid.amount) or 0
	local lqd_name = (nvm.liquid and nvm.liquid.name) or "techage:liquid"

	local water_amount = (nvm.water and nvm.water.amount) or 0
	local water_name = (nvm.water and nvm.water.name) or "techage:water"

	local arrow = "image[3,1.5;1,1;techage_form_arrow_bg.png^[transformR270]"
	if techage.is_running(nvm) then
		arrow = "image[3,1.5;1,1;techage_form_arrow_fg.png^[transformR270]"
	end

	if amount > 0 then
		lqd_name = lqd_name .. " " .. amount
	end

	if water_amount > 0 then
		water_name = water_name .. " " .. water_amount
	end

	return "size[6,5]" ..
		default.gui_bg ..
		default.gui_bg_img ..
		default.gui_slots ..
		"box[0,-0.1;5.8,0.5;#c6e8ff]" ..
		"label[0.2,-0.1;" .. minetest.colorize( "#000000", S("Electrolyzer")) .. "]" ..
		techage.wrench_tooltip(5.4, -0.1)..
		techage.formspec_power_bar(pos, 0.1, 0.8, S("Electricity"), nvm.taken, PWR_NEEDED) ..
		arrow ..
		"image_button[3,2.5;1,1;" .. self:get_state_button_image(nvm) .. ";state_button;]" ..
		"tooltip[3,2.5;1,1;" .. self:get_state_tooltip(nvm) .. "]" ..
		techage.item_image(4.5, 1.5, lqd_name) ..
		"label[4.2,1.2;" .. S("Hydrogen") .. "]" ..
		techage.item_image(4.5, 2.8, water_name) ..
		"label[4.2,2.5;" .. S("Water") .. "]" ..
		"label[0.2,3.8;" .. S("Water input (B)") .. "]" ..
		"label[0.2,4.3;" .. S("Hydrogen output (F)") .. "]"
end

local function can_start(pos, nvm, state)
	nvm.liquid = nvm.liquid or {}
	nvm.liquid.amount = nvm.liquid.amount or 0
	nvm.water = nvm.water or {}
	nvm.water.amount = nvm.water.amount or 0

	if nvm.liquid.amount >= CAPACITY then
		return S("Hydrogen storage full")
	end

	if nvm.water.amount < WATER_PER_HYDROGEN then
		return S("Not enough water")
	end

	return true
end

local function start_node(pos, nvm, state)
	nvm.taken  = 0
	nvm.reduction = evaluate_percent(M(pos):get_string("reduction"))
	nvm.turnoff = evaluate_percent(M(pos):get_string("turnoff"))
end

local function stop_node(pos, nvm, state)
	nvm.taken = 0
	nvm.running = nil -- legacy
end

local State = techage.NodeStates:new({
	node_name_passive = "techage:ta4_electrolyzer",
	node_name_active = "techage:ta4_electrolyzer_on",
	cycle_time = CYCLE_TIME,
	standby_ticks = STANDBY_TICKS,
	formspec_func = formspec,
	infotext_name = S("TA4 Electrolyzer"),
	can_start = can_start,
	start_node = start_node,
	stop_node = stop_node,
})

local function generating(pos, nvm)
	nvm.num_pwr_units = nvm.num_pwr_units or 0
	nvm.countdown = nvm.countdown or 0

	if nvm.taken > 0 and nvm.water and nvm.water.amount >= WATER_PER_HYDROGEN then
		nvm.num_pwr_units = nvm.num_pwr_units + (nvm.taken or 0)

		if nvm.num_pwr_units >= PWR_UNITS_PER_HYDROGEN_ITEM then
			-- Проверяем, есть ли место для водорода
			if nvm.liquid.amount < CAPACITY then
				-- Потребляем воду
				nvm.water.amount = nvm.water.amount - WATER_PER_HYDROGEN
				nvm.water.name = "techage:water"

				-- Производим водород
				nvm.liquid.amount = nvm.liquid.amount + 1
				nvm.liquid.name = "techage:hydrogen"
				nvm.num_pwr_units = nvm.num_pwr_units - PWR_UNITS_PER_HYDROGEN_ITEM
			end
		end
	end
end

-- converts water and power into hydrogen
local function node_timer(pos, elapsed)
	local meta = M(pos)
	local nvm = techage.get_nvm(pos)

	-- Инициализация хранилищ
	nvm.liquid = nvm.liquid or {}
	nvm.liquid.amount = nvm.liquid.amount or 0
	nvm.liquid.name = nvm.liquid.name or "techage:hydrogen"

	nvm.water = nvm.water or {}
	nvm.water.amount = nvm.water.amount or 0
	nvm.water.name = nvm.water.name or "techage:water"

	-- Проверяем условия для работы
	if nvm.liquid.amount < CAPACITY then
		local in_dir = meta:get_int("in_dir")
		local curr_load = power.get_storage_load(pos, Cable, in_dir, 1)

		-- Проверяем наличие воды
		local has_water = nvm.water.amount >= WATER_PER_HYDROGEN

		if curr_load > (nvm.turnoff or 0) and has_water then
			local to_be_taken = PWR_NEEDED * (nvm.reduction or 1)
			nvm.taken = power.consume_power(pos, Cable, in_dir, to_be_taken) or 0
			local running = techage.is_running(nvm)

			if not running and nvm.taken == to_be_taken then
				State:start(pos, nvm)
			elseif running and nvm.taken < to_be_taken then
				State:nopower(pos, nvm)
			elseif running then
				generating(pos, nvm)
				State:keep_running(pos, nvm, 1)
			end
		elseif not has_water then
			nvm.taken = 0
			State:standby(pos, nvm, S("Not enough water"))
		elseif curr_load == 0 then
			nvm.taken = 0
			State:nopower(pos, nvm)
		else
			nvm.taken = 0
			State:standby(pos, nvm, S("Turnoff point reached"))
		end
	else
		nvm.taken = 0
		State:blocked(pos, nvm, S("Hydrogen storage full"))
	end

	if techage.is_activeformspec(pos) then
		M(pos):set_string("formspec", formspec(State, pos, nvm))
	end
	return true
end

local function on_receive_fields(pos, formname, fields, player)
	if minetest.is_protected(pos, player:get_player_name()) then
		return
	end
	local nvm = techage.get_nvm(pos)
	techage.set_activeformspec(pos, player)
	State:state_button_event(pos, nvm, fields)
	M(pos):set_string("formspec", formspec(State, pos, nvm))
end

local function on_rightclick(pos, node, clicker)
	local nvm = techage.get_nvm(pos)
	techage.set_activeformspec(pos, clicker)
	M(pos):set_string("formspec", formspec(State, pos, nvm))
end

local function after_place_node(pos)
	local nvm = techage.get_nvm(pos)
	nvm.running = false
	nvm.num_pwr_units = 0
	-- Инициализация хранилищ
	nvm.water = {amount = 0, name = "techage:water"}
	nvm.liquid = {amount = 0, name = "techage:hydrogen"}

	local number = techage.add_node(pos, "techage:ta4_electrolyzer")
	State:node_init(pos, nvm, number)
	local node = minetest.get_node(pos)
	M(pos):set_int("in_dir", techage.side_to_indir("R", node.param2))
	M(pos):set_string("reduction", "100%")
	M(pos):set_string("turnoff", TURNOFF_THRESHOLD)
	Pipe:after_place_node(pos)
	Cable:after_place_node(pos)
end

local function after_dig_node(pos, oldnode, oldmetadata, digger)
	Pipe:after_dig_node(pos)
	Cable:after_dig_node(pos)
end

local function can_dig(pos, player)
	if minetest.is_protected(pos, player:get_player_name()) then
		return false
	end
	-- Проверяем оба хранилища
	local nvm = techage.get_nvm(pos)
	local water_empty = (not nvm.water or nvm.water.amount == 0)
	local hydrogen_empty = (not nvm.liquid or nvm.liquid.amount == 0)
	return water_empty and hydrogen_empty
end

-- Определения для жидкости (водород)
local liquid_def = {
	capa = CAPACITY,
	peek = function(pos)
		local nvm = techage.get_nvm(pos)
		return liquid.srv_peek(nvm.liquid)
	end,
	put = function(pos, indir, name, amount)
		local nvm = techage.get_nvm(pos)
		-- Вход для водорода (обычно не используется, так как водород производится)
		if name == "techage:hydrogen" then
			local leftover = liquid.srv_put(nvm.liquid, name, amount, CAPACITY)
			if techage.is_activeformspec(pos) then
				M(pos):set_string("formspec", formspec(State, pos, nvm))
			end
			return leftover
		end
		return amount -- Не принимаем другую жидкость
	end,
	take = function(pos, indir, name, amount)
		local nvm = techage.get_nvm(pos)
		if name == "techage:hydrogen" then
			amount, name = liquid.srv_take(nvm.liquid, name, amount)
			if techage.is_activeformspec(pos) then
				M(pos):set_string("formspec", formspec(State, pos, nvm))
			end
			return amount, name
		end
		return 0, name
	end,
	untake = function(pos, indir, name, amount)
		local nvm = techage.get_nvm(pos)
		if name == "techage:hydrogen" then
			local leftover = liquid.srv_put(nvm.liquid, name, amount, CAPACITY)
			if techage.is_activeformspec(pos) then
				M(pos):set_string("formspec", formspec(State, pos, nvm))
			end
			return leftover
		end
		return amount
	end,
}

-- Определения для воды (входная жидкость)
local water_def = {
	capa = INPUT_CAPACITY,
	peek = function(pos)
		local nvm = techage.get_nvm(pos)
		return liquid.srv_peek(nvm.water)
	end,
	put = function(pos, indir, name, amount)
		local nvm = techage.get_nvm(pos)
		-- Принимаем только воду
		if name == "techage:water" then
			local leftover = liquid.srv_put(nvm.water, name, amount, INPUT_CAPACITY)
			if techage.is_activeformspec(pos) then
				M(pos):set_string("formspec", formspec(State, pos, nvm))
			end
			return leftover
		end
		return amount -- Отклоняем другую жидкость
	end,
	take = function(pos, indir, name, amount)
		-- Обычно вода не забирается из электролизера
		return 0, name
	end,
	untake = function(pos, indir, name, amount)
		local nvm = techage.get_nvm(pos)
		if name == "techage:water" then
			local leftover = liquid.srv_put(nvm.water, name, amount, INPUT_CAPACITY)
			if techage.is_activeformspec(pos) then
				M(pos):set_string("formspec", formspec(State, pos, nvm))
			end
			return leftover
		end
		return amount
	end,
}

minetest.register_node("techage:ta4_electrolyzer", {
	description = S("TA4 Electrolyzer (Water)"),
	tiles = {
		-- up, down, right, left, back, front
		"techage_filling_ta4.png^techage_frame_ta4_top.png^techage_appl_arrow.png",
		"techage_filling_ta4.png^techage_frame_ta4.png",
		"techage_filling_ta4.png^techage_frame_ta4.png^techage_appl_hole_pipe.png", -- Выход водорода (F)
		"techage_filling_ta4.png^techage_frame_ta4.png^techage_appl_hole_electric.png", -- Вход электричества (L)
		"techage_filling_ta4.png^techage_frame_ta4.png^techage_appl_electrolyzer.png^techage_appl_ctrl_unit.png^[transformFX",
		"techage_filling_ta4.png^techage_frame_ta4.png^techage_appl_electrolyzer.png^techage_appl_ctrl_unit.png",
	},

	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
		},
	},

	can_dig = can_dig,
	after_place_node = after_place_node,
	after_dig_node = after_dig_node,
	on_punch = liquid.on_punch,
	on_receive_fields = on_receive_fields,
	on_timer = node_timer,
	on_rightclick = on_rightclick,

	paramtype2 = "facedir",
	groups = {cracky=2, crumbly=2, choppy=2},
	on_rotate = screwdriver.disallow,
	is_ground_content = false,
	sounds = default.node_sound_metal_defaults(),
	ta3_formspec = {
		{
			type = "const",
			name = "needed",
			label = S("Maximum power consumption [ku]"),
			tooltip = S("Maximum possible\ncurrent consumption"),
			value = PWR_NEEDED,
		},
		{
			type = "dropdown",
			choices = "20%,40%,60%,80%,100%",
			name = "reduction",
			label = S("Current limitation"),
			tooltip = S("Configurable value\nfor the current limit"),
			default = "100%",
		},
		{
			type = "dropdown",
			choices = "0%,20%,40%,60%,80%,98%",
			name = "turnoff",
			label = S("Turnoff point"),
			tooltip = S("If the charge of the storage\nsystem falls below the configured value,\nthe block switches off"),
			default = TURNOFF_THRESHOLD,
		},
		{
			type = "const",
			name = "water_need",
			label = S("Water per hydrogen"),
			tooltip = S("Amount of water needed\nto produce 1 hydrogen"),
			value = WATER_PER_HYDROGEN,
		},
	},
})

minetest.register_node("techage:ta4_electrolyzer_on", {
	description = S("TA4 Electrolyzer (Water)"),
	tiles = {
		-- up, down, right, left, back, front
		"techage_filling_ta4.png^techage_frame_ta4_top.png^techage_appl_arrow.png",
		"techage_filling_ta4.png^techage_frame_ta4.png",
		"techage_filling_ta4.png^techage_frame_ta4.png^techage_appl_hole_pipe.png", -- Выход водорода (F)
		"techage_filling_ta4.png^techage_frame_ta4.png^techage_appl_hole_electric.png", -- Вход электричества (L)
		{
			name = "techage_filling4_ta4.png^techage_frame4_ta4.png^techage_appl_electrolyzer4.png^techage_appl_ctrl_unit4.png^[transformFX",
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 32,
				aspect_h = 32,
				length = 0.8,
			},
		},
		{
			name = "techage_filling4_ta4.png^techage_frame4_ta4.png^techage_appl_electrolyzer4.png^techage_appl_ctrl_unit4.png",
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 32,
				aspect_h = 32,
				length = 0.8,
			},
		},
	},

	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
		},
	},

	on_receive_fields = on_receive_fields,
	on_punch = liquid.on_punch,
	on_timer = node_timer,
	on_rightclick = on_rightclick,

	paramtype2 = "facedir",
	groups = {not_in_creative_inventory=1},
	on_rotate = screwdriver.disallow,
	is_ground_content = false,
	diggable = false,
	paramtype = "light",
	light_source = 6,
	sounds = default.node_sound_metal_defaults(),
	ta3_formspec = {
		{
			type = "const",
			name = "needed",
			label = S("Maximum power consumption [ku]"),
			tooltip = S("Maximum possible\ncurrent consumption"),
			value = PWR_NEEDED,
		},
		{
			type = "dropdown",
			choices = "20%,40%,60%,80%,100%",
			name = "reduction",
			label = S("Current limitation"),
			tooltip = S("Configurable value\nfor the current limit"),
			default = "100%",
		},
		{
			type = "dropdown",
			choices = "0%,20%,40%,60%,80%,98%",
			name = "turnoff",
			label = S("Turnoff point"),
			tooltip = S("If the charge of the storage\nsystem falls below the configured value,\nthe block switches off"),
			default = TURNOFF_THRESHOLD,
		},
		{
			type = "const",
			name = "water_need",
			label = S("Water per hydrogen"),
			tooltip = S("Amount of water needed\nto produce 1 hydrogen"),
			value = WATER_PER_HYDROGEN,
		},
	},
})

-- Регистрируем две отдельные системы жидкостей
-- 1. Для водорода (выход) на стороне R
liquid.register_nodes({"techage:ta4_electrolyzer", "techage:ta4_electrolyzer_on"}, Pipe, "tank", {"R"}, liquid_def)

-- 2. Для воды (вход) на стороне B
liquid.register_nodes({"techage:ta4_electrolyzer", "techage:ta4_electrolyzer_on"}, Pipe, "tank2", {"B"}, water_def)

-- Регистрируем электрическое соединение на стороне L
power.register_nodes({"techage:ta4_electrolyzer", "techage:ta4_electrolyzer_on"}, Cable, "con", {"L"})

techage.register_node({"techage:ta4_electrolyzer", "techage:ta4_electrolyzer_on"}, {
	on_recv_message = function(pos, src, topic, payload)
		local nvm = techage.get_nvm(pos)
		if topic == "load" then
			-- Возвращаем заполненность водородом
			return techage.power.percent(CAPACITY, (nvm.liquid and nvm.liquid.amount) or 0)
		elseif topic == "water" then
			-- Возвращаем количество воды
			return (nvm.water and nvm.water.amount) or 0
		elseif topic == "delivered" then
			return -math.floor((nvm.taken or 0) + 0.5)
		else
			return State:on_receive_message(pos, topic, payload)
		end
	end,
	on_beduino_receive_cmnd = function(pos, src, topic, payload)
		return State:on_beduino_receive_cmnd(pos, topic, payload)
	end,
	on_beduino_request_data = function(pos, src, topic, payload)
		local nvm = techage.get_nvm(pos)
		if topic == 134 and payload[1] == 1 then
			-- Заполненность водородом
			return 0, {techage.power.percent(CAPACITY, (nvm.liquid and nvm.liquid.amount) or 0)}
		elseif topic == 134 and payload[1] == 2 then
			-- Количество воды
			return 0, {(nvm.water and nvm.water.amount) or 0}
		elseif topic == 135 then
			-- Потребляемая мощность
			return 0, {math.floor((nvm.taken or 0) + 0.5)}
		else
			return State:on_beduino_request_data(pos, topic, payload)
		end
	end,
	on_node_load = function(pos, node)
		local meta = M(pos)
		if not meta:contains("reduction") then
			meta:set_string("reduction", "100%")
			meta:set_string("turnoff", TURNOFF_THRESHOLD)
		end
		-- Инициализируем NVM при загрузке
		local nvm = techage.get_nvm(pos)
		nvm.water = nvm.water or {amount = 0, name = "techage:water"}
		nvm.liquid = nvm.liquid or {amount = 0, name = "techage:hydrogen"}
	end,
})

minetest.register_craft({
	output = "techage:ta4_electrolyzer",
	recipe = {
		{'default:steel_ingot', 'dye:blue', 'default:steel_ingot'},
		{'techage:electric_cableS', 'bucket:bucket_water', 'techage:ta3_pipeS'},
		{'default:steel_ingot', "techage:ta4_wlanchip", 'default:steel_ingot'},
	},
})
