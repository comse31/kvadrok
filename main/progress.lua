--- Сохранение прогресса игрока на устройстве.
---
--- Использует sys.save/sys.load из Defold: на десктопе и мобильных это файл
--- в пользовательской папке приложения, в HTML5 — localStorage. Поэтому
--- прогресс сохраняется между запусками игры на всех поддерживаемых платформах.
---
--- Хранится только достигнутый уровень — сторона поля в клетках
--- (20, 22, 24 … 30). Всё остальное (сколько кубиков разобрано за партию)
--- относится к текущей партии и не сохраняется.
---
--- Модуль безопасен и вне движка: если sys недоступен, все операции тихо
--- превращаются в no-op и возвращают значения по умолчанию (удобно для тестов).

local M = {}

--- Имя файла сохранения в папке приложения.
M.FILE = "kvadrok_progress"

--- Ключ, под которым лежит уровень внутри файла.
M.KEY = "field_size"

local function has_sys()
	return type(sys) == "table"
		and type(sys.save) == "function"
		and type(sys.load) == "function"
end

--- Загружает сохранённый прогресс. Возвращает таблицу вида
--- { field_size = <число или nil> }. При отсутствии файла или ошибке —
--- пустую таблицу.
function M.load()
	if not has_sys() then
		return {}
	end

	local ok, data = pcall(sys.load, M.FILE)
	if not ok or type(data) ~= "table" then
		return {}
	end
	return data
end

--- Сохраняет прогресс. progress — таблица (например, { field_size = 20 }).
--- Возвращает true при успешной записи.
function M.save(progress)
	if not has_sys() then
		return false
	end
	local ok = pcall(sys.save, M.FILE, progress or {})
	return ok and true or false
end

--- Читает сохранённый размер поля или nil, если прогресса ещё нет.
function M.load_field_size()
	local data = M.load()
	local value = data[M.KEY]
	if type(value) == "number" then
		return value
	end
	return nil
end

--- Записывает достигнутый размер поля на устройство.
function M.save_field_size(size)
	if type(size) ~= "number" then
		return false
	end
	return M.save({ [M.KEY] = size })
end

--- Полностью сбрасывает сохранённый прогресс.
function M.clear()
	if not has_sys() or type(sys.unload) ~= "function" then
		return false
	end
	local ok = pcall(sys.unload, M.FILE)
	return ok and true or false
end

return M
