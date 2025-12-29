--[[
	EasyDisenchant (C) Kruithne <kruithne@gmail.com>
	Licensed under GNU General Public Licence version 3.

	https://github.com/Kruithne/EasyDisenchant

	Strings_ruRU.lua - Russian localization ZamestoTV.
]]--

do
    if GetLocale() == "ruRU" then
		EasyDisenchant:ApplyLocalization({
    ["BLACKLIST_ADD_ITEM"] = "%s добавлен в чёрный список.",
    ["BLACKLIST_INFO"] = "Используйте команду '/de undo' для отмены или '/de reset' для удаления всех предметов из чёрного списка.",
    ["BLACKLIST_RESET"] = "Чёрный список предметов очищен!",
    ["BLACKLIST_REMOVE_ITEM"] = "%s удалён из чёрного списка.",
    ["INFO"] = "ЛКМ — распылить, ПКМ — добавить в чёрный список.",
    ["BROKEN_ITEM_SET"] = "Один из ваших комплектов предметов повреждён и не может быть отфильтрован. Удалите и создайте его заново.",
		});
    end
end
