--- Игровая логика «Квадрок» (чистый Lua, без зависимостей от движка).
--- Поле начинается с 16x16 и растёт по уровням после каждой победы:
--- 16 → 18 → 20 → 21 → 23 → 25 (максимум) через M.set_field_size().
--- В центре поля находится стартовый квадрат, выделенный контуром:
--- 4x4 на полях 16–20 и 5x5 на полях 21–25. Именно в нём появляются новые
--- фигуры: в стартовом квадрате 4x4 — только тетромино (4 кубика), а в
--- стартовом квадрате 5x5 равновероятно выпадают и тетромино (4 кубика),
--- и пентамино (5 кубиков).
---
--- Игрок тапом захватывает фигуру и тащит её в любом направлении. Пока фигура
--- в руке, её положение привязано к клеткам поля (квантизация). Отпущенная
--- фигура остаётся, только если она опирается на край поля или на ранее
--- поставленную фигуру; иначе она улетает обратно в центр зоны появления.
---
--- Зона появления должна оставаться свободной: ставить фигуру поверх неё
--- нельзя, а если новая фигура не помещается в центре — партия заканчивается.
--- Функция M.fill_ratio() показывает, насколько заполнено игровое поле:
--- 0 — поле пустое, 1 — заполнено целиком. По ней окрашивается контур
--- стартового квадрата: зелёный -> жёлтый -> красный.

local M = {}

--- Размеры поля по уровням: 16, 18, 20 — со стартовым квадратом 4x4,
--- затем 21, 23, 25 — со стартовым квадратом 5x5 (максимальный размер поля).
M.LEVELS = { 16, 18, 20, 21, 23, 25 }

--- Минимальный размер поля — стартовый уровень.
M.MIN_FIELD_SIZE = M.LEVELS[1]
--- Максимальный размер поля: дальше усложнять некуда.
M.MAX_FIELD_SIZE = M.LEVELS[#M.LEVELS]

--- Наибольший размер поля со стартовым квадратом 4x4.
--- Начиная со следующего уровня (21x21) стартовый квадрат — 5x5.
M.ZONE_SWITCH_SIZE = 20

--- Сторона стартового квадрата для очередного размера поля.
function M.zone_for_size(size)
	if size <= M.ZONE_SWITCH_SIZE then
		return 4
	end
	return 5
end

--- Сторона игрового поля в клетках (текущий уровень).
M.FIELD_SIZE = M.MIN_FIELD_SIZE

M.W = M.FIELD_SIZE
M.H = M.FIELD_SIZE

--- Сколько кубиков нужно разобрать за партию: S * S * 2 / 4, где S = FIELD_SIZE.
M.TOTAL_CELLS = math.floor(M.FIELD_SIZE * M.FIELD_SIZE * 2 / 4)

--- Насколько растёт цель партии за каждый пройденный круг на максимальном поле.
M.EXTRA_CELLS_PER_ROUND = 100

--- Сколько дополнительных кругов на максимальном поле уже пройдено.
--- Влияет только на цель партии: поле остаётся максимального размера.
M.EXTRA_ROUNDS = 0

--- Цель партии для текущего поля с учётом пройденных кругов.
--- Когда поле достигло максимального размера, дальше усложняем не размером,
--- а количеством кубиков, которое нужно разобрать: +100 за каждый круг.
function M.total_cells()
	if M.FIELD_SIZE < M.MAX_FIELD_SIZE then
		return M.TOTAL_CELLS
	end
	return M.TOTAL_CELLS + M.EXTRA_ROUNDS * M.EXTRA_CELLS_PER_ROUND
end

--- Задаёт число пройденных дополнительных кругов (при загрузке прогресса).
function M.set_extra_rounds(rounds)
	rounds = tonumber(rounds) or 0
	if rounds < 0 then
		rounds = 0
	end
	M.EXTRA_ROUNDS = math.floor(rounds)
end

--- Увеличивает сложность после победы на максимальном поле: +1 круг (+100 кубиков).
function M.next_extra_rounds()
	return M.EXTRA_ROUNDS + 1
end

--- Сторона стартового квадрата (зоны появления фигур) в клетках.
M.ZONE = M.zone_for_size(M.FIELD_SIZE)

--- Левый нижний угол зоны появления.
M.ZONE_X = math.floor((M.W - M.ZONE) / 2)
M.ZONE_Y = math.floor((M.H - M.ZONE) / 2)

--- Приводит размер поля к допустимому уровню: 16, 18, 20, 21, 23, 25.
--- Для промежуточных значений берётся ближайший уровень не больше заданного:
--- так корректно читается прогресс, записанный прежней версией игры.
function M.normalize_field_size(size)
	size = tonumber(size)
	if not size then
		return M.MIN_FIELD_SIZE
	end
	size = math.floor(size)
	if size <= M.MIN_FIELD_SIZE then
		return M.MIN_FIELD_SIZE
	end

	local best = M.MIN_FIELD_SIZE
	for i = 1, #M.LEVELS do
		if M.LEVELS[i] <= size then
			best = M.LEVELS[i]
		end
	end
	return best
end

--- Делает поле заданного размера. Все функции ниже читают M.W, M.H,
--- M.ZONE, M.ZONE_X, M.ZONE_Y и M.TOTAL_CELLS динамически, поэтому смена
--- размера сразу применяется ко всей логике. Возвращает фактический размер.
function M.set_field_size(size)
	size = M.normalize_field_size(size)
	M.FIELD_SIZE = size
	M.W = size
	M.H = size
	M.TOTAL_CELLS = math.floor(size * size * 2 / 4)
	M.ZONE = M.zone_for_size(size)
	M.ZONE_X = math.floor((M.W - M.ZONE) / 2)
	M.ZONE_Y = math.floor((M.H - M.ZONE) / 2)
	M.apply_zone_shapes()
	return size
end

--- Следующий размер поля после победы или nil, если достигнут максимум.
--- Функция ничего не меняет: размер применяется через M.set_field_size().
function M.next_field_size(size)
	size = M.normalize_field_size(size)
	for i = 1, #M.LEVELS do
		if M.LEVELS[i] > size then
			return M.LEVELS[i]
		end
	end
	return nil
end

--- Считать ли касание углом (по диагонали) опорой для фигуры.
M.TOUCH_DIAGONAL = false

--- Тетромино (4 кубика) — детали для стартового квадрата 4x4.
local TETROMINOES = {
	{ cells = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 } }, color = 1 }, -- I
	{ cells = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }, color = 2 }, -- O
	{ cells = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 } }, color = 3 }, -- T
	{ cells = { { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } }, color = 4 }, -- S
	{ cells = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } }, color = 5 }, -- Z
	{ cells = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } }, color = 6 }, -- J
	{ cells = { { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } }, color = 7 }, -- L
}

