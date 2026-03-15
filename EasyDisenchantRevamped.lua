--[[
	EasyDisenchantRevamped (C) FHeerdink <frankeheerdink@gmail.com>
	Forked from EasyDisenchant with Approval from Kruithne <kruithne@gmail.com>
	Licensed under GNU General Public Licence version 3.BlacklistItem

	https://github.com/FHeerdink/EasyDisenchantRevamped

	EasyDisenchantRevamped.lua - Contains the core functionality of the addon.
]]--

do
	-- [[ Globals ]] --
	local PlaySound = PlaySound;
	local HideUIPanel = HideUIPanel;
	local math_floor = math.floor;
	local string_match = string.match;
	local tonumber = tonumber;
	local strlower = strlower;
	local pairs = pairs;

	local _K = Krutilities;
	local _M = {
		ADDON_NAME = "EasyDisenchantRevamped",
		chatFormat = "Easy Disenchant Revamped: %s",
		eventFrame = CreateFrame("FRAME"),
		itemButtons = {},
		eventMap = {}, -- Used for internal mapping of events.
		-- Tab System
		currentTab = "DISENCHANT",
		blacklistRows = {},
		-- Disenchant Tab Scroll FRAME
		maxButtons = 89,
		minVisibleRows = 5,
		maxVisibleRows = 10,
		minFrameHeight = 350,
		maxFrameHeight = 650,
		itemRowHeight = 38,
		itemsPerRow = 9,

		buttonRenderingCache = {}
	};

	BINDING_HEADER_EASY_DISENCHANT = _M.ADDON_NAME;
	BINDING_NAME_EASY_DISENCHANT_OPEN = SHOW;

	-- Set table __index call to pass-through strings.
	setmetatable(_M, { __index = function(t, k) return t.Strings[k]; end });

	_M.ApplyLocalization = function(self, locale)
		local strings = self.Strings;
		for key, str in pairs(locale) do
			strings[key] = str;
		end
	end

	_M.GetItemIDFromLink = function(itemLink)
		return tonumber(string_match(itemLink, "Hitem:(%d+)"));
	end

	_M.IsBlacklisted = function(self, itemID)
		-- REPLACE your entire IsBlacklisted() function with this version.
		-- Changes:
		-- 1. Supports the new rich blacklist entry format.
		-- 2. Still works during migration from old boolean entries.

		return self.blacklist[itemID] ~= nil;
	end

	_M.BlacklistItem = function(self, itemID, itemLink)
		-- REPLACE your entire BlacklistItem() function with this version.
		-- Changes:
		-- 1. Stores a rich blacklist entry instead of just true.
		-- 2. Adds timeAdded for sorting newest first later.
		-- 3. Keeps the existing last-blacklisted tracking and chat messages.

		local itemName, _, itemQuality, _, _, _, _, _, _, itemIcon = GetItemInfo(itemLink);

		self.blacklist[itemID] = {
			itemID = itemID,
			itemLink = itemLink,
			itemName = itemName or ("Item ID: " .. itemID),
			iconFileID = itemIcon,
			quality = itemQuality,
			timeAdded = time(),
		};

		self.lastBlacklistedItem = itemID;
		self.lastBlacklistedItemLink = itemLink;

		self:Print(self.BLACKLIST_ADD_ITEM:format(itemLink));
		self:Print(self.BLACKLIST_INFO);
	end

	_M.OnLoad = function(self)
		-- REPLACE your entire OnLoad() function with this version.
		-- Changes:
		-- 1. Keeps slash command setup.
		-- 2. Initializes blacklist/settings saved variables.
		-- 3. Migrates old blacklist entries from itemID = true to rich entry tables.
		-- 4. Initializes settings saved variables for window position.

		-- Register command.
		SLASH_DISENCHANT1, SLASH_DISENCHANT2 = "/disenchant", "/de";
		SlashCmdList["DISENCHANT"] = _M.OnCommand;

		-- Create stored blacklist table if it doesn't exist.
		if not EasyDisenchantBlacklist then
			EasyDisenchantBlacklist = {};
		end

		-- Create stored settings table if it doesn't exist.
		if not EasyDisenchantRevampedSettings then
			EasyDisenchantRevampedSettings = {};
		end

		-- Store local references to our saved tables.
		self.blacklist = EasyDisenchantBlacklist;
		self.settings = EasyDisenchantRevampedSettings;

		-- Migrate old blacklist format:
		-- old:  self.blacklist[itemID] = true
		-- new:  self.blacklist[itemID] = { itemID=..., itemLink=..., itemName=..., iconFileID=..., quality=..., timeAdded=... }
		for itemID, entry in pairs(self.blacklist) do
			if entry == true then
				local itemLink = select(2, GetItemInfo(itemID));
				local itemName, _, itemQuality, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID);

				self.blacklist[itemID] = {
					itemID = itemID,
					itemLink = itemLink,
					itemName = itemName or ("Item ID: " .. itemID),
					iconFileID = itemIcon,
					quality = itemQuality,
					timeAdded = 0, -- migrated entries sort below real dated entries
				};
			end
		end
	end

	_M.GetBlacklistEntry = function(self, itemID)
		-- NEW:
		-- 1. Returns the rich blacklist entry for an itemID.
		-- 2. Safely handles missing entries.

		return self.blacklist[itemID];
	end

	_M.RefreshBlacklistEntry = function(self, itemID)
		-- NEW:
		-- 1. Optionally refreshes display snapshot fields if better item data is available.
		-- 2. Preserves timeAdded.
		-- 3. Keeps existing saved values when fresh item data is unavailable.

		local entry = self.blacklist[itemID];
		if not entry then
			return nil;
		end

		local itemName, itemLink, itemQuality, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID);

		if itemName then
			entry.itemName = itemName;
		end

		if itemLink then
			entry.itemLink = itemLink;
		end

		if itemQuality ~= nil then
			entry.quality = itemQuality;
		end

		if itemIcon then
			entry.iconFileID = itemIcon;
		end

		if entry.timeAdded == nil then
			entry.timeAdded = 0;
		end

		return entry;
	end

	_M.GetBlacklistCount = function(self)
		-- NEW:
		-- 1. Returns the total number of blacklisted item entries.

		local count = 0;

		for itemID, entry in pairs(self.blacklist) do
			if entry ~= nil then
				count = count + 1;
			end
		end

		return count;
	end

	_M.GetSortedBlacklistEntries = function(self)
		-- NEW:
		-- 1. Builds an array of blacklist entries from the saved dictionary.
		-- 2. Refreshes display snapshot data when possible.
		-- 3. Sorts by timeAdded (newest first), then itemName, then itemID.

		local entries = {};

		for itemID, entry in pairs(self.blacklist) do
			if entry ~= nil then
				entry = self:RefreshBlacklistEntry(itemID) or entry;
				entries[#entries + 1] = entry;
			end
		end

		table.sort(entries, function(a, b)
			local aTimeAdded = a.timeAdded or 0;
			local bTimeAdded = b.timeAdded or 0;

			if aTimeAdded ~= bTimeAdded then
				return aTimeAdded > bTimeAdded;
			end

			local aName = a.itemName or "";
			local bName = b.itemName or "";

			if aName ~= bName then
				return aName < bName;
			end

			local aItemID = a.itemID or 0;
			local bItemID = b.itemID or 0;

			return aItemID < bItemID;
		end);

		return entries;
	end

	_M.ResetBlacklist = function(self)
		self.blacklist = {};
		EasyDisenchantBlacklist = self.blacklist;

		self:Print(self.BLACKLIST_RESET);
		self.InvokeWindowOpen(); -- Refresh display.
	end

	_M.UndoBlacklist = function(self)
		if self.lastBlacklistedItem and self:IsBlacklisted(self.lastBlacklistedItem) then
			self.blacklist[self.lastBlacklistedItem] = nil;
			self:Print(self.BLACKLIST_REMOVE_ITEM:format(self.lastBlacklistedItemLink));

			self.lastBlacklistedItem = nil;
			self.lastBlacklistedItemLink = nil;

			self.InvokeWindowOpen(); -- Refresh display.
		end
	end

	_M.Print = function(self, message)
		DEFAULT_CHAT_FRAME:AddMessage(self.chatFormat:format(message));
	end

	_M.SetEventHandler = function(self, event, func)
		self.eventMap[event] = func;
		self.eventFrame:RegisterEvent(event);
	end

	_M.RemoveEventHandler = function(self, event)
		self.eventMap[event] = nil;
		self.eventFrame:UnregisterEvent(event);
	end

	_M.GetItemButtonRenderingCache = function(self)
		-- Changes:
		-- 1. Parents item buttons to the scroll child instead of the main frame.
		-- 2. Keeps the current glow/tooltip behavior.
		-- 3. Uses layout values from _M for row/column placement.

		local cache = self.buttonRenderingCache;
		if not cache.hasCreated then
			local frame = self.disenchantFrame;

			-- Called when an item button is clicked, as a post-event.
			cache.func_clickHook = function(self, key)
				if InCombatLockdown() then
					frame.header:SetText(ERR_NOT_IN_COMBAT);
					frame.header:SetTextColor(1, 0, 0);
				else
					if key == "RightButton" then
						_M:BlacklistItem(self.itemID, self.link);
					end
					self:Hide();
				end
			end

			-- Called when the player's cursor leaves an item button.
			cache.func_mouseLeave = function(self)
				frame.glow:Hide();
				GameTooltip:Hide();
			end

			-- Called when the player's cursor enters an item button.
			cache.func_mouseEnter = function(self)
				frame.glow:ClearAllPoints();
				frame.glow:SetPoint("CENTER", self);
				frame.glow:Show();
				frame.glow:SetFrameStrata(self:GetFrameStrata());
				frame.glow:SetFrameLevel(self:GetFrameLevel() + 10);

				GameTooltip:SetOwner(self, "ANCHOR_LEFT");
				GameTooltip:SetHyperlink(self.link);
				GameTooltip:Show();
			end

			cache.factory = function(index)
				local column = index % self.itemsPerRow;
				local row = math.floor(index / self.itemsPerRow);

				return {
					type = "ItemButton",
					parent = self.disenchantFrame.scrollChild,
					parentName = "ItemButton" .. index,
					inherit = "SecureActionButtonTemplate",
					textures = {
						injectSelf = "backdrop",
						layer = "BACKGROUND",
						texture = [[Interface\Buttons\UI-EmptySlot-Disabled]],
						size = 54,
					},
					points = {
						point = "TOPLEFT",
						x = 0 + (38 * column),   -- REPLACED: start at the top-left of the scroll child
						y = 0 + (row * -38)      -- REPLACED: first row starts at the top instead of lower down
					},
					scripts = {
						OnEnter = cache.func_mouseEnter,
						OnLeave = cache.func_mouseLeave
					},
				};
			end

			cache.hasCreated = true;
		end

		return cache;
	end

	_M.GetItemButton = function(self, index)
		local buttons = self.itemButtons;
		if buttons[index + 1] then
			return buttons[index + 1];
		end

		local cache = self:GetItemButtonRenderingCache();
		local button = _K:Frame(cache.factory(index));

		button:HookScript("OnClick", cache.func_clickHook);
		button:RegisterForClicks("LeftButtonDown", "RightButtonDown");
		button:SetAttribute("useOnKeyDown", true);

		buttons[#buttons + 1] = button;
		return button;
	end

	_M.ScanEquipmentManager = function(self)
        local ITEM_INVENTORY_BAG_OFFSET = 4096;
		local numOutfits = C_EquipmentSet.GetNumEquipmentSets();
		local equipmentCache = {};

		-- Equipment sets appear to be zero-index since 8.0?
		for index = 0, numOutfits - 1 do
			local setName, _, setID = C_EquipmentSet.GetEquipmentSetInfo(index);
			if setID ~= nil then
                local locations = C_EquipmentSet.GetItemLocations(setID);
                for slotIndex, location in pairs(locations) do
                    local isInBags = (bit.band(location, ITEM_INVENTORY_LOCATION_BAGS) ~= 0);
                    if isInBags and location > 0 then
                        print('loc:' .. location);
                        local slotLocation = location;
                        slotLocation = slotLocation - ITEM_INVENTORY_LOCATION_BAGS;
                        local bag = bit.rshift(slotLocation, ITEM_INVENTORY_BAG_BIT_OFFSET);
                        local slot = slotLocation - bit.lshift(bag, ITEM_INVENTORY_BAG_BIT_OFFSET);
                        bag = bag - ITEM_INVENTORY_BAG_OFFSET;

                        if bag ~= nil and slot ~= nil then
                            local itemID = C_Container.GetContainerItemID(bag, slot);
                            equipmentCache[table.concat({bag, slot, itemID}, "-")] = true;
                        end
                    end
                end
			else
				self:Print(self.BROKEN_ITEM_SET);
			end
		end

		self.equipmentCache = equipmentCache;
	end

	_M.ResetEquipmentManagerCache = function(self)
		self.equipmentCache = nil;
	end

	_M.IsItemInOutfit = function(self, bagID, slotID, itemID)
		-- Check Outfitter if installed.
		if Outfitter then
			local inventoryCache = Outfitter:GetInventoryCache();

			-- Call this method to mark items with UsedInOutfit
			inventoryCache:CompiledUnusedItemsList();

			local vItems = inventoryCache.ItemsByCode[itemID];
			if vItems ~= nil then
				for _, vItemInfo in ipairs(vItems) do
					-- We found our item now check if its used in an outfit.
					if vItemInfo.UsedInOutfit == true then
						return true
					end
				end
			end
		else
			if self.equipmentCache == nil then
				-- Only process outfit data once per window open.
				self:ScanEquipmentManager();
			end

			return self.equipmentCache[table.concat({bagID, slotID, itemID}, "-")] or false;
		end

		return false;
	end

	_M.UpdateWindowHeight = function(self, itemCount)
		-- NEW:
		-- 1. Grows the window based on how many item rows are needed.
		-- 2. Stops growing at maxVisibleRows.
		-- 3. Sizes the scroll child so extra rows can scroll.
		-- 4. Resets scroll position when the list is rebuilt.

		if not self.disenchantFrame or not self.disenchantFrame.scrollFrame or not self.disenchantFrame.scrollChild then
			return;
		end

		local rowCount = math.max(1, math.ceil(itemCount / self.itemsPerRow));
		local visibleRows = math.max(self.minVisibleRows, math.min(rowCount, self.maxVisibleRows));
		local frameHeight = self.minFrameHeight + ((visibleRows - self.minVisibleRows) * self.itemRowHeight);

		if frameHeight > self.maxFrameHeight then
			frameHeight = self.maxFrameHeight;
		end

		self.disenchantFrame:SetHeight(frameHeight);

		-- REPLACED: content now starts at the top of the scroll child.
		local contentHeight = 54 + ((rowCount - 1) * self.itemRowHeight);
		local minimumContentHeight = 54 + ((self.minVisibleRows - 1) * self.itemRowHeight);

		if contentHeight < minimumContentHeight then
			contentHeight = minimumContentHeight;
		end

		self.disenchantFrame.scrollChild:SetHeight(contentHeight);
		self.disenchantFrame.scrollFrame:SetVerticalScroll(0);
	end

	_M.UpdateItems = function(self)
		-- REPLACE your entire UpdateItems() function with this version.
		-- Changes:
		-- 1. Cleans up the nested logic.
		-- 2. Separates validation steps so eligibility is easier to follow.
		-- 3. Keeps the current weapon/armor + equippable filtering behavior.
		-- 4. Preserves button creation and secure macro behavior.
		-- 5. Keeps the current item filtering behavior.
		-- 6. Counts visible buttons.
		-- 7. Resizes the window after rebuilding the list.
		-- 8. Lets the scroll frame handle overflow.

		local buttons = self.itemButtons;
		local nButtons = #buttons;

		for i = 1, nButtons do
			buttons[i]:Hide();
		end

		local disenchantName = C_Spell.GetSpellName(13262);
		local macroFormat = "/stopmacro [combat][btn:2]\n/stopcasting\n/cast %s\n/cast %s %s";

		self:ResetEquipmentManagerCache();

		local useButton = 0;

		for bagID = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID);

			for slotID = 1, numSlots do
				local item = C_Container.GetContainerItemInfo(bagID, slotID);

				if item ~= nil and item.hyperlink ~= nil and item.quality ~= nil then
					local isCorrectQuality = item.quality > 1 and item.quality < 5;

					if isCorrectQuality then
						local itemName, _, _, _, _, _, _, _, itemEquipLoc, _, _, classID = GetItemInfo(item.hyperlink);

						if itemName ~= nil then
							local itemID = item.itemID;
							local isBlacklisted = self:IsBlacklisted(itemID);
							local isInOutfit = self:IsItemInOutfit(bagID, slotID, itemID);

							if not isBlacklisted and not isInOutfit then
								local isWeapon = (classID == Enum.ItemClass.Weapon);
								local isArmor = (classID == Enum.ItemClass.Armor);
								local isProfessionItem = (classID == Enum.ItemClass.Profession);
								local isEquippable = (itemEquipLoc ~= nil and itemEquipLoc ~= "");

								if isEquippable and (isWeapon or isArmor or isProfessionItem) then
									local button = self:GetItemButton(useButton);

									SetItemButtonTexture(button, item.iconFileID);
									SetItemButtonQuality(button, item.quality, item.hyperlink);

									button:SetAttribute("type", "macro");
									button:SetAttribute("macrotext", format(macroFormat, disenchantName, bagID, slotID));

									button.link = item.hyperlink;
									button.itemID = itemID;

									button:Show();

									useButton = useButton + 1;

									if useButton >= self.maxButtons then
										self:UpdateWindowHeight(useButton);
										return;
									end
								end
							end
						end
					end
				end
			end
		end

		self:UpdateWindowHeight(useButton);
	end

	_M.SaveWindowPosition = function(self)
		-- Saves the current frame anchor into saved variables.

		if not self.disenchantFrame then
			return;
		end

		local point, _, relativePoint, x, y = self.disenchantFrame:GetPoint(1);

		self.settings.windowPosition = {
			point = point,
			relativePoint = relativePoint,
			x = x,
			y = y,
		};
	end

	_M.RestoreWindowPosition = function(self)
		-- Restores the frame anchor from saved variables if one exists.

		if not self.disenchantFrame then
			return;
		end

		local windowPosition = self.settings.windowPosition;
		if windowPosition then
			self.disenchantFrame:ClearAllPoints();
			self.disenchantFrame:SetPoint(
				windowPosition.point,
				UIParent,
				windowPosition.relativePoint,
				windowPosition.x,
				windowPosition.y
			);
		end
	end

	_M.RegisterEscapeFrame = function(self)
		-- Makes the main frame closable with Escape.

		if not self.disenchantFrame or not self.disenchantFrame:GetName() then
			return;
		end

		for i = 1, #UISpecialFrames do
			if UISpecialFrames[i] == self.disenchantFrame:GetName() then
				return;
			end
		end

		tinsert(UISpecialFrames, self.disenchantFrame:GetName());
	end

	_M.UpdateBlacklistHeader = function(self)
		-- NEW:
		-- 1. Updates the blacklist content header text with the current count.
		-- 2. Keeps the short tab text separate from the content header.

		if not self.disenchantFrame or not self.disenchantFrame.blacklistHeader then
			return;
		end

		self.disenchantFrame.blacklistHeader:SetText("Blacklisted Items (" .. self:GetBlacklistCount() .. ")");
	end

	_M.UpdateBlacklistEmptyState = function(self)
		-- NEW:
		-- 1. Shows the empty-state message when there are no blacklisted items.
		-- 2. Hides it when blacklist entries exist.

		if not self.disenchantFrame or not self.disenchantFrame.blacklistEmptyText then
			return;
		end

		if self:GetBlacklistCount() == 0 then
			self.disenchantFrame.blacklistEmptyText:Show();
		else
			self.disenchantFrame.blacklistEmptyText:Hide();
		end
	end

	_M.SetActiveTab = function(self, tabName)
		-- NEW:
		-- 1. Switches between the Disenchant and Blacklist content regions.
		-- 2. Updates the selected state of the tab buttons.
		-- 3. Fully refreshes the blacklist view when switching to Blacklist.

		if not self.disenchantFrame then
			return;
		end

		self.currentTab = tabName;

		local frame = self.disenchantFrame;

		if tabName == "BLACKLIST" then
			frame.disenchantContent:Hide();
			frame.blacklistContent:Show();

			PanelTemplates_DeselectTab(frame.disenchantTabButton);
			PanelTemplates_SelectTab(frame.blacklistTabButton);

			self:RefreshBlacklistView();
		else
			frame.blacklistContent:Hide();
			frame.disenchantContent:Show();

			PanelTemplates_SelectTab(frame.disenchantTabButton);
			PanelTemplates_DeselectTab(frame.blacklistTabButton);
		end
	end

	_M.RefreshBlacklistView = function(self)
		-- NEW:
		-- 1. Refreshes the blacklist header count.
		-- 2. Refreshes the empty-state message.
		-- 3. Refreshes the visible blacklist rows.

		self:UpdateBlacklistHeader();
		self:UpdateBlacklistEmptyState();
		self:UpdateBlacklistRows();
	end

	_M.RemoveBlacklistItem = function(self, itemID)
		-- NEW:
		-- 1. Removes a single item from the blacklist by itemID.
		-- 2. Refreshes the blacklist tab immediately.

		local entry = self.blacklist[itemID];
		if not entry then
			return;
		end

		self.blacklist[itemID] = nil;

		if self.disenchantFrame then
			self:UpdateItems();
		end

		self:RefreshBlacklistView();
	end

	_M.GetBlacklistRow = function(self, index)
		-- NEW:
		-- 1. Creates/reuses a blacklist row frame.
		-- 2. Each row has an icon, item text, and Remove button.
		-- 3. Icon and text show the item tooltip on hover.

		local rows = self.blacklistRows;
		if rows[index] then
			return rows[index];
		end

		local frame = self.disenchantFrame;
		local rowHeight = 28;

		local row = CreateFrame("BUTTON", "$parentBlacklistRow" .. index, frame.blacklistScrollChild);
		row:SetHeight(rowHeight);
		row:SetPoint("TOPLEFT", frame.blacklistScrollChild, "TOPLEFT", 0, -((index - 1) * rowHeight));
		row:SetPoint("TOPRIGHT", frame.blacklistScrollChild, "TOPRIGHT", 0, -((index - 1) * rowHeight));
		row:Hide();

		row.bg = row:CreateTexture(nil, "BACKGROUND");
		row.bg:SetAllPoints(true);
		row.bg:SetColorTexture(1, 1, 1, 0.03);

		row.icon = row:CreateTexture(nil, "ARTWORK");
		row.icon:SetSize(20, 20);
		row.icon:SetPoint("LEFT", row, "LEFT", 4, 0);

		row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0);
		row.text:SetPoint("RIGHT", row, "RIGHT", -70, 0);
		row.text:SetJustifyH("LEFT");

		row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate");
		row.removeButton:SetSize(60, 20);
		row.removeButton:SetPoint("RIGHT", row, "RIGHT", -4, 0);
		row.removeButton:SetText("Remove");
		row.removeButton:SetScript("OnClick", function(buttonSelf)
			_M:RemoveBlacklistItem(buttonSelf:GetParent().itemID);
		end);

		row:SetScript("OnEnter", function(self)
			if self.itemLink then
				GameTooltip:SetOwner(self, "ANCHOR_LEFT");
				GameTooltip:SetHyperlink(self.itemLink);
				GameTooltip:Show();
			end
		end);

		row:SetScript("OnLeave", function()
			GameTooltip:Hide();
		end);

		rows[index] = row;
		return row;
	end

	_M.UpdateBlacklistRows = function(self)
		-- NEW:
		-- 1. Builds the blacklist row list from sorted entries.
		-- 2. Shows icon + item text + Remove button.
		-- 3. Sizes the scroll child based on row count.
		-- 4. Resets scroll position when the list is rebuilt.

		if not self.disenchantFrame or not self.disenchantFrame.blacklistScrollFrame or not self.disenchantFrame.blacklistScrollChild then
			return;
		end

		local entries = self:GetSortedBlacklistEntries();
		local rows = self.blacklistRows;
		local rowHeight = 28;
		local contentHeight = #entries * rowHeight;

		if contentHeight < 1 then
			contentHeight = 1;
		end

		self.disenchantFrame.blacklistScrollChild:SetHeight(contentHeight);

		for i = 1, #entries do
			local entry = entries[i];
			local row = self:GetBlacklistRow(i);

			row.itemID = entry.itemID;
			row.itemLink = entry.itemLink;

			if entry.iconFileID then
				row.icon:SetTexture(entry.iconFileID);
			else
				row.icon:SetTexture([[Interface\Icons\INV_Misc_QuestionMark]]);
			end

			if entry.itemLink then
				row.text:SetText(entry.itemLink);
			elseif entry.itemName then
				row.text:SetText(entry.itemName);
			else
				row.text:SetText("Item ID: " .. tostring(entry.itemID));
			end

			row:Show();
		end

		for i = #entries + 1, #rows do
			rows[i]:Hide();
		end

		self.disenchantFrame.blacklistScrollFrame:SetVerticalScroll(0);
	end

	_M.CreateDisenchantFrame = function(self)
		-- Changes:
		-- 1. 	Makes the window movable.
		-- 2. 	Saves position when dragging stops.
		-- 3. 	Restores saved position after creation.
		-- 4. 	Registers the frame for closing with Escape.
		-- 5. 	Clamps the frame to the screen.
		-- 6. 	Adds a scroll frame + scroll child for item buttons.
		-- 7. 	Keeps the window movable / remembered / Escape-close behavior.
		-- 8. 	Uses a minimum starting height and allows growth later.
		-- 9. 	Enables mouse wheel scrolling.
		-- 10. 	Adds two tab buttons: Disenchant and Blacklist.
		-- 11. 	Creates both content regions up front and toggles them with hide/show.
		-- 12. 	Moves the existing disenchant scroll area into disenchantContent.
		-- 13. 	Adds blacklist header text with count support.
		-- 14. 	Adds the empty-state message: "No blacklisted items."

		local bgAnchor = {
			{ point = "TOPLEFT", x = 8, y = -8 },
			{ point = "BOTTOMRIGHT", x = -8, y = 8 }
		};

		local cornerMixin = {
			layer = "BACKGROUND",
			size = 64,
			subLevel = -2,
			texture = [[Interface\Transmogrify\Textures]]
		};

		local edgeXMixin = {
			tileX = true,
			subLevel = -3,
			size = {64, 23},
			layer = "BACKGROUND",
			texture = [[Interface\Transmogrify\HorizontalTiles]]
		};

		local edgeYMixin = {
			tileY = true,
			subLevel = -3,
			size = {23, 64},
			layer = "BACKGROUND",
			texture = [[Interface\Transmogrify\VerticalTiles]]
		};

		self.disenchantFrame = _K:Frame({
			name = "EasyDisenchantRevampedFrame",
			size = {418, self.minFrameHeight},
			enableMouse = true,
			points = {
				point = "CENTER",
				relativePoint = "CENTER",
				x = 0,
				y = 0
			},
			frames = {
				{ -- Close Button
					type = "BUTTON",
					parentName = "CloseButton",
					inherit = "UIPanelCloseButton",
					points = { point = "TOPRIGHT", x = -20, y = -25 }
				},
				{ -- Glow used by the item buttons.
					size = 37,
					hidden = true,
					injectSelf = "glow",
					strata = "DIALOG",
					textures = {
						{
							parentName = "InnerGlow", injectSelf = "innerGlow",
							texture = [[Interface\SpellActivationOverlay\IconAlert]],
							size = 53, points = { point = "CENTER" },
							texCoord = { 0.00781250, 0.50781250, 0.27734375, 0.52734375 }
						},
						{
							layer = "OVERLAY", parentName = "Ants", injectSelf = "ants",
							texture = [[Interface\SpellActivationOverlay\IconAlertAnts]],
							size = 44, points = { point = "CENTER" }
						}
					},
					scripts = {
						OnUpdate = function(self, elapsed) AnimateTexCoords(self.ants, 256, 256, 48, 48, 22, elapsed, 0.01); end
					}
				}
			},
			texts = {
				{
					inherit = "GameFontHighlightMedium",
					text = "Easy Disenchant Revamped",
					injectSelf = "header",
					points = { point = "TOPLEFT", x = 35, y = -40 }
				},
				{
					inherit = "GameFontHighlightMedium",
					text = self.INFO,
					justifyH = "CENTER",
					points = { point = "BOTTOM", y = 30 }
				}
			},
			textures = {
				{ -- Background.
					layer = "BACKGROUND",
					subLevel = -6,
					texture = [[Interface\FrameGeneral\UI-Background-Marble]],
					tile = true,
					points = bgAnchor,
					color = {0.302, 0.102, 0.204, 0.8}
				},
				{ -- Corner: Top Left
					parentName = "CornerTL",
					mixin = cornerMixin,
					points = "TOPLEFT",
					texCoord = {0.00781250, 0.50781250, 0.00195313, 0.12695313}
				},
				{ -- Corner: Top Right
					parentName = "CornerTR",
					mixin = cornerMixin,
					points = "TOPRIGHT",
					texCoord = {0.00781250, 0.50781250, 0.38476563, 0.50781250}
				},
				{ -- Corner: Bottom Left
					parentName = "CornerBL",
					mixin = cornerMixin,
					points = "BOTTOMLEFT",
					texCoord = {0.0078125, 0.5078125, 0.2578125, 0.38085938}
				},
				{ -- Corner: Bottom Right
					parentName = "CornerBR",
					mixin = cornerMixin,
					points = "BOTTOMRIGHT",
					texCoord = {0.0078125, 0.5078125, 0.13085938, 0.25390625}
				},
				{ -- Edge: Top
					parentName = "TopEdge",
					mixin = edgeXMixin,
					points = {
						{ point = "TOPLEFT", relativeTo = "$parentCornerTL", relativePoint = "TOPRIGHT", x = -30, y = -5 },
						{ point = "TOPRIGHT", relativeTo = "$parentCornerTR", relativePoint = "TOPLEFT", x = 30, y = -5 }
					},
					texCoord = {0, 1, 0.40625, 0.765625}
				},
				{ -- Edge: Bottom
					parentName = "BottomEdge",
					mixin = edgeXMixin,
					points = {
						{ point = "BOTTOMLEFT", relativeTo = "$parentCornerBL", relativePoint = "BOTTOMRIGHT", x = -30, y = 4 },
						{ point = "BOTTOMRIGHT", relativeTo = "$parentCornerBR", relativePoint = "BOTTOMLEFT", x = 30, y = 4 }
					},
					texCoord = {0, 1, 0.015625, 0.375}
				},
				{ -- Edge: Left
					parentName = "LeftEdge",
					mixin = edgeYMixin,
					points = {
						{ point = "TOPLEFT", relativeTo = "$parentCornerTL", relativePoint = "BOTTOMLEFT", x = 4, y = 16 },
						{ point = "BOTTOMLEFT", relativeTo = "$parentCornerBL", relativePoint = "TOPLEFT", x = 4, y = -16 }
					},
					texCoord = {0.40625, 0.765625, 0, 1}
				},
				{ -- Edge: Right
					parentName = "RightEdge",
					mixin = edgeYMixin,
					points = {
						{ point = "TOPRIGHT", relativeTo = "$parentCornerTR", relativePoint = "BOTTOMRIGHT", x = -4, y = 16 },
						{ point = "BOTTOMRIGHT", relativeTo = "$parentCornerBR", relativePoint = "TOPRIGHT", x = -4, y = -16 }
					},
					texCoord = {0.015625, 0.375, 0, 1}
				}
			},
			scripts = {
				OnHide = function() PlaySound(SOUNDKIT.UI_ETHEREAL_WINDOW_CLOSE); end,
				OnMouseDown = function(frame, button)
					if button == "LeftButton" then
						frame:StartMoving();
					end
				end,
				OnMouseUp = function(frame)
					frame:StopMovingOrSizing();
					_M:SaveWindowPosition();
				end
			}
		});

		self.disenchantFrame:SetMovable(true);
		self.disenchantFrame:SetClampedToScreen(true);

		-- Create tab buttons.
		self.disenchantFrame.disenchantTabButton = CreateFrame("Button", "$parentDisenchantTabButton", self.disenchantFrame, "PanelTopTabButtonTemplate");
		self.disenchantFrame.disenchantTabButton:SetID(1)
		self.disenchantFrame.disenchantTabButton:SetText("Disenchant");
		PanelTemplates_TabResize(self.disenchantFrame.disenchantTabButton, 20);
		self.disenchantFrame.disenchantTabButton:SetPoint("TOPLEFT", self.disenchantFrame, "TOPLEFT", 24, -56);
		self.disenchantFrame.disenchantTabButton:SetScript("OnClick", function()
			_M:SetActiveTab("DISENCHANT");
		end);

		self.disenchantFrame.blacklistTabButton = CreateFrame("Button", "$parentBlacklistTabButton", self.disenchantFrame, "PanelTopTabButtonTemplate");
		self.disenchantFrame.disenchantTabButton:SetID(2)
		self.disenchantFrame.blacklistTabButton:SetText("Blacklist");
		PanelTemplates_TabResize(self.disenchantFrame.blacklistTabButton, 20);
		self.disenchantFrame.blacklistTabButton:SetPoint("TOPLEFT", self.disenchantFrame.disenchantTabButton, "TOPRIGHT", 8, 0);
		self.disenchantFrame.blacklistTabButton:SetScript("OnClick", function()
			_M:SetActiveTab("BLACKLIST");
		end);

		-- Create both content regions up front.
		self.disenchantFrame.disenchantContent = CreateFrame("FRAME", "$parentDisenchantContent", self.disenchantFrame);
		self.disenchantFrame.disenchantContent:SetPoint("TOPLEFT", self.disenchantFrame, "TOPLEFT", 18, -100);
		self.disenchantFrame.disenchantContent:SetPoint("BOTTOMRIGHT", self.disenchantFrame, "BOTTOMRIGHT", -18, 52);

		self.disenchantFrame.blacklistContent = CreateFrame("FRAME", "$parentBlacklistContent", self.disenchantFrame);
		self.disenchantFrame.blacklistContent:SetPoint("TOPLEFT", self.disenchantFrame, "TOPLEFT", 18, -100);
		self.disenchantFrame.blacklistContent:SetPoint("BOTTOMRIGHT", self.disenchantFrame, "BOTTOMRIGHT", -18, 52);
		self.disenchantFrame.blacklistContent:Hide();

		-- Divider line under tabs
		self.disenchantFrame.tabDivider = self.disenchantFrame:CreateTexture(nil, "ARTWORK");
		self.disenchantFrame.tabDivider:SetColorTexture(1, 1, 1, 0.10);
		self.disenchantFrame.tabDivider:SetHeight(2);
		self.disenchantFrame.tabDivider:SetPoint("TOPLEFT", self.disenchantFrame.disenchantContent, "TOPLEFT", 4, 12);
		self.disenchantFrame.tabDivider:SetPoint("TOPRIGHT", self.disenchantFrame.disenchantContent, "TOPRIGHT", -10, 12);

		-- Divider line above help text
		self.disenchantFrame.bottomDivider = self.disenchantFrame:CreateTexture(nil, "ARTWORK");
		self.disenchantFrame.bottomDivider:SetColorTexture(1, 1, 1, 0.10);
		self.disenchantFrame.bottomDivider:SetHeight(2);
		self.disenchantFrame.bottomDivider:SetPoint("BOTTOMLEFT", self.disenchantFrame.disenchantContent, "BOTTOMLEFT", 10, -6);
		self.disenchantFrame.bottomDivider:SetPoint("BOTTOMRIGHT", self.disenchantFrame.disenchantContent, "BOTTOMRIGHT", -10, -6);

		-- Blacklist content header.
		self.disenchantFrame.blacklistHeader = self.disenchantFrame.blacklistContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium");
		self.disenchantFrame.blacklistHeader:SetPoint("TOPLEFT", self.disenchantFrame.blacklistContent, "TOPLEFT", 20, -10);
		self.disenchantFrame.blacklistHeader:SetText("Blacklisted Items (0)");

		-- Blacklist empty-state message.
		self.disenchantFrame.blacklistEmptyText = self.disenchantFrame.blacklistContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
		self.disenchantFrame.blacklistEmptyText:SetPoint("CENTER", self.disenchantFrame.blacklistContent, "CENTER", 0, 0);
		self.disenchantFrame.blacklistEmptyText:SetText("No blacklisted items.");

		-- Existing Disenchant tab scroll frame.
		self.disenchantFrame.scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", self.disenchantFrame.disenchantContent, "UIPanelScrollFrameTemplate");
		self.disenchantFrame.scrollFrame:SetPoint("TOPLEFT", self.disenchantFrame.disenchantContent, "TOPLEFT", 20, 0);
		self.disenchantFrame.scrollFrame:SetPoint("BOTTOMRIGHT", self.disenchantFrame.disenchantContent, "BOTTOMRIGHT", -10, 4);
		self.disenchantFrame.scrollFrame:EnableMouseWheel(true);

		self.disenchantFrame.scrollChild = CreateFrame("FRAME", "$parentScrollChild", self.disenchantFrame.scrollFrame);
		self.disenchantFrame.scrollChild:SetSize(320, 54 + ((self.minVisibleRows - 1) * self.itemRowHeight));
		self.disenchantFrame.scrollFrame:SetScrollChild(self.disenchantFrame.scrollChild);

		self.disenchantFrame.scrollFrame:SetScript("OnMouseWheel", function(scrollFrame, delta)
			local currentScroll = scrollFrame:GetVerticalScroll();
			local maxScroll = math.max(0, scrollFrame.scrollChild:GetHeight() - scrollFrame:GetHeight());
			local newScroll = currentScroll - (delta * self.itemRowHeight);

			if newScroll < 0 then
				newScroll = 0;
			elseif newScroll > maxScroll then
				newScroll = maxScroll;
			end

			scrollFrame:SetVerticalScroll(newScroll);
		end);

		self.disenchantFrame.scrollFrame.scrollChild = self.disenchantFrame.scrollChild;

		-- ADD THIS BLOCK: Blacklist tab scroll frame
		self.disenchantFrame.blacklistScrollFrame = CreateFrame("ScrollFrame", "$parentBlacklistScrollFrame", self.disenchantFrame.blacklistContent, "UIPanelScrollFrameTemplate");
		self.disenchantFrame.blacklistScrollFrame:SetPoint("TOPLEFT", self.disenchantFrame.blacklistContent, "TOPLEFT", 20, -30);
		self.disenchantFrame.blacklistScrollFrame:SetPoint("BOTTOMRIGHT", self.disenchantFrame.blacklistContent, "BOTTOMRIGHT", -10, 4);
		self.disenchantFrame.blacklistScrollFrame:EnableMouseWheel(true);

		-- ADD THIS BLOCK: Blacklist tab scroll child
		self.disenchantFrame.blacklistScrollChild = CreateFrame("FRAME", "$parentBlacklistScrollChild", self.disenchantFrame.blacklistScrollFrame);
		self.disenchantFrame.blacklistScrollChild:SetSize(320, 1);
		self.disenchantFrame.blacklistScrollFrame:SetScrollChild(self.disenchantFrame.blacklistScrollChild);

		-- ADD THIS BLOCK: Blacklist mouse wheel behavior
		self.disenchantFrame.blacklistScrollFrame:SetScript("OnMouseWheel", function(scrollFrame, delta)
			local currentScroll = scrollFrame:GetVerticalScroll();
			local maxScroll = math.max(0, scrollFrame.blacklistScrollChild:GetHeight() - scrollFrame:GetHeight());
			local newScroll = currentScroll - (delta * 28);

			if newScroll < 0 then
				newScroll = 0;
			elseif newScroll > maxScroll then
				newScroll = maxScroll;
			end

			scrollFrame:SetVerticalScroll(newScroll);
		end);

		-- ADD THIS LINE: make the child available to the mouse wheel function
		self.disenchantFrame.blacklistScrollFrame.blacklistScrollChild = self.disenchantFrame.blacklistScrollChild;

		self:RestoreWindowPosition();
		self:RegisterEscapeFrame();
		self:SetActiveTab("DISENCHANT");
	end

	_M.OpenWindow = function(self)
		-- Changes:
		-- 1. Keeps the current behavior.
		-- 2. Uses a more sensible open sound.
		-- 3. Brings the frame back on screen if needed.

		HideUIPanel(TradeSkillFrame);

		if not self.disenchantFrame then
			self:CreateDisenchantFrame();
		end

		self:UpdateItems();
		self.disenchantFrame:Show();
		self.disenchantFrame:SetClampedToScreen(true);

		PlaySound(SOUNDKIT.UI_ETHEREAL_WINDOW_OPEN);
	end

	_M.OnCommand = function(msg)
		msg = strlower(msg);

		if msg == "reset" then
			-- Reset the entire blacklist.
			_M:ResetBlacklist();
		elseif msg == "undo" then
			-- Revert last addition to the blacklist.
			_M:UndoBlacklist();
		else
			-- Everything else just opens the window.
			_M:InvokeWindowOpen();
		end
	end

	_M.OnEvent = function(self, event, ...)
		-- Note: self is not _M in this instance, it's eventFrame.
		local handler = _M.eventMap[event];
		if handler then
			handler(_M, ...);
		end
	end

	_M.OnAddonLoaded = function(self, addonName)
		-- Now only initializes the addon.

		if addonName == self.ADDON_NAME then
			self:OnLoad();
		end
	end

	_M.InvokeWindowOpen = function()
		_M:OpenWindow();
	end

	_M.eventFrame:SetScript("OnEvent", _M.OnEvent);
	_M:SetEventHandler("ADDON_LOADED", _M.OnAddonLoaded);

	EasyDisenchantShowWindow = _M.InvokeWindowOpen; -- Expose window open function.
	EasyDisenchant = _M; -- Expose addon container.
end
