﻿--
--									
--					GHI Position
--					GHI_Position.lua
--
--		Information about position of the user
--	
-- 			(c)2013 The Gryphonheart Team
--				All rights reserved
--


function GHI_Position(useVersion1Coor)
	local class = GHClass("GHI_Position")

	--local variables
	local continent
	local currentContinent
	local x
	local y
	local zoneIndex
	local areaID
	local floorLevel;
	local dungeonLevel;
	local dungeonLevelDropDownShown;


	GHI_Event("GHP_LOADED",function()
		if GHP_FloorLevelDetermination then
			floorLevel = GHP_FloorLevelDetermination();
		end
	end);


	local Round = function(num,decimals)
		if decimals then
			return tonumber(string.format("%."..decimals.."f",num));
		end
		return num;
	end

	local ConvertMopToCata = function(x_mop,y_mop)
		local x_cata = 1.243338591 * x_mop - 2822.734638;
		local y_cata = 1.243339374 * y_mop - 409.9540594;
		return x_cata,y_cata;
	end

	local IsMopClient = function()
		local _, _, _, tocVersion = GetBuildInfo()
		return tocVersion >= 50000;
	end

	local DROPDOWNS = {"Level","Continent","Zone","ZoneMinimap"};
	local DD;
	local ClickDD = function(n)
		local f = _G["WorldMap"..n.."DropDownButton"];
		f:GetScript("OnClick")(f)
	end

	local SetMapToCurrentZone = function()
        WorldMapFrame:SetMapID(C_Map.GetBestMapForUnit("player"))
	end

	local ResetMap = function()
		SetMapToCurrentZone();
		if C_Map.GetMapInfo(C_Map.GetBestMapForUnit("player")) == areaID then
			SetDungeonMapLevel(dungeonLevel);
		elseif areaID == -1 then
			if continent == -1 then -- cosmos
				SetMapZoom(-1);
			else -- Azeroth
				SetMapZoom(0);
			end
		else
			WorldMapFrame:SetMapID(areaID)
		end
		if DD then
			for i,v in pairs(DD) do
				if v then
					ClickDD(i);
				end
			end
		end
	end

	local IsDropDownShown = function(n)
		return DropDownList1:IsShown() and ({DropDownList1:GetPoint(1)})[2] == _G["WorldMap"..n.."DropDownLeft"];
	end

	--Class functions

	-- Map API

	class.GetPlayerMapPosition = function(unit)
		local unit = unit or "player";
		return C_Map.GetPlayerMapPosition(class.GetCurrentMapID(), unit);
	end

	--- Returns player positions for members in the party/raid.
	class.GetPartyPlayerPositions = function()
		local unitType = "party";
		if IsInRaid("player") then
			unitType = "raid";
		end

		local playerPositions = {};
		for i=1, GetNumGroupMembers() do
			table.insert(playerPositions, C_Map.GetPlayerMapPosition(class.GetCurrentMapID(), unitType .. i))
		end

		return playerPositions;
	end

	class.GetCurrentMapID = function()
		return C_Map.GetBestMapForUnit("player")
	end

	class.GetCurrentMapInfo = function()
		return C_Map.GetMapInfo(class.GetCurrentMapID());
	end

	class.SetMapSubLevel = function(levelIdx)
		local subMap = class.GetMapSubLevels()[levelIdx];
		WorldMapFrame:SetMapID(subMap.mapID);
	end

 	class.GetMapSubLevels = function()
		local mapGroup = C_Map.GetMapGroupID(class.GetCurrentMapID());
		if mapGroup == None then
			return {};
		end

		return C_Map.GetMapGroupMembersInfo(mapGroup);
	end

	class.GetNumMapSubLevels = function()
		local mapGroup = class.GetMapSubLevels();
		return table.getn(mapGroup);
	end

	--- Returns the index of the current map sub-level the player is in.
	class.GetCurrentMapDungeonLevel = function()
		local currentMapID = class.GetCurrentMapID();
		local mapGroup = class.GetMapSubLevels();
		-- Find map level that matches the current map.
		for i, map in pairs(mapGroup) do
			if map.mapID == currentMapID then
				return map.relativeHeightIndex;
			end
		end

		return 0;
	end

	--- Returns the ID of the current map continent.
	class.GetCurrentMapContinentID = function()
		local mapInfo = class.GetCurrentMapInfo();
		-- Walk up until we find a continent.
		while mapInfo.mapType ~= Enum.UIMapType.Continent do
			mapInfo = C_Map.GetMapInfo(mapInfo.parentMapID);
		end
		return mapInfo.mapID;
	end

	--- Returns the index of the current map within the continent, or 0 if this is a continent.
	class.GetCurrentMapIndex = function()
		local currentMapID = class.GetCurrentMapID();
		local continentID = class.GetCurrentMapContinentID();

		if currentMapID == continentID then
			return 0;
		end

		for i, map in pairs(C_Map.GetMapChildrenInfo(continentID)) do
			if map.mapID == currentMapID then
				return i;
			end
		end
	end

	--- Returns a list of continent info
	class.GetContinents = function()
		-- Get cosmos map
		local cosmosMap = class.GetCurrentMapInfo();
		while cosmosMap.mapType ~= Enum.UIMapType.Cosmic do
			cosmosMap = C_Map.GetMapInfo(cosmosMap.parentMapID);
		end

		return class.GetContinentsForMap(cosmosMap.mapID);
	end

	--- Returns a list of continent names (replacement for GetMapContinents)
	class.GetContinentNames = function()
		local continents = class.GetContinents();
		local continentNames = {};
		for i, continent in pairs(continents) do
			table.insert(continentNames, continent.name);
		end

		return continentNames;
	end

	--- Returns a list of all continents in a map.
	class.GetContinentsForMap = function(mapID)
		-- If map is a continent or is smaller than a continent, just return now.
		if C_Map.GetMapInfo(mapID).mapType >= Enum.UIMapType.Continent then
			return {};
		end;

		local continents = {};
		for i, childMap in pairs(C_Map.GetMapChildrenInfo(mapID)) do
			-- If it's a continent, add it to the list.
			if childMap.mapType == Enum.UIMapType.Continent then
				table.insert(continents, childMap);
			-- If it's larger than a continent, get it's own continents.
			elseif childMap.mapType < Enum.UIMapType.Continent then

				local childMapContinents = class.GetContinentsForMap(childMap.mapID);
				-- If there are multiple sub-maps, unpack it and insert the values.
				if type(childMapContinents) == "table" then
					for i, childMap in pairs(childMapContinents) do
						table.insert(continents, childMap)
					end
				else
					table.insert(continents, childMapContinents)
				end

			end
		end

		return continents;
	end

	--- Returns array of map info for zones in the specified continent.
	class.GetZonesForContinentByIdx = function(continentIdx)
		return C_Map.GetMapChildrenInfo(class.GetContinents()[continentIdx].mapID);
	end

	--- Zooms the map to the specified continentID/zoneID
	class.SetMapZoomByID = function(continentID, zoneID)
		local zoneID = zoneID or -1;

		-- Show continent if no zone index specified.
		if zoneID < 0 then
			WorldMapFrame:SetMapID(continentID);
			return;
		end

		-- Otherwise show zone.
		WorldMapFrame:SetMapID(zoneID);
	end

	--- Replacement for SetMapZoom.
	class.SetMapZoomByIdx = function(continentIdx, zoneIdx)
		local zoneIdx = zoneIdx or 0;
		local continent = class.GetContinents()[continentIdx];
		local zoneID = -1;

		if zoneIdx > 0 then
			zoneID = class.GetZonesForContinentByIdx(continentIdx)[zoneIdx].mapID;
		end

		class.SetMapZoomByID(continent.mapID, zoneID);
	end

	--- Returns info for the specified POI.
	class.GetMapBannerInfo = function(bannerID)
		local banners = C_Map.GetMapBannersForMap(class.GetCurrentMapID());
		for i, banner in pairs(banners) do
			if banner.areaPoiID == bannerID then
				return banner;
			end
		end
	end

	--- Returns number of map banners on the map.
	class.GetNumMapBanners = function()
		local banners = C_Map.GetMapBannersForMap(class.GetCurrentMapID());
		return table.getn(banners);
	end

	--- Returns map texture info for a texture in the current map at the specified index. Should replace GetMapOverlayInfo.
	class.GetMapTextureInfo = function(idx)
		local mapTextures = C_MapExplorationInfo.GetExploredMapTextures(class.GetCurrentMapID());

		if mapTextures == None or table.getn(mapTextures) < idx then
			return {};
		end

		return mapTextures[idx];
	end

	--- Returns number of map textures on the current map.
	class.GetNumMapTextures = function()
		local mapTextures = C_MapExplorationInfo.GetExploredMapTextures(class.GetCurrentMapID());

		if mapTextures == None then
			return 0;
		end

		return table.getn(mapTextures);
	end

	--

	class.GetCoor = function(unit,decimals)
		if not (unit) then unit = "player" end

		zoneIndex = class.GetCurrentMapIndex();
		continent = class.GetCurrentMapContinentID();
		areaID = class.GetCurrentMapID();
		dungeonLevel = class.GetCurrentMapDungeonLevel();

		-- check if drop down is shown
		DD = {
			Level = IsDropDownShown("Level"),
			Continent = IsDropDownShown("Continent"),
			Zone = IsDropDownShown("Zone"),
			ZoneMinimap = IsDropDownShown("ZoneMinimap"),
		}

		-- Move map
		SetMapToCurrentZone();
		currentContinent = continent;
		if currentContinent < 0 or currentContinent == 572 or currentContinent == 424 or currentContinent == 948 then -- 572 is draenor, 424 is pandaria, 948 is maelstrom
			ResetMap()
			return 0.0, 0.0, 0
		end

		class.SetMapZoomByID(currentContinent);

		local playerPos = class.GetPlayerMapPosition(unit);
		local x, y = playerPos.x, playerPos.y;
		local level;
		if floorLevel then
			level = floorLevel.GetCurrentFloorLevel();
		end
		--print("raw", x, y)
		if currentContinent == 101 then
			x = x * 2228.61382 -- scale for Outland
			y = y * 1485.74255
			ResetMap();
			return Round(x,decimals), Round(y,decimals), 2, level
		else  -- scale for Azeroth
			if IsMopClient() and not(useVersion1Coor) then
				x = x * 14545.7650
				y = y * 9697.1767
			elseif IsMopClient() and useVersion1Coor then
				x,y = ConvertMopToCata(x * 11698.9534, y * 7799.30229);
			else
				x = x * 11698.9534
				y = y * 7799.30229
			end
			ResetMap();

			return Round(x,decimals), Round(y,decimals), 1, level
		end
	end

	class.GetPlayerPos = function(decimals)
		local x, y, world, level = class.GetCoor("player",decimals);
		return {
			x = x,
			y = y,
			world = world,
			level = level,
		};
	end

	class.IsPosWithinRange = function(position, range)
		GHCheck("GHI_Position.IsPosWithinRange", { "Table", "Number" }, { position, range })
		local playerPos = class.GetPlayerPos();
		position.world = position.world or position.continent;

		if not (playerPos.world == position.world) then
			return false;
		end
		if not(playerPos.level == position.level) then
			return false;
		end

		local xDiff = position.x - playerPos.x;
		local yDiff = position.y - playerPos.y;
		return math.abs(math.sqrt(xDiff * xDiff + yDiff * yDiff)) <= range
	end

	class.OnNextMoveCallback = function(range,func,_repeat)
		local pos = class.GetPlayerPos(3);
		GHI_Timer(function()
			if pos then
				if not(class.IsPosWithinRange(pos,range)) then
					func();
					if _repeat then
						pos = class.GetPlayerPos(3);
					else
						pos = nil;
					end
				end
			end
		end,1);
	end

	class.GetDirectionAndDistance = function(otherPos)
		local playerPos = class.GetPlayerPos();

		if not(otherPos.world == playerPos.world) then
			return 99999999
		end

		local dx = otherPos.x - playerPos.x;
		local dy = otherPos.y - playerPos.y;

		local dist = sqrt(dx^2+dy^2);

		local degreeAngle
		if dx >= 0 and dy >= 0 then
			degreeAngle = atan(dy/dx)+90;
		elseif dy >= 0 then
			degreeAngle = atan(-dx/dy)+180;
		elseif dx >= 0 then
			degreeAngle = atan(dx/-dy);
		else
			degreeAngle = atan(-dy/-dx)+270;
		end

		local directionNames = {"north","northeast","east","southeast","south","southwest","west","northwest","north"};
		local directionName = directionNames[math.floor((degreeAngle+22.5)/45)+1];

		local c = tostring(math.floor(dist)):len()-1;
		local roundDist = dist/(10^c);

		local distanceText = string.format("around %s%s meter%s",math.floor(roundDist+0.5),strrep("0",c),( roundDist >= 2 and "s") or "");

		return degreeAngle,directionName,dist,distanceText;
	end

	return class
end
