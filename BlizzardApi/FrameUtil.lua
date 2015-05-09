﻿SetSelf = function(f)
	if not(type(f) == "table" and f.GetObjectType) then
        error("SetSelf called on a non frame value. " .. type(f));
    end

    if (f.__setSelf) then
        return f;
    end

    if (f.__csLuaWrapper) then
        return f.__csLuaWrapper;
    end

	local refencedObjects = {};
	local c = {};
	setmetatable(c, {
		__index = function(_, key)
			if key == "this" or key == "self" then
				return f;
			end
            if key == "__setSelf" then
                return true;
            end
			if type(f[key]) == "function" then
				return function(...)
					local args = {...};
					for i,arg in pairs(args) do
						if type(arg) == "table" and arg.GetObjectType and arg.self then
							args[i] = arg.self;
						end
					end
					
					local ret = {f[key](f, unpack(args))};
					for i = 1, #(ret) do
						if type(ret[i]) == "table" and ret[i].GetParent then
							ret[i] = SetSelf(ret[i]);
						end
					end
					
					if #(ret) <= 1 then
						return ret[1];
					end
					local tuple = {};
					for i = 1, #(ret) do
						tuple["Item"..i] = ret[i];
					end
					return tuple
				end
			elseif refencedObjects[key] then
				return refencedObjects[key];
			elseif type(f[key]) == "table" and f[key].GetObjectType then
				refencedObjects[key] = SetSelf(f[key]);
				return refencedObjects[key];
			else 
				return f[key];
			end
		end,
		__newindex = function(_, key, value)
			if type(value) == "table" and value.__setSelf then
				refencedObjects[key] = value;
				f[key] = value.self;
			else
				f[key] = value;
			end
		end,
	});
	f.__csLuaWrapper = c;

	return c;
end

BlizzardApi.FrameUtil = {
	FrameProvider = {
		CreateFrame = function(frameType, name, parent, inherits)
			if parent and parent.self then
				return SetSelf(CreateFrame(frameType, name, parent.self, inherits));
			end
			return SetSelf(CreateFrame(frameType, name, parent, inherits));
		end,
		GetFrameByGlobalName = function(name)
			local f = _G[name];
			if (type(f) == "table" and f.GetObjectType) then
				return SetSelf(f);
			end
			return f;
		end,
		GetMouseFocus = function()
			local f = GetMouseFocus();
			if f then
				return SetSelf(f);
			end
		end,
        AddSelfReferencesToNonCsFrameObject = function(obj)
            return SetSelf(obj);
        end,
	}
}