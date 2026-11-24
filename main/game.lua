--- Игровая логика «Квадрок» (чистый Lua, без зависимостей от движка).
--- Поле по умолчанию 20x20 (размер задаётся настройкой M.FIELD_SIZE).
--- В центре поля находится квадрат 5x5, выделенный контуром:
--- именно в нём появляются новые фигуры-тетромино.
---
--- Игрок тапом захватывает фигуру и тащит её в любом направлении. Пока фигура
--- в руке, её положение привязано к клеткам поля (квантизация). Отпущенная
--- фигура остаётся, только если она опирается на край поля или на ранее
--- поставленную фигуру; иначе она улетает обратно в центр зоны появления.
---
--- Зона появления должна оставаться свободной: ставить фигуру поверх неё
--- нельзя, а если новая фигура не помещается в центре — партия заканчивается.
---
--- Функция M.danger() показывает, насколько плотно фигуры подступили
--- к контуру: 0 — вокруг пусто, 1 — фигуры вплотную.

local M = {}

--- Настройка: сторона игрового поля в клетках (по умолчанию 20x20).
M.FIELD_SIZE = 20

M.W = M.FIELD_SIZE
M.H = M.FIELD_SIZE

--- Сколько кубиков нужно разобрать за партию: S * S * 2 / 4, где S = FIELD_SIZE.
M.TOTAL_CELLS = math.floor(M.FIELD_SIZE * M.FIELD_SIZE * 2 / 4)

--- Сторона центрального квадрата появления фигур (в клетках).
M.ZONE = 5

--- Левый нижний угол зоны появления.
M.ZONE_X = math.floor((M.W - M.ZONE) / 2)
M.ZONE_Y = math.floor((M.H - M.ZONE) / 2)

--- Радиус (в клетках), в пределах которого близость фигур влияет на цвет контура.
M.DANGER_RADIUS = 7

--- Сумма весов близости, при которой контур считается полностью красным.
M.DANGER_SATURATION = 10

--- Считать ли касание углом (по диагонали) опорой для фигуры.
M.TOUCH_DIAGONAL = false

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

--- Свободны ли все клетки фигуры в данной позиции.
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

--- Можно ли вообще поставить фигуру в эту позицию: клетки свободны и зона
--- появления не задета (зона должна оставаться свободной для новых фигур).
function M.can_drop(board, cells, px, py)
	return M.can_place(board, cells, px, py) and not M.overlaps_zone(cells, px, py)
end

--- Касается ли клетка границы игрового поля.
function M.on_border(x, y)
	return x == 0 or x == M.W - 1 or y == 0 or y == M.H - 1
end