--- Пентамино (5 кубиков) — детали для стартового квадрата 5x5.
local PENTOMINOES = {
	{ cells = { { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 }, { 1, 2 } }, color = 1 }, -- F
	{ cells = { { 0, 0 }, { 0, 1 }, { 0, 2 }, { 0, 3 }, { 0, 4 } }, color = 2 }, -- I
	{ cells = { { 0, 0 }, { 0, 1 }, { 0, 2 }, { 0, 3 }, { 1, 3 } }, color = 3 }, -- L
	{ cells = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0, 2 } }, color = 4 }, -- P
	{ cells = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { 0, 2 }, { 0, 3 } }, color = 5 }, -- N
	{ cells = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 }, { 1, 2 } }, color = 6 }, -- T
	{ cells = { { 0, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } }, color = 7 }, -- U
	{ cells = { { 0, 0 }, { 0, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } }, color = 1 }, -- V
	{ cells = { { 2, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { 0, 2 } }, color = 2 }, -- W
	{ cells = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 }, { 1, 2 } }, color = 3 }, -- X
	{ cells = { { 0, 0 }, { 0, 1 }, { 0, 2 }, { 0, 3 }, { 1, 1 } }, color = 4 }, -- Y
	{ cells = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 1, 2 }, { 2, 2 } }, color = 5 }, -- Z
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

--- Собирает набор фигур со всеми уникальными поворотами.
local function build_shapes(base)
	local shapes = {}
	for i = 1, #base do
		local shape = { variants = {}, color = base[i].color }
		local seen = {}
		local cells = normalize(base[i].cells)
		for _ = 1, 4 do
			local sig = signature(cells)
			if not seen[sig] then
				seen[sig] = true
				shape.variants[#shape.variants + 1] = cells
			end
			cells = rotate_cw(cells)
		end
		shapes[i] = shape
	end
	return shapes
end

--- Наборы деталей: тетромино (4 кубика) и пентамино (5 кубиков).
M.SHAPES_TETROMINO = build_shapes(TETROMINOES)
M.SHAPES_PENTOMINO = build_shapes(PENTOMINOES)

--- Все детали, которые могут появиться в стартовом квадрате 5x5:
--- тетромино и пентамино сведены в один список.
M.SHAPES_MIXED = {}
for i = 1, #M.SHAPES_TETROMINO do
	M.SHAPES_MIXED[#M.SHAPES_MIXED + 1] = M.SHAPES_TETROMINO[i]
end
for i = 1, #M.SHAPES_PENTOMINO do
	M.SHAPES_MIXED[#M.SHAPES_MIXED + 1] = M.SHAPES_PENTOMINO[i]
end

--- Текущий набор деталей (по умолчанию — тетромино, как на первом уровне).
M.SHAPES = M.SHAPES_TETROMINO

--- Подбирает набор деталей под размер стартового квадрата: в квадрате 4x4 —
--- только детали из 4 кубиков, в квадрате 5x5 — и из 4, и из 5 кубиков.
function M.apply_zone_shapes()
	if M.ZONE >= 5 then
		M.SHAPES = M.SHAPES_MIXED
	else
		M.SHAPES = M.SHAPES_TETROMINO
	end
	return M.SHAPES
end

--- Случайный набор деталей для текущего размера стартового квадрата.
--- В квадрате 5x5 размер детали (4 или 5 кубиков) выбирается равновероятно,
--- после чего берётся случайная форма уже из выбранного набора.
function M.random_shape_set()
	if M.ZONE >= 5 and math.random(2) == 2 then
		return M.SHAPES_PENTOMINO
	end
	return M.SHAPES_TETROMINO
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

--- Случайная фигура (случайный набор, форма и поворот).
function M.random_piece()
	local set = M.random_shape_set()
	local shape = set[math.random(#set)]
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

--- Ставит клетки фигуры на поле и возвращает список занятых клеток.
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

--- Доля заполнения игрового поля: 0 — поле пустое, 1 — заполнено целиком.
--- Именно по этому значению окрашивается контур стартового квадрата:
--- до 30% — зелёный -> жёлтый, 30–70% — жёлтый -> красный, выше — красный.
function M.fill_ratio(board)
	local total = M.W * M.H
	if total <= 0 then
		return 0
	end
	local ratio = M.occupied(board) / total
	if ratio < 0 then
		return 0
	elseif ratio > 1 then
		return 1
	end
	return ratio
end

return M
