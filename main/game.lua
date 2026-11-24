--- Игровая логика «Квадрок» (чистый Lua, без зависимостей от движка).
---
--- Поле 30x30. В центре поля находится квадрат 5x5, выделенный контуром:
--- именно в нём появляются новые фигуры-тетромино. Игрок свайпом уводит
--- фигуру к одной из сторон, и она фиксируется, заполняя поле вокруг зоны.
---
--- Зона появления должна оставаться свободной. Если после свайпа фигура
--- так и не смогла полностью покинуть квадрат (пересекла контур) — партия
--- заканчивается.
---
--- Функция M.danger() показывает, насколько плотно фигуры подступили
--- к контуру: 0 — вокруг пусто, 1 — фигуры вплотную.

local M = {}

M.W = 30
M.H = 30

--- Сторона центрального квадрата появления фигур (в клетках).
M.ZONE = 5

--- Левый нижний угол зоны появления.
M.ZONE_X = math.floor((M.W - M.ZONE) / 2)
M.ZONE_Y = math.floor((M.H - M.ZONE) / 2)

--- Радиус (в клетках), в пределах которого близость фигур влияет на цвет контура.
M.DANGER_RADIUS = 7

--- Сумма весов близости, при которой контур считается полностью красным.
M.DANGER_SATURATION = 10

M.SIDE_LEFT = 1
M.SIDE_RIGHT = 2
M.SIDE_BOTTOM = 3
M.SIDE_TOP = 4

local BASE_SHAPES = {
	{ cells = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 } }, color = 1 }, -- I
	{ cells = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }, color = 2 }, -- O
	{ cells = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 } }, color = 3 }, -- T
	{ cells = { { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } }, color = 4 }, -- S
	{ cells = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } }, color = 5 }, -- Z
	{ cells = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } }, color = 6 }, -- J
	{ cells = { { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } }, color = 7 }, -- L
}

local function normalize(cells)
	local min_x, min_y = math.huge, math.huge
	for i = 1, #cells do
		local c = cells[i]
		if c[1] < min_x then min_x = c[1] end
		if c[2] < min_y then min_y = c[2] end
	end
	local out = {}
	for i = 1, #cells do
		out[i] = { cells[i][1] - min_x, cells[i][2] - min_y }
	end
	return out
end

local function rotate_cw(cells)
	local max_y = 0
	for i = 1, #cells do
		if cells[i][2] > max_y then max_y = cells[i][2] end
	end
	local out = {}
	for i = 1, #cells do
		out[i] = { max_y - cells[i][2], cells[i][1] }
	end
	return normalize(out)
end

local function signature(cells)
	local parts = {}
	for i = 1, #cells do
		parts[i] = cells[i][1] .. ":" .. cells[i][2]
	end
	table.sort(parts)
	return table.concat(parts, ";")
end

M.SHAPES = {}
for i = 1, #BASE_SHAPES do
	local shape = { variants = {}, color = BASE_SHAPES[i].color }
	local seen = {}
	local cells = normalize(BASE_SHAPES[i].cells)
	for _ = 1, 4 do
		local sig = signature(cells)
		if not seen[sig] then
			seen[sig] = true
			shape.variants[#shape.variants + 1] = cells
		end
		cells = rotate_cw(cells)
	end
	M.SHAPES[i] = shape
end

function M.new_board()
	local board = {}
	for y = 0, M.H - 1 do
		local row = {}
		for x = 0, M.W - 1 do
			row[x] = 0
		end
		board[y] = row
	end
	return board
end

--- Случайная фигура (случайная форма и случайный поворот).
function M.random_piece()
	local shape = M.SHAPES[math.random(#M.SHAPES)]
	local cells = shape.variants[math.random(#shape.variants)]

	local w, h = 0, 0
	for i = 1, #cells do
		if cells[i][1] + 1 > w then w = cells[i][1] + 1 end
		if cells[i][2] + 1 > h then h = cells[i][2] + 1 end
	end

	return { cells = cells, w = w, h = h, color = shape.color }
end

function M.can_place(board, cells, px, py)
	for i = 1, #cells do
		local x = px + cells[i][1]
		local y = py + cells[i][2]
		if x < 0 or x >= M.W or y < 0 or y >= M.H then
			return false
		end
		if board[y][x] ~= 0 then
			return false
		end
	end
	return true
end

--- Клетка внутри центральной зоны появления?
function M.in_zone(x, y)
	return x >= M.ZONE_X and x < M.ZONE_X + M.ZONE
		and y >= M.ZONE_Y and y < M.ZONE_Y + M.ZONE
end

--- Пересекает ли фигура контур зоны появления.
function M.overlaps_zone(cells, px, py)
	for i = 1, #cells do
		if M.in_zone(px + cells[i][1], py + cells[i][2]) then
			return true
		end
	end
	return false
end

--- Позиция появления: по центру зоны.
function M.spawn_pos(piece)
	local x = M.ZONE_X + math.floor((M.ZONE - piece.w) / 2)
	local y = M.ZONE_Y + math.floor((M.ZONE - piece.h) / 2)
	return x, y
end

--- Расстояние Чебышёва от клетки до прямоугольника зоны (0 — внутри).
local function zone_distance(x, y)
	local dx = 0
	if x < M.ZONE_X then
		dx = M.ZONE_X - x
	elseif x > M.ZONE_X + M.ZONE - 1 then
		dx = x - (M.ZONE_X + M.ZONE - 1)
	end

	local dy = 0
	if y < M.ZONE_Y then
		dy = M.ZONE_Y - y
	elseif y > M.ZONE_Y + M.ZONE - 1 then
		dy = y - (M.ZONE_Y + M.ZONE - 1)
	end

	return math.max(dx, dy)
end

--- Насколько близко зафиксированные фигуры подступили к контуру: 0..1.
function M.danger(board)
	local radius = M.DANGER_RADIUS
	local sum = 0

	for y = 0, M.H - 1 do
		local row = board[y]
		for x = 0, M.W - 1 do
			if row[x] ~= 0 then
				local d = zone_distance(x, y)
				if d <= 1 then
					sum = sum + 1
				elseif d <= radius then
					sum = sum + (radius - d + 1) / radius
				end
			end
		end
	end

	local value = sum / M.DANGER_SATURATION
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

function M.place(board, cells, px, py, color)
	local placed = {}
	for i = 1, #cells do
		local x = px + cells[i][1]
		local y = py + cells[i][2]
		board[y][x] = color
		placed[#placed + 1] = { x, y }
	end
	return placed
end

--- Сдвиг фигуры до упора в заданном направлении.
function M.slide(board, cells, px, py, dx, dy)
	local steps = 0
	local limit = (M.W + M.H) * 4
	while steps < limit and M.can_place(board, cells, px + dx, py + dy) do
		px = px + dx
		py = py + dy
		steps = steps + 1
	end
	return px, py, steps
end

--- Направление сдвига для стороны поля.
function M.side_delta(side)
	if side == M.SIDE_LEFT then
		return -1, 0
	elseif side == M.SIDE_RIGHT then
		return 1, 0
	elseif side == M.SIDE_BOTTOM then
		return 0, -1
	end
	return 0, 1
end

--- Количество занятых клеток (для статистики).
function M.occupied(board)
	local n = 0
	for y = 0, M.H - 1 do
		for x = 0, M.W - 1 do
			if board[y][x] ~= 0 then n = n + 1 end
		end
	end
	return n
end

return M