local SUPPORT_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local SUPPORT_DIRS_DIAGONAL = {
	{ 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
	{ 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}

--- Есть ли у фигуры опора: касание границы поля или ранее поставленной фигуры.
--- Без опоры отпущенная фигура не остаётся на поле.
function M.has_support(board, cells, px, py)
	local dirs = M.TOUCH_DIAGONAL and SUPPORT_DIRS_DIAGONAL or SUPPORT_DIRS
	for i = 1, #cells do
		local x = px + cells[i][1]
		local y = py + cells[i][2]
		if M.on_border(x, y) then
			return true
		end
		for d = 1, #dirs do
			local nx = x + dirs[d][1]
			local ny = y + dirs[d][2]
			if nx >= 0 and nx < M.W and ny >= 0 and ny < M.H then
				if board[ny][nx] ~= 0 then
					return true
				end
			end
		end
	end
	return false
end

--- Есть ли на поле хоть одна позиция, куда эту фигуру можно поставить:
--- клетки свободны, зона появления не задета и есть опора.
function M.has_any_drop(board, piece)
	local cells = piece.cells
	local max_x = M.W - piece.w
	local max_y = M.H - piece.h
	for py = 0, max_y do
		for px = 0, max_x do
			if M.can_drop(board, cells, px, py)
				and M.has_support(board, cells, px, py) then
				return true
			end
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

--- Ограничение позиции фигуры рамками поля.
function M.clamp_pos(piece, px, py)
	local max_x = M.W - piece.w
	local max_y = M.H - piece.h
	if px < 0 then
		px = 0
	elseif px > max_x then
		px = max_x
	end
	if py < 0 then
		py = 0
	elseif py > max_y then
		py = max_y
	end
	return px, py
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

--- Убирает кубики из полностью заполненных рядов и столбцов.
--- Ряд или столбец считается заполненным, только если в нём нет пробелов.
---
--- Возвращает:
---   cells — массив убранных клеток { x, y, color, order }, где order —
---           позиция клетки внутри линии (для каскадной анимации удаления):
---           для ряда — слева направо, для столбца — сверху вниз;
---   rows  — таблица «удалённый ряд» (ключ — индекс ряда);
---   cols  — таблица «удалённый столбец» (ключ — индекс столбца).
function M.clear_lines(board)
	local rows = {}
	local cols = {}
	local has_full = false

	for y = 0, M.H - 1 do
		local row = board[y]
		local full = true
		for x = 0, M.W - 1 do
			if row[x] == 0 then
				full = false
				break
			end
		end
		if full then
			rows[y] = true
			has_full = true
		end
	end

	for x = 0, M.W - 1 do
		local full = true
		for y = 0, M.H - 1 do
			if board[y][x] == 0 then
				full = false
				break
			end
		end
		if full then
			cols[x] = true
			has_full = true
		end
	end

	if not has_full then
		return {}, nil, nil
	end

	local cells = {}
	for y = 0, M.H - 1 do
		local row = board[y]
		for x = 0, M.W - 1 do
			if (rows[y] or cols[x]) and row[x] ~= 0 then
				-- Ряд идёт слева направо, столбец — сверху вниз (ряд 0 — нижний).
				local in_row = rows[y]
				local col_order = M.H - 1 - y
				local order
				if in_row and cols[x] then
					order = math.min(x, col_order)
				elseif in_row then
					order = x
				else
					order = col_order
				end

				cells[#cells + 1] = { x = x, y = y, color = row[x], order = order }
				row[x] = 0
			end
		end
	end

	return cells, rows, cols
end

--- Вычисляет сдвиги кубиков, примыкающих к удалённым линиям, к ближайшей
--- стороне поля. Сдвигается только связная группа, непосредственно примыкающая
--- к удалённой линии: кубики за пробелом остаются на месте.
--- Поле не изменяется — только возвращается список перемещений.
---
--- Возвращает массив перемещений { from_x, from_y, to_x, to_y, color }.
function M.collapse(board, rows, cols)
	local moves = {}

	--- Присоединяет перемещение к уже начатому, если кубик сдвигается повторно.
	local function add_move(from_x, from_y, to_x, to_y, color)
		for i = 1, #moves do
			local m = moves[i]
			if m.to_x == from_x and m.to_y == from_y then
				m.to_x = to_x
				m.to_y = to_y
				return
			end
		end
		moves[#moves + 1] = {
			from_x = from_x,
			from_y = from_y,
			to_x = to_x,
			to_y = to_y,
			color = color,
		}
	end

	-- Вертикальные сдвиги по удалённым рядам.
	if rows then
		local y = 0
		while y < M.H do
			if rows[y] then
				local lo = y
				while y + 1 < M.H and rows[y + 1] do
					y = y + 1
				end
				local hi = y
				local count = hi - lo + 1
				-- Направление — к ближайшей горизонтальной стороне поля.
				-- Если пустота ближе к верху, кубики под ней поднимаются вверх,
				-- и наоборот: если ближе к низу — кубики над ней опускаются.
				local up = (lo + hi) * 0.5 >= (M.H - 1) * 0.5

				for x = 0, M.W - 1 do
					if up then
						-- Связная цепочка кубиков непосредственно под пустотой.
						-- Идём от ближайшего к пустоте кубика вниз, чтобы не
						-- затирать ещё не перенесённые клетки.
						local cy = lo - 1
						while cy >= 0 and board[cy][x] ~= 0 do
							local to_y = cy + count
							local color = board[cy][x]
							board[to_y][x] = color
							board[cy][x] = 0
							add_move(x, cy, x, to_y, color)
							cy = cy - 1
						end
					else
						-- Связная цепочка кубиков непосредственно над пустотой.
						local cy = hi + 1
						while cy < M.H and board[cy][x] ~= 0 do
							local to_y = cy - count
							local color = board[cy][x]
							board[to_y][x] = color
							board[cy][x] = 0
							add_move(x, cy, x, to_y, color)
							cy = cy + 1
						end
					end
				end
			end
			y = y + 1
		end
	end

	-- Горизонтальные сдвиги по удалённым столбцам.
	if cols then
		local x = 0
		while x < M.W do
			if cols[x] then
				local lo = x
				while x + 1 < M.W and cols[x + 1] do
					x = x + 1
				end
				local hi = x
				local count = hi - lo + 1
				-- Направление — к ближайшей вертикальной стороне поля.
				local left = (lo + hi) * 0.5 <= (M.W - 1) * 0.5

				for y = 0, M.H - 1 do
					if left then
						-- Цепочка кубиков справа от пустоты сдвигается влево.
						local cx = hi + 1
						while cx < M.W and board[y][cx] ~= 0 do
							local to_x = cx - count
							local color = board[y][cx]
							board[y][to_x] = color
							board[y][cx] = 0
							add_move(cx, y, to_x, y, color)
							cx = cx + 1
						end
					else
						-- Цепочка кубиков слева от пустоты сдвигается вправо.
						local cx = lo - 1
						while cx >= 0 and board[y][cx] ~= 0 do
							local to_x = cx + count
							local color = board[y][cx]
							board[y][to_x] = color
							board[y][cx] = 0
							add_move(cx, y, to_x, y, color)
							cx = cx - 1
						end
					end
				end
			end
			x = x + 1
		end
	end

	return moves
end

--- Полная копия поля.
function M.clone_board(board)
	local copy = {}
	for y = 0, M.H - 1 do
		local row = {}
		local src = board[y]
		for x = 0, M.W - 1 do
			row[x] = src[x]
		end
		copy[y] = row
	end
	return copy
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
