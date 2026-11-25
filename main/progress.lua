--- Сохранение прогресса игрока на устройстве.
---
--- Использует sys.save/sys.load из Defold: на десктопе и мобильных это файл
--- в пользовательской папке приложения, в HTML5 — файл в IndexedDB.
---
--- ВАЖНО. Путь к файлу обязательно получать через sys.get_save_file():
--- в HTML5 постоянное хранилище (IDBFS/IndexedDB) смонтировано в /data,
--- а относительный путь попадает в MEMFS рядом с игровыми ресурсами и
--- бесследно исчезает при перезагрузке страницы. sys.get_save_file() создаёт
--- каталог приложения внутри постоянного хранилища и возвращает абсолютный
--- путь (в HTML5 — /data/.kvadrok/<файл>), поэтому запись переживает reload.
---
--- Хранится только достигнутый уровень — сторона поля в клетках
--- (20, 22, 24 … 30). Всё остальное (сколько кубиков разобрано за партию)
--- относится к текущей партии и не сохраняется.
---
--- Модуль безопасен и вне движка: если sys недоступен, все операции тихо
--- превращаются в no-op и возвращают значения по умолчанию (удобно для тестов).

local M = {}

--- Идентификатор приложения: задаёт каталог сохранений внутри постоянного
--- хранилища (в HTML5 это /data/.<APP_ID>/).
M.APP_ID = "kvadrok"

--- Имя файла сохранения.
M.FILE = "kvadrok_progress"

--- Ключ, под которым лежит уровень внутри файла.
M.KEY = "field_size"

--- Кэш абсолютного пути: sys.get_save_file() создаёт каталог, поэтому
--- вызываем его один раз за запуск.
local cached_path

local function has_sys()
	return type(sys) == "table"
		and type(sys.save) == "function"
		and type(sys.load) == "function"
end

--- Абсолютный путь к файлу сохранения внутри постоянного хранилища.
--- Если движка нет (тесты), возвращается просто имя файла.
function M.get_path()
	if cached_path then
		return cached_path
	end

	local path = M.FILE
	if has_sys() and type(sys.get_save_file) == "function" then
		local ok, value = pcall(sys.get_save_file, M.APP_ID, M.FILE)
		if ok and type(value) == "string" and value ~= "" then
			path = value
		end
	end

	cached_path = path
	return path
end

--- Загружает сохранённый прогресс. Возвращает таблицу вида
--- { field_size = <число или nil> }. При отсутствии файла или ошибке —
--- пустую таблицу.
function M.load()
	if not has_sys() then
		return {}
	end

	local ok, data = pcall(sys.load, M.get_path())
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
	local ok = pcall(sys.save, M.get_path(), progress or {})
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
--- В Defold нет sys.unload, поэтому файл удаляется средствами os.remove;
--- если доступен sys.unload (мок в тестах), используется он.
function M.clear()
	local path = M.get_path()

	if type(sys) == "table" and type(sys.unload) == "function" then
		local ok = pcall(sys.unload, path)
		return ok and true or false
	end

	if type(os) == "table" and type(os.remove) == "function" then
		local ok = pcall(os.remove, path)
		return ok and true or false
	end

	return false
end

return M
