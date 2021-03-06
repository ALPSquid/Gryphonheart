﻿--
--
--				GHI_BookObj
--				GHI_BookObj.lua
--
--	Main class for book objects.
--	A book object should be implemented with the following:
--		- It should have the naming: GHI_BookObj_NameOfObject
--		- It should take two different constructor argument sets:
--			* height, width, arg1, arg2, arg3 etc
--			* bookObjClass, nil, arg1, arg2, arg3 etc
--		- It should implement .GetData, which returns arg1, arg2, arg3 etc
--		- It should implement .GetFrame
--
-- 		(c)2013 The Gryphonheart Team
--			All rights reserved
--
local class
function GHI_BookObjGenerator()
	if class then
		return class;
	end
	class = GHClass("GHI_BookObjGenerator");

	local deserializer = GHI_HtmlDeserializer();
	local sizeMap = {
		SIGNATURE = GHI_BookObj_Signature_GetSize,
	};
	local objMap = {
		SIGNATURE = GHI_BookObj_Signature,
	};
	
	class.GetSize = function(data)
		local tag = string.upper(data.tag);
		if sizeMap[tag] then
			return sizeMap[tag](data);
		end

		return 0, 0;
	end
	
	class.FromTextCode = function(code)
		GHCheck("GHI_BookObj.InitializeFromTextCode",{"string"},{code})
		-- Format: \124T:width:height:InnerHtml\124t

		local height, width, innerHtml = string.match(code,"^\124T:(%d*):(%d*):(.*)\124t$");
		assert(height and width and innerHtml,"Could not initialize from code. Object contains no size information. ");

		local data = deserializer.HtmlToTable(innerHtml);

		if data[1] and objMap[data[1].tag] then
			return objMap[data[1].tag](width, height, data)
		else
			return nil;
		end
	end
	
	return class;
end

