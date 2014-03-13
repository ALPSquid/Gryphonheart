--===================================================
--
--				GHM_MultiPageToolbar
--  			GHM_MultiPageToolbar.lua
--
--	          (description)
--
-- 	  (c)2013 The Gryphonheart Team
--			All rights reserved
--===================================================

local count = 1;
function GHM_MultiPageToolbar(parent, main, profile)
	local frame = CreateFrame("Frame", "GHM_MultiPageToolbar" .. count, parent);
	count = count + 1;

	local height,width = 0,0;
	local pages = {};

	local lastClicked;
	local TogglePage = function(self)
		if lastClicked then
			lastClicked:Enable();
			pages[lastClicked.id]:Hide();
		end
		self:Disable();
		pages[self.id]:Show();
		lastClicked = self;
	end


	-- todo: use GuildRosterColumnButtonTemplate instead.
	local buttonRowProfile = {};
	local firstButton
	for i = 1,#(profile) do
		table.insert(buttonRowProfile,{
			type = "Button",
			text = profile[i].name,
			align = "l",
			compact = true,
			OnClick = function(self)
				TogglePage(self);
			end,
			OnLoad = function(self)
				self:SetDisabledTexture(self:GetPushedTexture());
				self.id = i;
				if i == 1 then
					firstButton = self;
				end
			end,
		})
	end

	local buttonRow = GHM_ToolbarObjectRow(frame, main, buttonRowProfile);
	buttonRow:SetPoint("TOPLEFT", frame, "TOPLEFT");

	for i=1,#(profile) do
		local page = GHM_ToolbarPage(frame, main, profile[i]);
		page:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -buttonRow:GetHeight());

		width = math.max(width, page:GetWidth());
		height = math.max(height, page:GetHeight());

		table.insert(pages, page)
	end

	height = height + buttonRow:GetHeight()
	width = math.max(width, buttonRow:GetWidth())

	frame:SetHeight(height);
	frame:SetWidth(width);

	TogglePage(firstButton);

	return frame;
end

