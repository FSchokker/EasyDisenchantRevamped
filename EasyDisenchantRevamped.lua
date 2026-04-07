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
		disenchantViewMode = "BUTTONS",
		disenchantListRows = {},
		pendingDisenchantBagID = nil,
		pendingDisenchantSlotID = nil,
		pendingDisenchantItemID = nil,
		pendingDisenchantCastStartTimeMS = nil,
		pendingDisenchantCastEndTimeMS = nil,
		blacklistRows = {},
		-- Disenchant Tab Scroll FRAME
		maxButtons = 89,
		minVisibleRows = 5,
		maxVisibleRows = 10,
		minFrameHeight = 350,
		maxFrameHeight = 650,
		itemRowHeight = 38,
		itemsPerRow = 9,

		buttonRenderingCache = {},
		Strings = {}
	};

	BINDING_HEADER_EASY_DISENCHANT = _M.ADDON_NAME;
	BINDING_NAME_EASY_DISENCHANT_OPEN = SHOW;

	-- Set table __index call to pass-through strings.
	setmetatable(_M, {
		__index = function(t, k)
			local strings = rawget(t, "Strings");
			if strings then
				return strings[k];
			end

			return nil;
		end
	});

	_M.UpdateMinimapButtonPosition = function(self)
		-- Positions the minimap button based on the saved angle.

		if not self.minimapButton then
			return;
		end

		local angle = self.settings.minimapButtonAngle or 225;
		local radius = 80;

		local x = math.cos(math.rad(angle)) * radius;
		local y = math.sin(math.rad(angle)) * radius;

		self.minimapButton:ClearAllPoints();
		self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y);
	end

	--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	-- Minimap button helpers
	--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	
	_M.OpenSettingsPanel = function(self)
		-- NEW:
		-- 1. Opens the Blizzard Settings entry for this addon.
		-- 2. Uses the double-open behavior for reliability.

		if not self.settingsCategory then
			return;
		end

		if Settings and Settings.OpenToCategory then
			Settings.OpenToCategory(self.settingsCategory.ID);
			Settings.OpenToCategory(self.settingsCategory.ID);
		end
	end

	_M.SetMinimapButtonLocked = function(self, isLocked)
		-- NEW:
		-- 1. Saves the minimap lock setting.
		-- 2. Applies it immediately.

		self.settings.lockMinimapButton = isLocked and true or false;
	end

	_M.CreateMinimapButton = function(self)
		-- Changes:
		-- 1. Left-click opens the addon window.
		-- 2. Right-click now opens the Blizzard Settings entry.
		-- 3. CTRL + Right-click and drag moves the minimap button.
		-- 4. Dragging is blocked when the button is locked.
		-- 5. Tooltip text reflects the new behavior.

		if self.minimapButton then
			return;
		end

		local button = CreateFrame("Button", "EasyDisenchantRevampedMinimapButton", Minimap);
		button:SetSize(32, 32);
		button:SetFrameStrata("MEDIUM");
		button:EnableMouse(true);
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp");

		button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight");

		button.border = button:CreateTexture(nil, "OVERLAY");
		button.border:SetSize(53, 53);
		button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder");
		button.border:SetPoint("TOPLEFT");

		button.icon = button:CreateTexture(nil, "BACKGROUND");
		button.icon:SetSize(20, 20);
		button.icon:SetPoint("CENTER", 0, 0);
		button.icon:SetTexture("Interface\\AddOns\\EasyDisenchantRevamped\\Media\\icon_MiniMap_x32");

		button:SetScript("OnClick", function(_, mouseButton)
			if mouseButton == "LeftButton" then
				if _M.disenchantFrame and _M.disenchantFrame:IsShown() then
					_M.disenchantFrame:Hide();
				else
					_M:OpenWindow();
				end
			elseif mouseButton == "RightButton" then
				if not IsControlKeyDown() then
					_M:OpenSettingsPanel();
				end
			end
		end);

		button:SetScript("OnMouseDown", function(self, mouseButton)
			if mouseButton ~= "RightButton" then
				return;
			end

			if not IsControlKeyDown() then
				return;
			end

			if _M.settings.lockMinimapButton then
				return;
			end

			self.isDragging = true;

			self:SetScript("OnUpdate", function()
				local mx, my = Minimap:GetCenter();
				local px, py = GetCursorPosition();
				local scale = UIParent:GetEffectiveScale();

				px = px / scale;
				py = py / scale;

				local angle = math.deg(math.atan2(py - my, px - mx));
				if angle < 0 then
					angle = angle + 360;
				end

				_M.settings.minimapButtonAngle = angle;
				_M:UpdateMinimapButtonPosition();
			end);
		end);

		button:SetScript("OnMouseUp", function(self, mouseButton)
			if mouseButton == "RightButton" then
				self.isDragging = nil;
				self:SetScript("OnUpdate", nil);
			end
		end);

		button:SetScript("OnHide", function(self)
			self.isDragging = nil;
			self:SetScript("OnUpdate", nil);
		end);

		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT");
			GameTooltip:SetText("Easy Disenchant Revamped");
			GameTooltip:AddLine("Left-click: Toggle window", 1, 1, 1);
			GameTooltip:AddLine("Right-click: Open settings", 1, 1, 1);

			if _M.settings.lockMinimapButton then
				GameTooltip:AddLine("CTRL + Right-drag: Locked", 1, 0.25, 0.25);
			else
				GameTooltip:AddLine("CTRL + Right-drag: Move button", 1, 1, 1);
			end

			GameTooltip:Show();
		end);

		button:SetScript("OnLeave", function()
			GameTooltip:Hide();
		end);

		self.minimapButton = button;
		self:UpdateMinimapButtonPosition();
	end

	_M.UpdateMinimapButtonVisibility = function(self)
		-- Changes:
		-- 1. Shows or hides the minimap button based on saved settings.
		-- 2. Creates the button first if needed.

		if not self.minimapButton then
			self:CreateMinimapButton();
		end

		if self.settings.showMinimapButton then
			self.minimapButton:Show();
		else
			self.minimapButton:Hide();
		end
	end

	_M.SetMinimapButtonShown = function(self, isShown)
		-- Changes:
		-- 1. Saves the minimap button visibility setting.
		-- 2. Applies the visibility immediately.

		self.settings.showMinimapButton = isShown and true or false;
		self:UpdateMinimapButtonVisibility();
	end

	_M.CreateSettingsPanel = function(self)
		-- Changes:
		-- 1. Uses a custom Blizzard Settings canvas panel.
		-- 2. Adds Show/Hide Minimap Button.
		-- 3. Adds Lock Minimap Button Position.
		-- 4. Adds a professional About section at the bottom.
		-- 5. Uses read-only URL boxes for CurseForge and GitHub links.
		-- 6. Adds the addon logo in the top-right corner of the settings panel.

		if self.settingsPanelCreated then
			return;
		end

		local panel = CreateFrame("Frame", nil, UIParent);
		panel.name = self.ADDON_NAME;

		local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge");
		title:SetPoint("TOPLEFT", 16, -16);
		title:SetText("Easy Disenchant Revamped");

		local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
		subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8);
		subtitle:SetWidth(620);
		subtitle:SetJustifyH("LEFT");
		subtitle:SetText("Configuration options for Easy Disenchant Revamped.");

		panel.logo = panel:CreateTexture(nil, "ARTWORK");
		panel.logo:SetSize(40, 40);
		panel.logo:SetTexture("Interface\\AddOns\\EasyDisenchantRevamped\\Media\\icon_MiniMap_x32");
		panel.logo:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, -16);

		local minimapCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate");
		minimapCheckbox:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -20);
		minimapCheckbox.Text:SetText("Show Minimap Button");
		minimapCheckbox:SetChecked(self.settings.showMinimapButton);

		minimapCheckbox:SetScript("OnClick", function(button)
			_M:SetMinimapButtonShown(button:GetChecked());
		end);

		local lockCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate");
		lockCheckbox:SetPoint("TOPLEFT", minimapCheckbox, "BOTTOMLEFT", 0, -8);
		lockCheckbox.Text:SetText("Lock Minimap Button Position");
		lockCheckbox:SetChecked(self.settings.lockMinimapButton);

		lockCheckbox:SetScript("OnClick", function(button)
			_M:SetMinimapButtonLocked(button:GetChecked());
		end);

		local divider = panel:CreateTexture(nil, "ARTWORK");
		divider:SetColorTexture(1, 1, 1, 0.10);
		divider:SetHeight(1);
		divider:SetPoint("TOPLEFT", lockCheckbox, "BOTTOMLEFT", 0, -18);
		divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -140);

		local aboutHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
		aboutHeader:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -16);
		aboutHeader:SetText("About");

		local aboutText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
		aboutText:SetPoint("TOPLEFT", aboutHeader, "BOTTOMLEFT", 0, -10);
		aboutText:SetWidth(700);
		aboutText:SetJustifyH("LEFT");
		aboutText:SetSpacing(4);
		aboutText:SetText(
			"Developer: |cFFFFFFFFFSchokker|r\n" ..
			"Contributors/Collabs: |cFFFFFFFFMalitor|r\n" ..
			"Original Developers/Contributors: |cFFFFFFFFKruithne, Numy, robgha01|r"
		);

		local function CreateReadOnlyURLBox(parent, labelText, urlText, anchorTo)
			local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal");
			label:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -14);
			label:SetText(labelText);

			local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate");
			box:SetSize(520, 24);
			box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6);
			box:SetAutoFocus(false);
			box:SetTextInsets(6, 6, 0, 0);
			box:SetText(urlText);
			box:SetCursorPosition(0);

			box:SetScript("OnEscapePressed", function(self)
				self:ClearFocus();
			end);

			box:SetScript("OnEditFocusGained", function(self)
				self:HighlightText();
			end);

			box:SetScript("OnEditFocusLost", function(self)
				self:HighlightText(0, 0);
				self:SetCursorPosition(0);
			end);

			return box;
		end

		local curseforgeBox = CreateReadOnlyURLBox(
			panel,
			"CurseForge",
			"https://www.curseforge.com/wow/addons/easydisenchantrevamped",
			aboutText
		);

		local githubBox = CreateReadOnlyURLBox(
			panel,
			"Project GitHub",
			"https://github.com/FSchokker/EasyDisenchantRevamped",
			curseforgeBox
		);

		local footer = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall");
		footer:SetPoint("TOPLEFT", githubBox, "BOTTOMLEFT", 0, -14);
		footer:SetWidth(700);
		footer:SetJustifyH("LEFT");
		footer:SetText("Tip: Click into a link field to highlight it for copying.");

		local category = Settings.RegisterCanvasLayoutCategory(panel, self.ADDON_NAME, self.ADDON_NAME);
		Settings.RegisterAddOnCategory(category);

		self.settingsCategory = category;
		self.settingsPanel = panel;
		self.settingsPanelCreated = true;
	end

	--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	-- Localization helpers
	--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

	_M.ApplyLocalization = function(self, locale)
		local strings = self.Strings;
		for key, str in pairs(locale) do
			strings[key] = str;
		end
	end

	--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	-- Item handling helpers
	--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	
	_M.GetItemIDFromLink = function(itemLink)
		return tonumber(string_match(itemLink, "Hitem:(%d+)"));
	end

	_M.IsBlacklisted = function(self, itemID)
		-- 1. Supports the new rich blacklist entry format.
		-- 2. Still works during migration from old boolean entries.

		return self.blacklist[itemID] ~= nil;
	end

	_M.BlacklistItem = function(self, itemID, itemLink)
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

	--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	-- Main functions
	--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	
	_M.OnLoad = function(self)
		-- Changes:
		-- 1. Keeps slash command setup.
		-- 2. Initializes blacklist/settings saved variables.
		-- 3. Migrates old blacklist entries from itemID = true to rich entry tables.
		-- 4. Initializes minimap button settings.
		-- 5. Initializes minimap button visibility setting.
		-- 6. Initializes sort dropdown setting.
		-- 7. Creates the minimap button only if enabled.
		-- 8. Registers pending disenchant events.

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

		-- Default minimap button settings.
		if self.settings.minimapButtonAngle == nil then
			self.settings.minimapButtonAngle = 225;
		end

		if self.settings.showMinimapButton == nil then
			self.settings.showMinimapButton = true;
		end

		if self.settings.lockMinimapButton == nil then
			self.settings.lockMinimapButton = false;
		end

		if self.settings.disenchantViewMode == nil then
			self.settings.disenchantViewMode = "BUTTONS";
		end

		if self.settings.disenchantSortMode == nil then
			self.settings.disenchantSortMode = "BAG";
		end

		self.disenchantViewMode = self.settings.disenchantViewMode;
		self.disenchantSortMode = self.settings.disenchantSortMode;

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
					timeAdded = 0,
				};
			end
		end

		self:UpdateMinimapButtonVisibility();
		self:CreateSettingsPanel();

		self:SetEventHandler("UNIT_SPELLCAST_START", _M.OnUnitSpellcastStart);
		self:SetEventHandler("UNIT_SPELLCAST_SUCCEEDED", _M.OnUnitSpellcastSucceeded);
		self:SetEventHandler("UNIT_SPELLCAST_FAILED", _M.OnUnitSpellcastFailed);
		self:SetEventHandler("UNIT_SPELLCAST_INTERRUPTED", _M.OnUnitSpellcastInterrupted);
		self:SetEventHandler("BAG_UPDATE_DELAYED", _M.OnBagUpdateDelayed);
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

	--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	-- Disenchant Helpers
	--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	_M.ClearPendingDisenchant = function(self)
		-- Changes:
		-- 1. Clears the pending disenchant tracking fields.
		-- 2. Clears cast timing used by spinner/progress visuals.
		-- 3. Stops the pending visual updater.

		self.pendingDisenchantBagID = nil;
		self.pendingDisenchantSlotID = nil;
		self.pendingDisenchantItemID = nil;
		self.pendingDisenchantCastStartTimeMS = nil;
		self.pendingDisenchantCastEndTimeMS = nil;

		if self.disenchantFrame and self.disenchantFrame.pendingAnimationFrame then
			self.disenchantFrame.pendingAnimationFrame:Hide();
		end
	end

	_M.SetPendingDisenchant = function(self, bagID, slotID, itemID)
		-- Changes:
		-- 1. Stores the currently pending disenchant target.
		-- 2. Clears any old cast timing until UNIT_SPELLCAST_START refreshes it.

		self.pendingDisenchantBagID = bagID;
		self.pendingDisenchantSlotID = slotID;
		self.pendingDisenchantItemID = itemID;
		self.pendingDisenchantCastStartTimeMS = nil;
		self.pendingDisenchantCastEndTimeMS = nil;
	end

	_M.SetPendingDisenchantCastWindow = function(self, startTimeMS, endTimeMS)
		-- Changes:
		-- 1. Stores the active cast timing for spinner/progress visuals.
		-- 2. Starts the visual updater.

		self.pendingDisenchantCastStartTimeMS = startTimeMS;
		self.pendingDisenchantCastEndTimeMS = endTimeMS;

		if self.disenchantFrame and self.disenchantFrame.pendingAnimationFrame then
			self.disenchantFrame.pendingAnimationFrame:Show();
		end

		self:UpdatePendingDisenchantVisuals();
	end

	_M.IsPendingDisenchant = function(self, bagID, slotID, itemID)
		-- Changes:
		-- 1. Returns true when the given item matches the pending disenchant target.

		return self.pendingDisenchantBagID == bagID
			and self.pendingDisenchantSlotID == slotID
			and self.pendingDisenchantItemID == itemID;
	end

	_M.UpdatePendingDisenchantVisuals = function(self)
		-- Changes:
		-- 1. Updates the grid spinner-style cooldown overlay.
		-- 2. Updates the list row progress bar.
		-- 3. Hides visuals automatically when no active cast timing exists.

		if not self.disenchantFrame then
			return;
		end

		local startTimeMS = self.pendingDisenchantCastStartTimeMS;
		local endTimeMS = self.pendingDisenchantCastEndTimeMS;

		if not startTimeMS or not endTimeMS or endTimeMS <= startTimeMS then
			for i = 1, #self.itemButtons do
				local button = self.itemButtons[i];
				if button.pendingSpinner then
					button.pendingSpinner:Hide();
					button.pendingSpinner:Clear();
				end
			end

			for i = 1, #self.disenchantListRows do
				local row = self.disenchantListRows[i];
				if row.progressBar then
					row.progressBar:Hide();
					row.progressBar:SetValue(0);
				end
			end

			if self.disenchantFrame.pendingAnimationFrame then
				self.disenchantFrame.pendingAnimationFrame:Hide();
			end

			return;
		end

		local nowMS = GetTime() * 1000;
		local durationMS = endTimeMS - startTimeMS;
		local progress = (nowMS - startTimeMS) / durationMS;

		if progress < 0 then
			progress = 0;
		elseif progress > 1 then
			progress = 1;
		end

		local cooldownStart = startTimeMS / 1000;
		local cooldownDuration = durationMS / 1000;

		for i = 1, #self.itemButtons do
			local button = self.itemButtons[i];
			if button.pendingSpinner then
				local isPending = self:IsPendingDisenchant(button.bagID, button.slotID, button.itemID);

				if isPending then
					button.pendingSpinner:SetCooldown(cooldownStart, cooldownDuration);
					button.pendingSpinner:Show();
				else
					button.pendingSpinner:Hide();
					button.pendingSpinner:Clear();
				end
			end
		end

		for i = 1, #self.disenchantListRows do
			local row = self.disenchantListRows[i];
			if row.progressBar then
				local isPending = self:IsPendingDisenchant(row.bagID, row.slotID, row.itemID);

				if isPending then
					row.progressBar:SetValue(progress);
					row.progressBar:Show();
				else
					row.progressBar:SetValue(0);
					row.progressBar:Hide();
				end
			end
		end

		if progress >= 1 and self.disenchantFrame.pendingAnimationFrame then
			self.disenchantFrame.pendingAnimationFrame:Hide();
		end
	end

	_M.SetDisenchantSortMode = function(self, sortMode)
		-- Changes:
		-- 1. Saves the selected sort mode.
		-- 2. Updates the dropdown label text.
		-- 3. Refreshes the item list immediately.
		-- 4. Uses nicer user-facing labels.

		if not sortMode then
			sortMode = "BAG";
		end

		self.disenchantSortMode = sortMode;
		self.settings.disenchantSortMode = sortMode;

		if self.disenchantFrame and self.disenchantFrame.sortDropDown then
			local labelMap = {
				BAG = "Bag Order",
				ITEM_LEVEL_DESC = "iLvl: High to Low",
				ITEM_LEVEL_ASC = "iLvl: Low to High",
				QUALITY_DESC = "Quality: High to Low",
				QUALITY_ASC = "Quality: Low to High",
				NAME_ASC = "Name: A to Z",
				NAME_DESC = "Name: Z to A",
			};

			UIDropDownMenu_SetText(self.disenchantFrame.sortDropDown, labelMap[sortMode] or "Bag Order");
		end

		if self.disenchantFrame then
			self:UpdateItems();
		end
	end

	--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	-- Event Handlers
	--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	
	_M.OnUnitSpellcastStart = function(self, unitTarget, castGUID, spellID)
		-- Changes:
		-- 1. Captures Disenchant cast timing from the player.
		-- 2. Starts spinner/progress visuals in sync with the cast bar.

		if unitTarget ~= "player" then
			return;
		end

		if spellID ~= 13262 then
			return;
		end

		local _, _, _, startTimeMS, endTimeMS = UnitCastingInfo("player");
		if startTimeMS and endTimeMS then
			self:SetPendingDisenchantCastWindow(startTimeMS, endTimeMS);
		end
	end

	_M.OnUnitSpellcastSucceeded = function(self, unitTarget, castGUID, spellID)
		-- Changes:
		-- 1. Leaves pending state in place until BAG_UPDATE_DELAYED removes the item.
		-- 2. Prevents early refresh before the inventory actually changes.

		if unitTarget ~= "player" then
			return;
		end

		if spellID ~= 13262 then
			return;
		end
	end

	_M.OnUnitSpellcastFailed = function(self, unitTarget, castGUID, spellID)
		-- Changes:
		-- 1. Clears pending state if Disenchant fails.
		-- 2. Refreshes both views immediately.

		if unitTarget ~= "player" then
			return;
		end

		if spellID ~= 13262 then
			return;
		end

		self:ClearPendingDisenchant();
		self:UpdateItems();
	end

	_M.OnUnitSpellcastInterrupted = function(self, unitTarget, castGUID, spellID)
		-- Changes:
		-- 1. Clears pending state if Disenchant is interrupted.
		-- 2. Refreshes both views immediately.

		if unitTarget ~= "player" then
			return;
		end

		if spellID ~= 13262 then
			return;
		end

		self:ClearPendingDisenchant();
		self:UpdateItems();
	end

	_M.OnBagUpdateDelayed = function(self)
		-- Changes:
		-- 1. Adds a tiny completion flash.
		-- 2. Refreshes the item views after a short delay.
		-- 3. Clears pending state afterward.

		if self.pendingDisenchantItemID == nil then
			return;
		end

		self:PlayPendingCompleteFlash();

		C_Timer.After(0.08, function()
			_M:ClearPendingDisenchant();
			_M:UpdateItems();
		end);
	end

	_M.PlayPendingCompleteFlash = function(self)
		-- NEW:
		-- 1. Plays a small completion flash on the pending grid button.
		-- 2. Runs just before the item list refresh removes the button.

		if not self.disenchantFrame then
			return;
		end

		for i = 1, #self.itemButtons do
			local button = self.itemButtons[i];

			if self:IsPendingDisenchant(button.bagID, button.slotID, button.itemID) then
				if button.completeFlashAnim then
					button.completeFlashAnim:Stop();
				end

				button.completeFlash:Show();
				button.completeFlashAnim:Play();
				return;
			end
		end
	end

	_M.GetItemButtonRenderingCache = function(self)
		-- Changes:
		-- 1. Keeps the current click/tooltip behavior.
		-- 2. Adds a subtle pending overlay texture to each grid button.
		-- 3. Leaves the item visible until the disenchant actually completes.

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
						_M:UpdateItems();
					else
						_M:SetPendingDisenchant(self.bagID, self.slotID, self.itemID);
						_M:UpdateItems();
					end
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
						{
							injectSelf = "backdrop",
							layer = "BACKGROUND",
							texture = [[Interface\Buttons\UI-EmptySlot-Disabled]],
							size = 54,
						},
						{
							injectSelf = "pendingShade",
							layer = "OVERLAY",
							size = 54,
							color = { 0, 0, 0, 0.35 },
							hidden = true,
						},
					},
					points = {
						point = "TOPLEFT",
						x = 0 + (38 * column),
						y = 0 + (row * -38)
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
		-- Changes:
		-- 1. Keeps the spinner overlay.
		-- 2. Adds a tiny completion flash animation for successful disenchant.
		-- 3. Adds item level text to the bottom-right of each grid icon.
		-- 4. Uses an outlined font for better readability.

		local buttons = self.itemButtons;
		if buttons[index + 1] then
			return buttons[index + 1];
		end

		local cache = self:GetItemButtonRenderingCache();
		local button = _K:Frame(cache.factory(index));

		button:HookScript("OnClick", cache.func_clickHook);
		button:RegisterForClicks("LeftButtonDown", "RightButtonDown");
		button:SetAttribute("useOnKeyDown", true);

		button.pendingSpinner = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate");
		button.pendingSpinner:SetAllPoints(button);
		button.pendingSpinner:SetDrawEdge(false);
		button.pendingSpinner:SetDrawSwipe(true);
		button.pendingSpinner:SetReverse(false);
		button.pendingSpinner:Hide();

		button.completeFlash = button:CreateTexture(nil, "OVERLAY");
		button.completeFlash:SetAllPoints(true);
		button.completeFlash:SetColorTexture(1, 1, 1, 0.75);
		button.completeFlash:Hide();

		button.completeFlashAnim = button:CreateAnimationGroup();

		local fadeIn = button.completeFlashAnim:CreateAnimation("Alpha");
		fadeIn:SetOrder(1);
		fadeIn:SetFromAlpha(0);
		fadeIn:SetToAlpha(0.75);
		fadeIn:SetDuration(0.08);

		local fadeOut = button.completeFlashAnim:CreateAnimation("Alpha");
		fadeOut:SetOrder(2);
		fadeOut:SetFromAlpha(0.75);
		fadeOut:SetToAlpha(0);
		fadeOut:SetDuration(0.18);

		button.completeFlashAnim:SetScript("OnFinished", function()
			button.completeFlash:Hide();
		end);

		-- Item level text
		button.itemLevelText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmallOutline");
		button.itemLevelText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2);
		button.itemLevelText:SetJustifyH("RIGHT");
		button.itemLevelText:SetText("");
		button.itemLevelText:SetTextColor(1, 1, 1, 1);

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

	_M.GetDisenchantListRow = function(self, index)
		-- Changes:
		-- 1. Keeps the subtle hover highlight.
		-- 2. Adds a progress bar for pending disenchant.
		-- 3. Left-click marks the row pending immediately.
		-- 4. Right-click still blacklists immediately.
		-- 5. Adds an outlined item level label on the right side of the row.

		local rows = self.disenchantListRows;
		if rows[index] then
			return rows[index];
		end

		local frame = self.disenchantFrame;
		local rowHeight = 28;

		local row = CreateFrame("Button", "$parentDisenchantListRow" .. index, frame.disenchantListScrollChild, "SecureActionButtonTemplate");
		row:SetHeight(rowHeight);
		row:SetPoint("TOPLEFT", frame.disenchantListScrollChild, "TOPLEFT", 0, -((index - 1) * rowHeight));
		row:SetPoint("TOPRIGHT", frame.disenchantListScrollChild, "TOPRIGHT", 0, -((index - 1) * rowHeight));
		row:RegisterForClicks("LeftButtonDown", "RightButtonDown");
		row:SetAttribute("useOnKeyDown", true);
		row:Hide();

		row.bg = row:CreateTexture(nil, "BACKGROUND");
		row.bg:SetAllPoints(true);
		row.bg:SetColorTexture(1, 1, 1, 0.03);

		row.hover = row:CreateTexture(nil, "HIGHLIGHT");
		row.hover:SetAllPoints(true);
		row.hover:SetColorTexture(1, 1, 1, 0.08);

		row.pendingShade = row:CreateTexture(nil, "OVERLAY");
		row.pendingShade:SetAllPoints(true);
		row.pendingShade:SetColorTexture(0, 0, 0, 0.18);
		row.pendingShade:Hide();

		row.icon = row:CreateTexture(nil, "ARTWORK");
		row.icon:SetSize(20, 20);
		row.icon:SetPoint("LEFT", row, "LEFT", 4, 0);

		row.itemLevelText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmallOutline");
		row.itemLevelText:SetPoint("RIGHT", row, "RIGHT", -6, 0);
		row.itemLevelText:SetWidth(34);
		row.itemLevelText:SetJustifyH("RIGHT");
		row.itemLevelText:SetText("");
		row.itemLevelText:SetTextColor(0.82, 0.82, 0.82, 1);

		row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0);
		row.text:SetPoint("RIGHT", row.itemLevelText, "LEFT", -8, 0);
		row.text:SetJustifyH("LEFT");

		row.progressBackground = row:CreateTexture(nil, "BORDER");
		row.progressBackground:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 2);
		row.progressBackground:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2);
		row.progressBackground:SetHeight(3);
		row.progressBackground:SetColorTexture(0, 0, 0, 0.35);
		row.progressBackground:Hide();

		row.progressBar = CreateFrame("StatusBar", nil, row);
		row.progressBar:SetPoint("TOPLEFT", row.progressBackground, "TOPLEFT", 0, 0);
		row.progressBar:SetPoint("BOTTOMRIGHT", row.progressBackground, "BOTTOMRIGHT", 0, 0);
		row.progressBar:SetMinMaxValues(0, 1);
		row.progressBar:SetValue(0);
		row.progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");
		row.progressBar:SetStatusBarColor(0.85, 0.85, 1, 0.9);
		row.progressBar:Hide();

		row:SetScript("OnEnter", function(self)
			if self.link then
				GameTooltip:SetOwner(self, "ANCHOR_LEFT");
				GameTooltip:SetHyperlink(self.link);
				GameTooltip:Show();
			end
		end);

		row:SetScript("OnLeave", function()
			GameTooltip:Hide();
		end);

		row:HookScript("OnClick", function(self, key)
			if InCombatLockdown() then
				frame.header:SetText(ERR_NOT_IN_COMBAT);
				frame.header:SetTextColor(1, 0, 0);
			else
				if key == "RightButton" then
					_M:BlacklistItem(self.itemID, self.link);
					_M:UpdateItems();
				else
					_M:SetPendingDisenchant(self.bagID, self.slotID, self.itemID);
					_M:UpdateItems();
				end
			end
		end);

		rows[index] = row;
		return row;
	end

	_M.UpdateDisenchantListRows = function(self, entries)
		-- Changes:
		-- 1. Keeps the current list population logic.
		-- 2. Shows "Disenchanting..." while a row is pending.
		-- 3. Keeps the progress bar and muted pending styling.
		-- 4. Shows item level on the right side of each row.

		if not self.disenchantFrame or not self.disenchantFrame.disenchantListScrollFrame or not self.disenchantFrame.disenchantListScrollChild then
			return;
		end

		local rows = self.disenchantListRows;
		local rowHeight = 28;
		local contentHeight = #entries * rowHeight;

		if contentHeight < 1 then
			contentHeight = 1;
		end

		self.disenchantFrame.disenchantListScrollChild:SetHeight(contentHeight);

		for i = 1, #entries do
			local entry = entries[i];
			local row = self:GetDisenchantListRow(i);

			row.itemID = entry.itemID;
			row.link = entry.link;
			row.bagID = entry.bagID;
			row.slotID = entry.slotID;

			row:SetAttribute("type", "macro");
			row:SetAttribute("macrotext", entry.macrotext);

			if entry.iconFileID then
				row.icon:SetTexture(entry.iconFileID);
			else
				row.icon:SetTexture([[Interface\Icons\INV_Misc_QuestionMark]]);
			end

			if entry.itemLevel and entry.itemLevel > 0 then
				row.itemLevelText:SetText(entry.itemLevel);
			else
				row.itemLevelText:SetText("");
			end

			if entry.isPending then
				row.text:SetText("Disenchanting...");
				row.pendingShade:Show();
				row.icon:SetDesaturated(true);
				row.text:SetTextColor(0.78, 0.78, 0.78, 1);
				row.itemLevelText:SetTextColor(0.78, 0.78, 0.78, 1);
				row.progressBackground:Show();
			else
				if entry.link then
					row.text:SetText(entry.link);
				else
					row.text:SetText("Item ID: " .. tostring(entry.itemID));
				end

				row.pendingShade:Hide();
				row.icon:SetDesaturated(false);
				row.text:SetTextColor(1, 1, 1, 1);
				row.itemLevelText:SetTextColor(0.82, 0.82, 0.82, 1);
				row.progressBackground:Hide();
				row.progressBar:Hide();
				row.progressBar:SetValue(0);
			end

			row:Show();
		end

		for i = #entries + 1, #rows do
			rows[i]:Hide();
		end

		self.disenchantFrame.disenchantListScrollFrame:SetVerticalScroll(0);

		self:UpdatePendingDisenchantVisuals();
	end

	_M.SortDisenchantEntries = function(self, entries)
		-- Changes:
		-- 1. Sorts scanned entries before they are rendered into grid/list views.
		-- 2. Supports bag order, item level, quality, and name sorting.
		-- 3. Falls back to bag/slot for stable ordering.

		local sortMode = self.disenchantSortMode or "BAG";

		table.sort(entries, function(a, b)
			if sortMode == "ITEM_LEVEL_DESC" then
				if (a.itemLevel or 0) ~= (b.itemLevel or 0) then
					return (a.itemLevel or 0) > (b.itemLevel or 0);
				end
			elseif sortMode == "ITEM_LEVEL_ASC" then
				if (a.itemLevel or 0) ~= (b.itemLevel or 0) then
					return (a.itemLevel or 0) < (b.itemLevel or 0);
				end
			elseif sortMode == "QUALITY_DESC" then
				if (a.quality or 0) ~= (b.quality or 0) then
					return (a.quality or 0) > (b.quality or 0);
				end
			elseif sortMode == "QUALITY_ASC" then
				if (a.quality or 0) ~= (b.quality or 0) then
					return (a.quality or 0) < (b.quality or 0);
				end
			elseif sortMode == "NAME_ASC" then
				local aName = a.itemName or "";
				local bName = b.itemName or "";

				if aName ~= bName then
					return aName < bName;
				end
			elseif sortMode == "NAME_DESC" then
				local aName = a.itemName or "";
				local bName = b.itemName or "";

				if aName ~= bName then
					return aName > bName;
				end
			end

			-- Stable fallback: bag then slot
			if a.bagID ~= b.bagID then
				return a.bagID < b.bagID;
			end

			return a.slotID < b.slotID;
		end);

		return entries;
	end

	_M.UpdateItems = function(self)
		-- Changes:
		-- 1. Scans all valid disenchantable items first.
		-- 2. Stores sort metadata (item level, quality, item name).
		-- 3. Sorts entries using the selected sort mode.
		-- 4. Builds both grid and list views from the same sorted results.

		local buttons = self.itemButtons;
		local nButtons = #buttons;

		for i = 1, nButtons do
			buttons[i]:Hide();
		end

		local disenchantName = C_Spell.GetSpellName(13262);
		local macroFormat = "/stopmacro [combat][btn:2]\n/stopcasting\n/cast %s\n/cast %s %s";

		self:ResetEquipmentManagerCache();

		local scannedEntries = {};

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
									local currentItemLevel = C_Item.GetDetailedItemLevelInfo(item.hyperlink) or 0;
									local macrotext = format(macroFormat, disenchantName, bagID, slotID);
									local isPending = self:IsPendingDisenchant(bagID, slotID, itemID);

									scannedEntries[#scannedEntries + 1] = {
										itemID = itemID,
										link = item.hyperlink,
										iconFileID = item.iconFileID,
										macrotext = macrotext,
										bagID = bagID,
										slotID = slotID,
										isPending = isPending,
										itemLevel = currentItemLevel,
										quality = item.quality,
										itemName = itemName,
									};
								end
							end
						end
					end
				end
			end
		end

		self:SortDisenchantEntries(scannedEntries);

		local useButton = 0;
		local listEntries = {};

		for i = 1, #scannedEntries do
			local entry = scannedEntries[i];

			local button = self:GetItemButton(useButton);

			SetItemButtonTexture(button, entry.iconFileID);
			SetItemButtonQuality(button, entry.quality, entry.link);

			button:SetAttribute("type", "macro");
			button:SetAttribute("macrotext", entry.macrotext);

			button.link = entry.link;
			button.itemID = entry.itemID;
			button.bagID = entry.bagID;
			button.slotID = entry.slotID;

			if entry.itemLevel and entry.itemLevel > 0 then
				button.itemLevelText:SetText(entry.itemLevel);
			else
				button.itemLevelText:SetText("");
			end

			if entry.isPending then
				button:SetAlpha(0.70);
				if button.pendingShade then
					button.pendingShade:Show();
				end
			else
				button:SetAlpha(1);
				if button.pendingShade then
					button.pendingShade:Hide();
				end
			end

			button:Show();

			listEntries[#listEntries + 1] = entry;

			useButton = useButton + 1;

			if useButton >= self.maxButtons then
				self:UpdateWindowHeight(useButton);
				self:UpdateDisenchantListRows(listEntries);
				return;
			end
		end

		self:UpdateWindowHeight(useButton);
		self:UpdateDisenchantListRows(listEntries);
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
		-- Changes:
		-- 1. Switches between the Disenchant and Blacklist content regions.
		-- 2. Keeps Blizzard tab selected/deselected state.
		-- 3. Restores the current Disenchant sub-view when switching back.
		-- 4. Refreshes blacklist view when switching to Blacklist.

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

			self:RefreshDisenchantView();
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
		-- Changes:
		-- 1. Matches the Disenchant list row styling more closely.
		-- 2. Adds a subtle hover highlight.
		-- 3. Adds a bottom accent bar for cleaner polish.
		-- 4. Keeps the Remove button and tooltip behavior.

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

		row.hover = row:CreateTexture(nil, "HIGHLIGHT");
		row.hover:SetAllPoints(true);
		row.hover:SetColorTexture(1, 1, 1, 0.08);

		row.icon = row:CreateTexture(nil, "ARTWORK");
		row.icon:SetSize(20, 20);
		row.icon:SetPoint("LEFT", row, "LEFT", 4, 0);

		row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0);
		row.text:SetPoint("RIGHT", row, "RIGHT", -70, 0);
		row.text:SetJustifyH("LEFT");

		row.bottomAccent = row:CreateTexture(nil, "BORDER");
		row.bottomAccent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 2);
		row.bottomAccent:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2);
		row.bottomAccent:SetHeight(3);
		row.bottomAccent:SetColorTexture(0, 0, 0, 0.35);

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

	_M.UpdateDisenchantViewButtons = function(self)
		-- NEW:
		-- 1. Updates the graphic state for the Buttons/List view icons.
		-- 2. Shows Active art for the selected mode.
		-- 3. Shows Inactive/Hover art for the non-selected mode.

		if not self.disenchantFrame then
			return;
		end

		local frame = self.disenchantFrame;
		local mediaPath = "Interface\\AddOns\\EasyDisenchantRevamped\\Media\\";

		local isListView = (self.disenchantViewMode == "LIST");

		if isListView then
			frame.disenchantButtonViewButton.icon:SetTexture(mediaPath .. "Icons_GridView_Inactive_x32");
			frame.disenchantListViewButton.icon:SetTexture(mediaPath .. "Icons_ListView_Active_x32");
		else
			frame.disenchantButtonViewButton.icon:SetTexture(mediaPath .. "Icons_GridView_Active_x32");
			frame.disenchantListViewButton.icon:SetTexture(mediaPath .. "Icons_ListView_Inactive_x32");
		end
	end

	_M.SetDisenchantViewMode = function(self, viewMode)
		-- Changes:
		-- 1. Switches between the Disenchant button grid and Disenchant list container.
		-- 2. Updates the selected state of the two view toggle buttons.
		-- 3. Saves the selected view mode.

		if not self.disenchantFrame then
			return;
		end

		self.disenchantViewMode = viewMode;
		self.settings.disenchantViewMode = viewMode;

		local frame = self.disenchantFrame;

		if viewMode == "LIST" then
			frame.scrollFrame:Hide();
			frame.disenchantListContent:Show();

			frame.disenchantButtonViewButton.icon:SetDesaturated(false);
			frame.disenchantListViewButton.icon:SetDesaturated(false);
		else
			frame.disenchantListContent:Hide();
			frame.scrollFrame:Show();
		end

		self:UpdateDisenchantViewButtons();
	end

	_M.RefreshDisenchantView = function(self)
		-- Changes:
		-- 1. Re-applies the current Disenchant view mode after data/UI refreshes.

		self:SetDisenchantViewMode(self.disenchantViewMode or "BUTTONS");
	end

	_M.CreateDisenchantFrame = function(self)
		-- Changes:
		-- 1. Creates the grid/list buttons before anchoring the sort controls to them.
		-- 2. Keeps your title icon, tabs, scroll frames, and view toggle icons.
		-- 3. Keeps the saved sort mode initialization.

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

		-- Add addon icon beside the title
		self.disenchantFrame.titleIcon = self.disenchantFrame:CreateTexture(nil, "ARTWORK");
		self.disenchantFrame.titleIcon:SetSize(32, 32);
		self.disenchantFrame.titleIcon:SetTexture("Interface\\AddOns\\EasyDisenchantRevamped\\Media\\icon_MiniMap_x32");
		self.disenchantFrame.titleIcon:SetPoint("TOPLEFT", self.disenchantFrame, "TOPLEFT", 24, -28);

		-- Move title slightly right so it lines up nicely with the icon
		self.disenchantFrame.header:ClearAllPoints();
		self.disenchantFrame.header:SetPoint("TOPLEFT", self.disenchantFrame.titleIcon, "TOPRIGHT", 8, -10);

		-- Create tab buttons.
		self.disenchantFrame.disenchantTabButton = CreateFrame("Button", "$parentDisenchantTabButton", self.disenchantFrame, "PanelTopTabButtonTemplate");
		self.disenchantFrame.disenchantTabButton:SetID(1);
		self.disenchantFrame.disenchantTabButton:SetText("Disenchant");
		PanelTemplates_TabResize(self.disenchantFrame.disenchantTabButton, 20);
		self.disenchantFrame.disenchantTabButton:SetPoint("TOPLEFT", self.disenchantFrame, "TOPLEFT", 24, -56);
		self.disenchantFrame.disenchantTabButton:SetScript("OnClick", function()
			_M:SetActiveTab("DISENCHANT");
		end);

		self.disenchantFrame.blacklistTabButton = CreateFrame("Button", "$parentBlacklistTabButton", self.disenchantFrame, "PanelTopTabButtonTemplate");
		self.disenchantFrame.blacklistTabButton:SetID(2);
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
		self.disenchantFrame.scrollFrame:SetPoint("TOPLEFT", self.disenchantFrame.disenchantContent, "TOPLEFT", 20, -30);
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

		-- Disenchant controls (view buttons first, then sort controls)
		local mediaPath = "Interface\\AddOns\\EasyDisenchantRevamped\\Media\\";

		self.disenchantFrame.disenchantButtonViewButton = CreateFrame("Button", "$parentDisenchantButtonViewButton", self.disenchantFrame.disenchantContent);
		self.disenchantFrame.disenchantButtonViewButton:SetSize(22, 22);
		self.disenchantFrame.disenchantButtonViewButton:SetPoint("TOPRIGHT", self.disenchantFrame.disenchantContent, "TOPRIGHT", -30, 0);
		self.disenchantFrame.disenchantButtonViewButton:SetScript("OnClick", function()
			_M:SetDisenchantViewMode("BUTTONS");
		end);

		self.disenchantFrame.disenchantButtonViewButton.icon = self.disenchantFrame.disenchantButtonViewButton:CreateTexture(nil, "ARTWORK");
		self.disenchantFrame.disenchantButtonViewButton.icon:SetAllPoints(true);
		self.disenchantFrame.disenchantButtonViewButton.icon:SetTexture(mediaPath .. "Icons_GridView_Active_x32");

		self.disenchantFrame.disenchantButtonViewButton:SetScript("OnEnter", function(button)
			if _M.disenchantViewMode ~= "BUTTONS" then
				button.icon:SetTexture(mediaPath .. "Icons_GridView_Hover_x32");
			end
		end);

		self.disenchantFrame.disenchantButtonViewButton:SetScript("OnLeave", function(button)
			if _M.disenchantViewMode ~= "BUTTONS" then
				button.icon:SetTexture(mediaPath .. "Icons_GridView_Inactive_x32");
			end
		end);

		self.disenchantFrame.disenchantListViewButton = CreateFrame("Button", "$parentDisenchantListViewButton", self.disenchantFrame.disenchantContent);
		self.disenchantFrame.disenchantListViewButton:SetSize(22, 22);
		self.disenchantFrame.disenchantListViewButton:SetPoint("RIGHT", self.disenchantFrame.disenchantButtonViewButton, "LEFT", -4, 0);
		self.disenchantFrame.disenchantListViewButton:SetScript("OnClick", function()
			_M:SetDisenchantViewMode("LIST");
		end);

		self.disenchantFrame.disenchantListViewButton.icon = self.disenchantFrame.disenchantListViewButton:CreateTexture(nil, "ARTWORK");
		self.disenchantFrame.disenchantListViewButton.icon:SetAllPoints(true);
		self.disenchantFrame.disenchantListViewButton.icon:SetTexture(mediaPath .. "Icons_ListView_Inactive_x32");

		self.disenchantFrame.disenchantListViewButton:SetScript("OnEnter", function(button)
			if _M.disenchantViewMode ~= "LIST" then
				button.icon:SetTexture(mediaPath .. "Icons_ListView_Hover_x32");
			end
		end);

		self.disenchantFrame.disenchantListViewButton:SetScript("OnLeave", function(button)
			if _M.disenchantViewMode ~= "LIST" then
				button.icon:SetTexture(mediaPath .. "Icons_ListView_Inactive_x32");
			end
		end);

		self.disenchantFrame.sortLabel = self.disenchantFrame.disenchantContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		self.disenchantFrame.sortLabel:SetPoint("RIGHT", self.disenchantFrame.disenchantListViewButton, "LEFT", -170, 0);
		self.disenchantFrame.sortLabel:SetText("Sort By:");

		self.disenchantFrame.sortDropDown = CreateFrame("Frame", "$parentSortDropDown", self.disenchantFrame.disenchantContent, "UIDropDownMenuTemplate");
		self.disenchantFrame.sortDropDown:SetPoint("LEFT", self.disenchantFrame.sortLabel, "RIGHT", -12, -2);
		UIDropDownMenu_SetWidth(self.disenchantFrame.sortDropDown, 135);
		UIDropDownMenu_SetText(self.disenchantFrame.sortDropDown, "Bag Order");

		self.disenchantFrame.sortDropDown:SetScript("OnEnter", function()
			GameTooltip:SetOwner(self.disenchantFrame.sortDropDown, "ANCHOR_TOP");
			GameTooltip:SetText("Sort Items");
			GameTooltip:AddLine("Choose how disenchantable items are ordered.", 1, 1, 1, true);
			GameTooltip:Show();
		end);

		self.disenchantFrame.sortDropDown:SetScript("OnLeave", function()
			GameTooltip:Hide();
		end);

		UIDropDownMenu_Initialize(self.disenchantFrame.sortDropDown, function(dropdown, level)
			local info = UIDropDownMenu_CreateInfo();

			info.func = function(buttonSelf)
				_M:SetDisenchantSortMode(buttonSelf.value);
			end

			info.text = "Bag Order";
			info.value = "BAG";
			info.checked = (_M.disenchantSortMode == "BAG");
			UIDropDownMenu_AddButton(info, level);

			info.text = "iLvl: High to Low";
			info.value = "ITEM_LEVEL_DESC";
			info.checked = (_M.disenchantSortMode == "ITEM_LEVEL_DESC");
			UIDropDownMenu_AddButton(info, level);

			info.text = "iLvl: Low to High";
			info.value = "ITEM_LEVEL_ASC";
			info.checked = (_M.disenchantSortMode == "ITEM_LEVEL_ASC");
			UIDropDownMenu_AddButton(info, level);

			info.text = "Quality: High to Low";
			info.value = "QUALITY_DESC";
			info.checked = (_M.disenchantSortMode == "QUALITY_DESC");
			UIDropDownMenu_AddButton(info, level);

			info.text = "Quality: Low to High";
			info.value = "QUALITY_ASC";
			info.checked = (_M.disenchantSortMode == "QUALITY_ASC");
			UIDropDownMenu_AddButton(info, level);

			info.text = "Name: A to Z";
			info.value = "NAME_ASC";
			info.checked = (_M.disenchantSortMode == "NAME_ASC");
			UIDropDownMenu_AddButton(info, level);

			info.text = "Name: Z to A";
			info.value = "NAME_DESC";
			info.checked = (_M.disenchantSortMode == "NAME_DESC");
			UIDropDownMenu_AddButton(info, level);
		end);

		-- Initialize dropdown text from saved sort mode.
		self:SetDisenchantSortMode(self.disenchantSortMode or "BAG");

		self.disenchantFrame.disenchantListContent = CreateFrame("FRAME", "$parentDisenchantListContent", self.disenchantFrame.disenchantContent);
		self.disenchantFrame.disenchantListContent:SetPoint("TOPLEFT", self.disenchantFrame.disenchantContent, "TOPLEFT", 20, -30);
		self.disenchantFrame.disenchantListContent:SetPoint("BOTTOMRIGHT", self.disenchantFrame.disenchantContent, "BOTTOMRIGHT", -10, 4);
		self.disenchantFrame.disenchantListContent:Hide();

		self.disenchantFrame.disenchantListScrollFrame = CreateFrame("ScrollFrame", "$parentDisenchantListScrollFrame", self.disenchantFrame.disenchantListContent, "UIPanelScrollFrameTemplate");
		self.disenchantFrame.disenchantListScrollFrame:SetPoint("TOPLEFT", self.disenchantFrame.disenchantListContent, "TOPLEFT", 0, 0);
		self.disenchantFrame.disenchantListScrollFrame:SetPoint("BOTTOMRIGHT", self.disenchantFrame.disenchantListContent, "BOTTOMRIGHT", 0, 0);
		self.disenchantFrame.disenchantListScrollFrame:EnableMouseWheel(true);

		self.disenchantFrame.disenchantListScrollChild = CreateFrame("FRAME", "$parentDisenchantListScrollChild", self.disenchantFrame.disenchantListScrollFrame);
		self.disenchantFrame.disenchantListScrollChild:SetSize(344, 1);
		self.disenchantFrame.disenchantListScrollFrame:SetScrollChild(self.disenchantFrame.disenchantListScrollChild);

		self.disenchantFrame.disenchantListScrollFrame:SetScript("OnMouseWheel", function(scrollFrame, delta)
			local currentScroll = scrollFrame:GetVerticalScroll();
			local maxScroll = math.max(0, scrollFrame.disenchantListScrollChild:GetHeight() - scrollFrame:GetHeight());
			local newScroll = currentScroll - (delta * 28);

			if newScroll < 0 then
				newScroll = 0;
			elseif newScroll > maxScroll then
				newScroll = maxScroll;
			end

			scrollFrame:SetVerticalScroll(newScroll);
		end);

		self.disenchantFrame.disenchantListScrollFrame.disenchantListScrollChild = self.disenchantFrame.disenchantListScrollChild;

		-- Blacklist tab scroll frame
		self.disenchantFrame.blacklistScrollFrame = CreateFrame("ScrollFrame", "$parentBlacklistScrollFrame", self.disenchantFrame.blacklistContent, "UIPanelScrollFrameTemplate");
		self.disenchantFrame.blacklistScrollFrame:SetPoint("TOPLEFT", self.disenchantFrame.blacklistContent, "TOPLEFT", 20, -30);
		self.disenchantFrame.blacklistScrollFrame:SetPoint("BOTTOMRIGHT", self.disenchantFrame.blacklistContent, "BOTTOMRIGHT", -10, 4);
		self.disenchantFrame.blacklistScrollFrame:EnableMouseWheel(true);

		self.disenchantFrame.blacklistScrollChild = CreateFrame("FRAME", "$parentBlacklistScrollChild", self.disenchantFrame.blacklistScrollFrame);
		self.disenchantFrame.blacklistScrollChild:SetSize(344, 1);
		self.disenchantFrame.blacklistScrollFrame:SetScrollChild(self.disenchantFrame.blacklistScrollChild);

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

		self.disenchantFrame.blacklistScrollFrame.blacklistScrollChild = self.disenchantFrame.blacklistScrollChild;

		self.disenchantFrame.pendingAnimationFrame = CreateFrame("Frame", nil, self.disenchantFrame);
		self.disenchantFrame.pendingAnimationFrame:Hide();
		self.disenchantFrame.pendingAnimationFrame:SetScript("OnUpdate", function()
			_M:UpdatePendingDisenchantVisuals();
		end);

		self:RestoreWindowPosition();
		self:RegisterEscapeFrame();
		self:SetActiveTab("DISENCHANT");
		self:SetDisenchantViewMode(self.disenchantViewMode or "BUTTONS");
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
