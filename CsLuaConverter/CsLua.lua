_M = { };
_M.MetaTypes = {
    TypeObject = "TypeObject",
    ClassObject = "ClassObject",
    NameSpace = "NameSpace",
    InteractionElement = "InteractionElement",
    StaticValues = "StaticValues",
    NameSpaceElement = "NameSpaceElement",
    InteractionElement = "InteractionElement",
    GenericMethod = "GenericMethod",
};
_M.__metaType = _M.MetaTypes.NameSpace

_M.NOT = setmetatable({}, { __add = function(_, value) 
    return not(value); 
end}); 

_M.AddRange = function(t1, t2)
    for i,v in pairs(t2) do
        table.insert(t1, v);
    end
end

local recursive = {};
local RecursiveProtectionLock = function(value)
    if (recursive[value] == true) then
        error("Unexpected recursion detected");
    end

    recursive[value] = true;
end;
_M.RPL = RecursiveProtectionLock;

local RecursiveProtectionRelease = function(value)
    recursive[value] = nil;
end;
_M.RPR = RecursiveProtectionRelease;

local primes = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83};
local GetSignatureHash = function(...)
    local types = {...};

    local value = 0;
    for i, type in ipairs(types) do
        
        if type.signatureHash then
            value = value + (primes[i] * type.signatureHash);
        elseif (type[1]) then
            value = value + (primes[i] * type[1].signatureHash);
        elseif type then
            error("Could not find signatureHash of given generic.");
        end
    end

    return value;
end
_M.SH = GetSignatureHash;

local function SetAddMeta(f)
    local mt = { __add = function(self, b) return f(self[1], b) end }
    return setmetatable({}, { __add = function(a, _) return setmetatable({ a }, mt) end })
end


_M.Add = SetAddMeta(function(a, b)
    assert(a or type(b) == "string", "Add called on a nil value (left).");
    assert(b or type(a) == "string", "Add called on a nil value (right).");
    if type(a) == "number" and type(b) == "number" then return a + b; end
    return tostring(a or "")..tostring(b or "");
end);

_M.ATN = function(fullNamespace, name, element)
    local namespace = {string.split(".", fullNamespace)};
    local t = _G;

    for _,v in ipairs(namespace) do
        if t[v] == nil then
            t[v] = {};
        end

        t = t[v];
    end

    t[name] = element;
end
 
--============= Argument Matching =============
local ScoreArguments = function(expectedTypes, argTypes, args, isParams)
    local sum = 0;
    local str = "";
    local foldOutArray = false;

    for i = 1, argTypes.num do
        local argType = argTypes[i];
        
        if (argType) then
            local expectedType = expectedTypes[i] or (isParams and expectedTypes[#(expectedTypes)]);
            if (expectedType == nil) then
                return nil, ", - Skipping candidate. Did not have enough expected types. Expected "..#(expectedTypes).." had: "..#(argTypes);
            end
        
            str = str .. ", " .. expectedType.ToString();

            local score = argType.GetMatchScore(expectedType, args[i]);

            if (isParams and i == #(expectedTypes) and i == argTypes.num) and argType.FullName == "System.Array" then
                local arrayGenricType = argType.GetGenericArguments()[0];
                local foldOutScore = arrayGenricType.GetMatchScore(expectedType, (args[i] % _M.DOT)[0]);
                if foldOutScore >= score then
                    score = foldOutScore;
                    foldOutArray = true;
                end
            end

            if (score == nil) then
                local additional = ""
                for j = i + 1, #(expectedTypes) do
                    additional = ", " .. expectedTypes[j].ToString();
                end

                return nil, str .. additional .. " - Skipping candidate. Arg ("..argType.ToString() .. ") did not match expected arg ("..expectedType.ToString()..")";
            end
            sum = sum + score;
        end
    end
    
    return sum, str, foldOutArray;
end

local SelectMatchingByTypes = function(list, args, name, methodGenerics)
    assert(type(list) == "table", "Expected a table as 1th argument to _M.AM, got "..type(list))
    assert(type(args) == "table", "Expected a table as 2th argument to _M.AM, got "..type(args))
    assert(type(name) == "string", "Expected a string as 3rd argument to _M.AM, got "..type(args))
    assert(methodGenerics == nil or type(methodGenerics) == "table", "Expected a table as 4th argument to _M.AM, got "..type(args))
    local argTypes = {num = #(args)};
    local argTypeStr = "";

    for i=1,#(args) do
        local arg = args[i];

        if not(arg == nil) then
            argTypes[i] = (arg%_M.DOT).GetType();
            argTypeStr = argTypeStr .. "," .. argTypes[i].FullName;
        else
            argTypeStr = argTypeStr .. ",null";
        end
    end
    
    local bestMatch, bestScore, bestFoldOutArray;
    local candidatesStr = "Candidates:";

    for _, element in ipairs(list) do
        local types = {};
        for _, t in ipairs(element.types) do 
            if type(t) == "string" then
                if methodGenerics and methodGenerics[element.generics[t]] then
                    table.insert(types, methodGenerics[element.generics[t]]);
                else
                    table.insert(types, System.Object.__typeof);
                end
            else
                table.insert(types, t);
            end
        end

        local score, scoreStr, foldOutArray = ScoreArguments(types, argTypes, args, element.isParams);
        candidatesStr = candidatesStr .. "\n  " .. scoreStr;

        if not(score == nil) and (not(bestScore) or score > bestScore) then
            bestMatch = element;
            bestScore = score;
            bestFoldOutArray = foldOutArray;
        end
    end
    
    if not(bestMatch) then
        error(string.format("No signature match found for method (%s).\nArgs: %s.\n%s", name, argTypeStr, candidatesStr));
    end
    
    return bestMatch, bestFoldOutArray;
end

_M.AM = SelectMatchingByTypes;

local GetAllMembers = function(members, implements)
    for _, implement in pairs(implements) do
        local _, interfaceMembers = implement.interactionElement.__meta({});

        for name, memberPair in pairs(interfaceMembers) do
            for _, member in pairs(memberPair) do
                _M.IM(members, name, member);
            end 
        end
    end
end
_M.GAM = GetAllMembers;

_M.CA = function(object, func)
    if not(object == nil) then
        return func(object);
    end
end
local defaultValues;

local initializeDefaultValues = function()
    if defaultValues then 
        return 
    end

    defaultValues = {
        [System.Int32.__typeof] = 0,
        [System.Boolean.__typeof] = false,
    };
end


local GetDefaultValue = function(type)
    initializeDefaultValues();
    if not(defaultValues[type] == nil) then
        return defaultValues[type];
    end

    if type.IsEnum then
        return type.InteractionElement.__default;
    end
end
_M.DV = GetDefaultValue;


local DotMeta = function(fIndex, fNewIndex, fCall) 
    return setmetatable({}, {
        __mod = function(obj, _) 
            return setmetatable({}, {
                __index = function(_, index)
                    return fIndex(obj,index);
                end,
                __newindex = function(_, index, value)
                    return fNewIndex(obj, index, value);
                end,
                __call = function(_,...)
                    return fCall(obj, ...);
                end
            })
        end
    });
end

local GetType = function(obj, index)
    if type(obj) == "table" then
        if type(obj.type) == "table" and obj.type.__metaType == _M.MetaTypes.TypeObject then
            return obj.type;
        end
        return Lua.NativeLuaTable.__typeof;
    elseif type(obj) == "string" then
        return System.String.__typeof;
    elseif type(obj) == "function" then
        return Lua.Function.__typeof;
    elseif type(obj) == "boolean" then
        return System.Boolean.__typeof;
    elseif type(obj) == "number" then
        if obj == math.floor(obj) then
            return System.Int.__typeof;
        end
        return System.Double.__typeof;
    else
        error("Could not get type of object "..type(obj)..". Attempting to address index "..tostring(index));
    end
end

_M.DOT_LVL = function(level, explicitLevel)
    return DotMeta(
        function(obj, index)  -- useage:  a%_M.dot%b
            assert(not(obj == nil), "Attempted to read index "..tostring(index).." on a nil value.");
            --assert(not(type(obj) == "table") or not(obj.__metaType == nil), "Attempted to read index "..tostring(index).." on a obj value with no meta type");

            if (type(obj) == "table" and (obj.__metaType ~= _M.MetaTypes.ClassObject and obj.__metaType ~= _M.MetaTypes.StaticValues and obj.__metaType ~= _M.MetaTypes.NameSpaceElement) and not(index == "GetType")) then
                if type(index) == "string" then
                    local newIndex, indexType, numGenerics, hash = string.split("_", index);

                    if (indexType == "M") then
                        index = newIndex;
                    end
                end

                return obj[index];
            end

            if (type(obj) == "table" and (obj.__metaType == _M.MetaTypes.NameSpaceElement)) then
                local indexer = obj.__index;
                if type(indexer) == "function" then
                    return indexer(obj, index, level); 
                end
                return obj[index];
            end

            local typeObject = GetType(obj, index);
            if (index == "GetType" or index == "GetType_M_0_0") then
                return function() return typeObject; end
            end

            return typeObject.interactionElement.__index(obj, index, level, explicitLevel); 
        end, 
        function(obj, index, value)
            assert(not(obj == nil), "Attempted to write index "..tostring(index).." to a nil value.");
            --assert(not(type(obj) == "table") or not(obj.__metaType == nil), "Attempted to write index "..tostring(index).." on a obj value with no meta type");

            if (type(obj) == "table" and (obj.__metaType == _M.MetaTypes.NameSpaceElement)) then
                return obj.__newindex(obj, index, value, level);
            end

            if (type(obj) == "table" and ((obj.__metaType == _M.MetaTypes.InteractionElement) or obj.__metaType == nil)) then
                obj[index] = value;
                return;
            end

            local typeObject = GetType(obj, index);
            return typeObject.interactionElement.__newindex(obj, index, value, level, explicitLevel); 
        end,
        function(obj, ...)
            if (type(obj) == "table" and (obj.__metaType == _M.MetaTypes.ClassObject)) then
                local typeObject = GetType(obj, "Invoke");
                return typeObject.interactionElement.__index(obj, "Invoke", level)(...); 
            end 

            assert(type(obj) == "function" or type(obj) == "table", "Attempted to invoke a "..type(obj).." value.");
            return obj(...);
        end
    );
end
_M.DOT = _M.DOT_LVL(nil);


local Enum = function(table, name, namespace, signatureHash)
    table.__typeof = System.Type(name, namespace, System.Object.__typeof, 0, nil, nil, table, 'Enum', signatureHash);

    return table;
end

_M.EN = Enum;

local Extensions = {};
local RegisterExtension = function(name, numGenerics, provider)
    Extensions[name] = Extensions[name] or {};
    Extensions[name][numGenerics] = Extensions[name][numGenerics] or {};
    table.insert(Extensions[name][numGenerics], provider);
end;
_M.RE = RegisterExtension;

local addRange = function(t, range)
    for _,v in pairs(range) do
        table.insert(t, v);
    end
end

local addMethodType = function(t)
    for _,v in pairs(t) do
        v.memberType = 'Method';
    end
    return t;
end

local GetExtensions = function(name, generics)
    local numGenerics = #(generics);
    local t = {};
    if type(Extensions[name]) == "table" then
        if type(Extensions[name][numGenerics]) == "table" then
            for _, provider in pairs(Extensions[name][numGenerics]) do
                addRange(t, addMethodType(provider(generics)));
            end
        end

        if type(Extensions[name]["#"]) == "table" then
            for _, provider in pairs(Extensions[name]["#"]) do
                addRange(t, addMethodType(provider(generics)));
            end
        end
    end
    return t;
end
_M.GE = GetExtensions;

local InvokeMethod = function(member, element, generics, args)
    if member.isParams then
        local i = #(args);

        local value = args[i];

        if not(value == nil) and ((value % _M.DOT).GetType() % _M.DOT).IsArray then
            args[i] = nil;
            for j = 0, (value % _M.DOT).Length - 1 do
                args[i+j] = (value % _M.DOT)[j];
            end
        end
    end 

    if member.generics then
        return member.func(element, member.generics, generics, unpack(args));
    else
        return member.func(element, unpack(args));
    end
end

local meta = {};
setmetatable(meta,{
    __index = function(_, index)
        if index == "__metaType" then
            return _M.MetaTypes.GenericMethod;
        end
    end
});

local GenericMethod = function(member, elementOrStaticValues, name)
    
    local t = {};

    setmetatable(t,{
        __index = function(_, generics)
            if meta[generics] then
                return meta[generics];
            end

            if generics == "type" then
                local actionGenerics = {};
                for _,v in pairs(member.types) do
                    table.insert(actionGenerics, v)
                end

                if (member.isParams == true) then
                    local i = #(actionGenerics)
                    actionGenerics[i] = System.Array[{actionGenerics[i]}].__typeof;
                end

                if not(member.returnType == nil) then
                    table.insert(actionGenerics, 1, member.returnType())
                    return System.Func[actionGenerics].__typeof;
                end

                return System.Action[actionGenerics].__typeof;
            end

            return function(...)
                return InvokeMethod(member, elementOrStaticValues, generics, {...});
            end
        end,
        __call = function(_, ...)
            return InvokeMethod(member, elementOrStaticValues, {}, {...});
        end,
    });

    return t;
end

_M.GM = GenericMethod;

local MethodGenerics = function(generics)
    local t = {};
    setmetatable(t, {
        __index = function(self, key)
            for i,v in pairs(generics) do
                if v == key then
                    return i;
                end
            end
        end
    });
    return t;
end

_M.MG = MethodGenerics;

--============= Interaction Element =============

local expectOneMember = function(members, key)
    assert(type(members) == "table", "A table of one member was expected for key '"..tostring(key).."'. Got no table.");
    assert(#(members) == 1, "A table of one member was expected for key '"..tostring(key).."'. Got "..#(members).." members");
end

local clone;
clone = function(t,dept)
    local t2 = {};
    for i,v in pairs(t) do
        if dept > 1 and type(v) == "table" then
            t2[i] = clone(v, dept-1);
        else
            t2[i] = v;
        end
    end
    return t2;
end

local where = function(list, evaluator)
    local t = {};
    for _, value in ipairs(list) do
        if evaluator(value) then
            table.insert(t, value);
        end
    end
    return t;
end

local joinTablesDistinct = function(tables)
    local res = {};

    for _,t in pairs(tables) do
        for _,v in pairs(t) do
            if not(tContains(res, v)) then
                table.insert(res, v);
            end
        end
    end

    return res;
end

local join = function(t1, t2)
    local t3 = {};
    for _,v in pairs(t1) do table.insert(t3, v); end
    for _,v in pairs(t2) do table.insert(t3, v); end
    return t3;
end

local memberTypeTranslation = {
    ["M"] = "Method",
    ["C"] = "Cstor",
};

local InteractionElement = function(metaProvider, generics, selfObj)
    if (type(metaProvider)=="table" and type(metaProvider.__typeof) == "table" and metaProvider.__typeof.IsEnum) then
        for i,v in pairs(metaProvider) do
            selfObj[i] = v;
        end

        return metaProvider;
    end

    local element = selfObj or { __metaType = _M.MetaTypes.InteractionElement };
    local staticValues = {__metaType = _M.MetaTypes.StaticValues};
    local extensions = {};

    _M.RPL(tostring(metaProvider));

    local catagory, typeObject, memberProvider, constructors, elementGenerator, implements, initialize, attributes = metaProvider(element, generics, staticValues);
    staticValues.type = typeObject;

    local cachedMembers = nil;

    local filterMethodSignature = function(key)
        local methodMetaIndex = type(key) == "string" and (string.find(key, "_M_") or string.find(key, "_C_")) or nil;
        if (methodMetaIndex) then
            local newKey = string.sub(key, 0, methodMetaIndex-1);
            local indexType, numGenerics, hash = string.split("_", string.sub(key, methodMetaIndex+1));
            return newKey, indexType, tonumber(numGenerics), tonumber(hash);
        end

        return key;
    end

    local getMembers = function(key, level, staticOnly, extensions, explicitLevel, getOrSetFilter)
        if not(cachedMembers) then
            cachedMembers = _M.RTEF(memberProvider);
        end

        local indexType, numGenerics, hash;
        key, indexType, numGenerics, hash = filterMethodSignature(key);

        local members =  where(cachedMembers[key] or {}, function(member)
            assert(member.memberType, "Member without member type in "..typeObject.FullName..". Key: "..key.." Level: "..tostring(member.level));
            local static = member.static;
            local public = member.scope == "Public";
            local protected = member.scope == "Protected";
            local memberLevel = member.level;
            local levelProvided = not(level == nil);
            local typeLevel = typeObject.level;
            local memberType = member.memberType;
            local isCstor = indexType == "C";

            return (not(staticOnly) or static) and
                (indexType == nil or memberType == memberTypeTranslation[indexType]) and
                (numGenerics == nil or numGenerics == member.numMethodGenerics) and
                (getOrSetFilter == nil or not(member.memberType == "Property") or (getOrSetFilter == "get" and member.get) or (getOrSetFilter == "set" and member.set)) and
                (hash == nil or hash == member.signatureHash) and
                (
                    (levelProvided and (explicitLevel) and memberLevel == level) or
                    (levelProvided and (explicitLevel) and memberLevel < level and (public or protected)) or
                    (levelProvided and not(explicitLevel) and memberLevel <= level) or
                    (not(explicitLevel) and not(isCstor) and (public or protected) and memberLevel <= typeLevel) or
                    (not(levelProvided) and not(public or protected) and memberLevel == typeLevel)
                );
        end);

        if #(members) <= 1 then
            return members;
        end

        local maxLevel = nil;
        for _,member in ipairs(members) do
            if not(maxLevel) or maxLevel < member.level then
                maxLevel = member.level;
            end
        end

        return where(members, function(member)
            return member.level == maxLevel;
        end);
    end

    local getExtensions = function()
        local ext = {_M.GE(typeObject.FullName, generics)};

        if not(typeObject.BaseType == nil) then
            table.insert(ext, typeObject.BaseType.InteractionElement.__getExtensions());
        end

        for _, imp in pairs(implements or {}) do
            table.insert(ext, imp.InteractionElement.__getExtensions());
        end
        return joinTablesDistinct(ext);
    end

    local extensions = nil;
    local getFittingExtensions = function(key)
        if (extensions == nil) then
            extensions = getExtensions();
        end

        local indexType, numGenerics, hash;
        key, indexType, numGenerics, hash = filterMethodSignature(key);

        return where(extensions, function(ext) 
            return ext.name == key and
                (numGenerics == nil or numGenerics == ext.numMethodGenerics) and
                (hash == nil or hash == ext.signatureHash); 
            end);
    end

    local matchesAll = function(t1, t2)
        if not(#(t1) == #(t2)) then
            return false;
        end

        for i,_ in ipairs(t1) do
            if not(t1[i] == t2[i]) then
                return false;
            end
        end

        return true;
    end

    local orderByLevel = function(members)
        local t = {};

        for _,member in ipairs(members) do
            local inserted = false;

            for i,v in ipairs(t) do
                if member.level > v.level then
                    table.insert(t, i, member);
                    inserted = true;
                    break;
                end
            end

            if (inserted == false) then
                table.insert(t, member);
            end
        end

        return t;
    end

    local filterOverrides = function(fittingMembers, level)
        if #(fittingMembers) == 1 then
            return fittingMembers;
        end
        
        fittingMembers = orderByLevel(fittingMembers);

        local result = {};

        for i,member in ipairs(fittingMembers) do
            local accepted = true;
            for j,otherMember in ipairs(fittingMembers) do
                if not(i == j) and
                    member.signatureHash == otherMember.signatureHash and
                    member.numMethodGenerics == otherMember.numMethodGenerics and
                    member.level < otherMember.level
                then
                    accepted = false;
                end
            end

            if accepted then
                table.insert(result, member);
            end
        end

        return result;
    end


    local index = function(self, key, level, explicitLevel)
        if (key == "__metaType") then return _M.MetaTypes.InteractionElement; end

        if (key == "__Initialize") and initialize then
            return function(values) initialize(self, values); return self; end
        end

        local fittingMembers = filterOverrides(getMembers(key, level, false, nil, explicitLevel, "get"), level or typeObject.level);

        if #(fittingMembers) == 0 then
            fittingMembers = getFittingExtensions(key);
        end

        if #(fittingMembers) == 0 then
            fittingMembers = getMembers("#", level, false, nil, explicitLevel); -- Look up indexers
        end

        if #(fittingMembers) == 0 and type(key) == "table" then
            return self[key];
        end

        if #(fittingMembers) == 0 then
            error("Could not find member. Key: "..tostring(key)..". Object: "..typeObject.FullName.." Level: "..tostring(level));
        end

        for i=1,#(fittingMembers) do
            assert(type(fittingMembers[i].memberType) == "string", "Missing member type on member. Object: "..typeObject.FullName..". Key: "..tostring(key).." Level: "..tostring(level).." Member #: "..tostring(i))
        end

        if (#(fittingMembers) > 1) then
            local nonMethodMembers = where(fittingMembers, function(m) return not(m.memberType == "Method"); end)
            if #(nonMethodMembers) > 0 then
                fittingMembers = nonMethodMembers;
            end
        end

        expectOneMember(fittingMembers, key);
        local member = fittingMembers[1];

        if member.memberType == "Field" or member.memberType == "AutoProperty" then
            if member.static then
                return staticValues[member.level][key];
            end

            return self[member.level][key];
        end

        if member.memberType == "Indexer" then
            if (member.get) then
                return member.get(self, key);
            end

            return self[member.level][key];
        end

        if member.memberType == "Method" then
            return _M.GM(member, self, key);
        end

        if member.memberType == "Property" then
            return member.get(self);
        end

        if member.memberType == "Cstor" then
            return function(...)
                member.func(self, ...);
            end
        end

        error("Could not handle member (get). Object: "..typeObject.FullName.." Type: "..tostring(fittingMembers[1].memberType)..". Key: "..tostring(key));
    end;

    local newIndex = function(self, key, value, level, explicitLevel)
        local fittingMembers = getMembers(key, level, false, nil, explicitLevel, "set");

        if #(fittingMembers) == 0 then
            fittingMembers = getMembers("#", level, false, nil, explicitLevel); -- Look up indexers
        end

        if #(fittingMembers) == 0 then
            error("Could not find member (set). Key: "..tostring(key)..". Object: "..typeObject.FullName.." Level: "..tostring(level));
        end

        if fittingMembers[1].memberType == "Field" or fittingMembers[1].memberType == "AutoProperty" then
            expectOneMember(fittingMembers, key);

            if (fittingMembers[1].static) then
                staticValues[fittingMembers[1].level][key] = value;
                return;
            end

            self[fittingMembers[1].level][key] = value;
            return
        end

        if fittingMembers[1].memberType == "Indexer" then
            expectOneMember(fittingMembers, "#");

            if (fittingMembers[1].set) then
                fittingMembers[1].set(self, key, value);
                return
            end

            self[fittingMembers[1].level][key] = value;
            return
        end

        if fittingMembers[1].memberType == "Property" then
            expectOneMember(fittingMembers, key);
            fittingMembers[1].set(self, value);
            return 
        end

        error("Could not handle member (set). Object: "..typeObject.FullName.." Type: "..tostring(fittingMembers[1].memberType)..". Key: "..tostring(key)..". Num members: "..#(fittingMembers));
    end

    local meta = {
        __typeof = typeObject,
        __is = function(value) return typeObject.IsInstanceOfType(value); end,
        __as = function(value) return typeObject.IsInstanceOfType(value) and value or nil; end,
        __meta = function(inheritingStaticValues) 
            for i = 1, typeObject.level do
                inheritingStaticValues[i] = staticValues[i];
            end

            if not(cachedMembers) then
                cachedMembers = _M.RTEF(memberProvider);
            end

            return typeObject, clone(cachedMembers, 2), clone(constructors or {},2), elementGenerator, clone(implements or {},1), initialize, attributes; 
        end,
        __index = index,
        __newindex = newIndex,
        __metaType = _M.MetaTypes.InteractionElement,
        __extend = function(extensions) 
            for _,v in ipairs(extensions) do
                if not(extendedMethods[v.name]) then
                    extendedMethods[v.name] = {};
                end
                v.level = typeObject.level;
                table.insert(extendedMethods[v.name], v);
            end
        end,
        __getExtensions = getExtensions,
    };

    
    setmetatable(element, { 
        __index = function(_, key)
            if not(meta[key] == nil) then 
                return meta[key];
            end

            if (key == "type") then
                return nil;
            end

            if not(catagory == "Class") then
                if (key == "GetType") then
                    return nil;
                end

                error(string.format("Could not find key on a non class element. Category: %s. Key: %s.", tostring(catagory), tostring(key)));
            end

            local fittingMembers = getMembers(key, typeObject.level, true, nil, explicitLevel);

            if #(fittingMembers) == 0 then
                error("Could not find static member. Key: "..tostring(key)..". Object: "..typeObject.FullName);
            end

            expectOneMember(fittingMembers, key);

            local member = fittingMembers[1];

            if (member.memberType == "Method") then
                return _M.GM(member, staticValues, key);
            end

            if member.memberType == "Property" then
                return member.get(staticValues);
            end

            if member.memberType == "AutoProperty" then
                return staticValues[member.level][key];
            end

            if member.memberType == "Cstor" then
                local classElement = elementGenerator();
                return function(...)
                    member.func(classElement, ...);
                    return classElement;
                end;
            end

            assert(member.memberType == "Field", "Expected field member for key "..tostring(key)..". Got "..tostring(member.memberType)..". Object: "..typeObject.FullName..".");
            return staticValues[member.level][key];
        end,
        __newindex = function(_, key, value)
            if not(catagory == "Class") then
                error(string.format("Could not set key on a non class element. Category: %s. Key: %s.", tostring(catagory), tostring(key)));
            end

            local fittingMembers = getMembers(key, nil, true, nil, explicitLevel);
            expectOneMember(fittingMembers, key);
            local member = fittingMembers[1];

            if member.memberType == "Property" then
                member.set(staticValues, value);
                return 
            end

            if member.memberType == "AutoProperty" then
                staticValues[member.level][key] = value;
                return;
            end

            assert(member.memberType == "Field", "Expected field member for key "..tostring(key)..". Got "..tostring(member.memberType)..". Object: "..typeObject.FullName..".");
            staticValues[member.level][key] = value;
        end, --[[
        __call = function(_, ...)
            
            
            assert(type(constructors)=="table" and #(constructors) > 0, "Class did not provide any constructors. Type: "..typeObject.FullName);
            -- Generate the base class element from constructor.GenerateBaseClass
            local classElement = elementGenerator();
            -- find the constructor fitting the arguments.
            local constructor, foldOutLast = _M.AM(constructors, {...}, "Constructor");
            -- Call the constructor
            constructor.func(classElement, ...);

            return classElement; 
        end, --]]
    });

    _M.RPR(tostring(metaProvider));

    return element;
end

_M.IE = InteractionElement;

local InsertMember = function(members, key, member)
    if not(members[key]) then
        members[key] = {};
    end

    if member.memberType == 'Method' and member.signatureHash == nil then 
        error("No signature hash for member ".. key); 
    end

    table.insert(members[key], member);
end
_M.IM = InsertMember;

local BaseCstor = function(classElement, baseConstructors, ...)
    local constructor = _M.AM(baseConstructors, {...}, "Base constructor");
    constructor.func(classElement, ...);
end
_M.BC = BaseCstor;

local ReturnTableOrExecuteFunction = function(t)
    return type(t) == "table" and t or t();
end
_M.RTEF = ReturnTableOrExecuteFunction;

local lambda = function(f, retArg, ...)
    
    if (retArg == nil) then
        return System.Action[{...}]._C_0_0(f);
    end

    return System.Func[{..., retArg}](f);
end

_M.LB = lambda;

--============= Namespace Element =============

local getHashOfGenerics = function(generics)
    local hash = 0;
    for i,v in ipairs(generics) do
        hash = hash + (primes[i]*v.GetHashCode());
    end
    return hash;
end

local isGenericsTable = function(t)
    if not(type(t) == "table") then
        return false;
    end
    
    for i,v in ipairs(t) do
        if (not(type(v) == "table") or not(System.Type.__is(v))) then
            return false;
        end
    end
    return true;
end

local NamespaceElement = function(metaProviders)
    local interactionElements = {};
    
    local getInteractionElement = function(generics)
        generics = generics or {};
        local hash = getHashOfGenerics(generics);
        if not(interactionElements[hash]) then
            assert(metaProviders[#(generics)] or metaProviders["#"], string.format("Could not find meta provider fitting number of generics: %s or '#'", #(generics)));

            local selfObj = { __metaType = _M.MetaTypes.InteractionElement };
            interactionElements[hash] = selfObj;
            _M.IE(metaProviders[#(generics)] or metaProviders["#"], generics, selfObj);
        end
        
        return interactionElements[hash];
    end

    local element = {};
    setmetatable(element, { 
        __index = function(_, key)
            if key == "__metaType" then
                return _M.MetaTypes.NameSpaceElement;
            end

            if not(isGenericsTable(key)) then
                return getInteractionElement()[key];
            end
            return getInteractionElement(key);
        end,
        __newindex = function(_, key, value)
            getInteractionElement()[key] = value;
        end,
    });

    return element;
end

_M.NE = NamespaceElement;

_M.Throw = function(exception)
    if not(System.Exception.__is(exception)) then
        error("Non exception thrown.");
    end

    _M._CurrentException = exception;
    error((exception % _M.DOT).ToString_M_0_0(), 2);
end

_M.Try = function(try, catch, finally)
    _M._CurrentException = nil;
    local success, err = pcall(try)
    local exception = _M._CurrentException;
    _M._CurrentException = nil;

    if not(success) then
        exception = exception or System.Exception._C_0_8736("Lua error:\n" .. (err or "nil"));
        
        local matchFound = false;
        for _, catchCase in ipairs(catch or {}) do
            if catchCase.type == nil or catchCase.type.interactionElement.__is(exception) then
                catchCase.func(exception)
                matchFound = true;
                break;
            end
        end

        if (matchFound == false) then -- rethrow
            if finally then
                finally();
            end

            __CurrentException = exception;
            error(err, 2);
        end
    end

    if finally then
        finally();
    end
end
System = { __metaType = _M.MetaTypes.NameSpace };

System.Action = _M.NE({["#"] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('Action','System',baseTypeObject,#(generics),generics,nil,interactionElement,'Class', 4393);
    
    local members = {
        
    };

    _M.IM(members,'Invoke',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = generics,
        numMethodGenerics = 0,
        signatureHash = _M.SH(unpack(generics)),
        func = function(element,...)
            (element[typeObject.level].innerAction % _M.DOT)(...);
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*Lua.Function.__typeof.signatureHash,
        scope = 'Public',
        func = function(element, innerAction)
            element[typeObject.level].innerAction = innerAction;
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*typeObject.signatureHash,
        scope = 'Public',
        func = function(element, innerAction)
            element[typeObject.level].innerAction = innerAction[typeObject.level].innerAction;
        end,
    });

    --[[
    local constructors = {
        {
            types = {typeObject},
            func = function(element, innerAction) 
                element[typeObject.level].innerAction = innerAction[typeObject.level].innerAction;
            end,
        },
        {
            types = {Lua.Function.__typeof},
            func = function(element, innerAction) 
                element[typeObject.level].innerAction = innerAction;
            end,
        }
    };--]]
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.Activator = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members, baseConstructors = System.Object.__meta(staticValues);
    local typeObject = System.Type('Activator','System',baseTypeObject,0,nil,nil,interactionElement,'Class',0);

    _M.IM(members, 'CreateInstance', {
        level = typeObject.Level,
        memberType = 'Method',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*1798,
        scope = 'Public',
        func = function(element, typeObject)
            return typeObject.interactionElement._C_0_0();
        end,
    });

    _M.IM(members, 'CreateInstance', {
        level = typeObject.Level,
        memberType = 'Method',
        static = true,
        numMethodGenerics = 1,
        signatureHash = 0,
        scope = 'Public',
        generics = {['T'] = 1};
        func = function(element, methodGenericsMapping, methodGenerics)
            return methodGenerics[1].interactionElement._C_0_0();
        end,
    });

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            [3] = {},
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        };  
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.ArgumentOutOfRangeException = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members, baseConstructors = System.Exception.__meta(staticValues);
    local typeObject = System.Type('ArgumentOutOfRangeException','System',baseTypeObject,0,nil,nil,interactionElement,'Class',131151);

    --[[
    local constructors = {
        {
            types = {},
            func = function(element) 
                _M.BC(element, baseConstructors, "Index was out of range. Must be non-negative and less than the size of the collection.\r\nParameter name: index");
            end,
        }
    }; --]]

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
            (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_8736("Index was out of range. Must be non-negative and less than the size of the collection.\r\nParameter name: index");
        end,
    });

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            [3] = {},
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        };  
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.Array = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local implements = {
        System.Collections.IList.__typeof,
        System.Collections.ICollection.__typeof,
        System.Collections.IEnumerable.__typeof,
    };

    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('Array','System', baseTypeObject,#(generics),generics,implements,interactionElement,'Class',3052);

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
        end,
    });

    local initialize = function(self, values)
    end;
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator, nil, initialize;
end,
[1] = function(interactionElement, generics, staticValues)
    local implements = {
        System.Collections.IList.__typeof,
        System.Collections.ICollection.__typeof,
        System.Collections.IEnumerable.__typeof,
        System.Collections.Generic.IList[generics].__typeof,
        System.Collections.Generic.ICollection[generics].__typeof,
        System.Collections.Generic.IEnumerable[generics].__typeof,
        System.Collections.Generic.IReadOnlyList[generics].__typeof,
        System.Collections.Generic.IReadOnlyCollection[generics].__typeof,
    };
    
    local baseTypeObject, members = System.Array.__meta(staticValues);
    local typeObject = System.Type('Array','System', baseTypeObject,#(generics),generics,implements,interactionElement,'Class',3052, (generics[1] % _M.DOT).FullName .. '[]');

    local size;

    local len = function(element)
        return element[typeObject.level].size or ((element[typeObject.level][0] and 1 or 0) + #(element[typeObject.level]));
    end

    _M.IM(members,'GetEnumerator',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = {},
        numMethodGenerics = 0,
        signatureHash = 0,
        func = function(element)
            return function(_, prevKey) 
                local key;
                if prevKey == nil then
                    key = 0;
                else
                    key = prevKey + 1;
                end

                if key < len(element) then
                    return key, element[typeObject.level][key];
                end
                return nil, nil;
            end;
        end,
    });

    _M.IM(members,'Length',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        types = {},
        get = function(element)
            return len(element);
        end,
    });

    _M.IM(members,'#',{
        level = typeObject.Level,
        memberType = 'Indexer',
        scope = 'Public',
        --types = {generics[1]},
        get = function(element, key)
            assert(type(key) == "number", "Attempted to address array with a non number index: "..tostring(key));
            return element[typeObject.Level][key];
        end,
        set = function(element, key, value)
            element[typeObject.Level][key] = value;
        end
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2112,
        scope = 'Public',
        func = function(element, size)
            element[typeObject.level].size = size;
        end,
    });

    local initialize = function(self, values)
        for i,v in pairs(values) do
            self[typeObject.Level][i] = v;
        end
    end;
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            [3] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator, implements, initialize;
end})

local areAllOfType = function(objs, type)
    for _,v in pairs(objs) do
        if not(type.IsInstanceOfType(v)) then
            return false;
        end
    end
    return true;
end

local getHighestCommonType = function(objs)
    local type;
    for i,v in pairs(objs) do
        type = (v %_M.DOT).GetType();
        break;
    end

    while (type) do
        if areAllOfType(objs, type) then
            return type;
        end
        type = type.BaseType;
    end

    error("No common type found");
end

ImplicitArray = function(t)
    local type = getHighestCommonType(t);
    return (System.Array[{type}]() % _M.DOT).__Initialize(t);
end
System.Boolean = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('Boolean','System',baseTypeObject,0,nil,nil,interactionElement,'Class',6018);

    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.Double = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('Double','System',baseTypeObject,0,nil,nil,interactionElement,'Class',4241);

    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.Enum = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('Enum','System',baseTypeObject,0,nil,nil,interactionElement,'Class',1816);

    _M.IM(members,'Parse',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 16700,
        types = {System.Type.__typeof, System.String.__typeof},
        func = function(staticValues, typeObj, str)
            for _,v in pairs(typeObj.interactionElement) do
                if type(v) == "string" and string.lower(str) == string.lower(v) then
                    return v;
                end
            end
            return nil;
        end,
    });

    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})

System.Exception = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('Exception','System',baseTypeObject,0,nil,nil,interactionElement,'Class',10864);
    local level = 2;

    _M.IM(members,'Message',{
        level = typeObject.Level,
        memberType = 'AutoProperty',
        scope = 'Public',
    });

    _M.IM(members,'ToString',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = {typeObject},
        numMethodGenerics = 0,
        signatureHash = 0,
        override = true,
        func = function(element)
            return (element % _M.DOT).Message;
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
            (element %_M.DOT).Message = "";
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 8736,
        scope = 'Public',
        func = function(element, msg)
            (element % _M.DOT_LVL(typeObject.Level)).Message = msg;
        end,
    });

    --[[
    local constructors = {
        {
            types = {},
            func = function(element)
                (element %_M.DOT).Message = "";
            end,
        },
        {
            types = {System.String.__typeof},
            func = function(element, msg)
                (element %_M.DOT).Message = msg;
            end,
        }
    };
    -- ]]

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.Func = _M.NE({["#"] = function(interactionElement, generics, staticValues)
    local typeObject = System.Type('Func','System',System.Object.__typeof,#(generics),generics,nil,interactionElement,'Class',1734);
    local level = 2;
    local members = {
        
    };

    local inputGenerics = {};
    for i = 1, #(generics)-1 do
        table.insert(inputGenerics, generics[i]);
    end

    _M.IM(members,'Invoke',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = inputGenerics,
        numMethodGenerics = 0,
        signatureHash = 0, -- TODO: Fix hash
        func = function(element,...)
            return (element[typeObject.level].innerAction % _M.DOT)(...);
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*typeObject.signatureHash,
        scope = 'Public',
        func = function(element, innerAction)
            element[typeObject.level].innerAction = innerAction[typeObject.level].innerAction;
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*Lua.Function.__typeof.signatureHash,
        scope = 'Public',
        func = function(element, innerAction)
            element[typeObject.level].innerAction = innerAction;
        end,
    });

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.Guid = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members, baseConstructors = System.Object.__meta(staticValues);
    local typeObject = System.Type('Guid','System',baseTypeObject,0,nil,nil,interactionElement,'Class',1718);

    local toHex = function(value, num)
        local value = string.gsub(string.format("%"..num.."x", value)," ","0");
        return value;
    end

    local randomHexValue = function(size)
        return toHex(math.random(16^size), size);
    end

    _M.IM(members, 'NewGuid', {
        level = typeObject.Level,
        memberType = 'Method',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
            local value = randomHexValue(4).. randomHexValue(4).."-".. randomHexValue(4).."-".. randomHexValue(4).."-".. randomHexValue(4).."-".. randomHexValue(6).. randomHexValue(6);

            return System.Guid._C_0_8736(value);
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*4368,
        scope = 'Public',
        func = function(element, value)
            element[2].value = value;
        end,
    });

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        };  
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.Int = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Double.__meta(staticValues);
    local typeObject = System.Type('Int','System',baseTypeObject,0,nil,nil,interactionElement,'Class',1056);

    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return 0; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})

System.Int32 = _M.NE({["#"] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Double.__meta({});
    local typeObject = System.Type('Int32','System',baseTypeObject,0,nil,nil,interactionElement,'Class', 1963);
    members[typeObject.level] = {};

    _M.IM(members,'Parse',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = true,
        types = {System.Object.__typeof},
        numMethodGenerics = 0,
        signatureHash = 8572,
        func = function(_, value)
            return math.floor(tonumber(value));
        end,
    });

    _M.IM(members,'Parse',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = true,
        types = {System.String.__typeof},
        numMethodGenerics = 0,
        signatureHash = 8736    ,
        func = function(_, value)
            return math.floor(tonumber(value));
        end,
    });

    _M.IM(members,'Equals',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = {typeObject},
        numMethodGenerics = 0,
        signatureHash = 3926,
        func = function(element, obj)
            return element == obj;
        end,
    });

    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return 0; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.Int = System.Int32;

System.Int64 = _M.NE({["#"] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Int32.__meta({});
    local typeObject = System.Type('Int64','System',baseTypeObject,0,nil,nil,interactionElement,'Class',2006);
    members[typeObject.level] = {};

    _M.IM(members,'Parse',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = true,
        types = {System.Object.__typeof},
        numMethodGenerics = 0,
        signatureHash = 8572,
        func = function(_, value)
            return math.floor(tonumber(value));
        end,
    });

    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return 0; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.Long = System.Int64;
System.InvalidOperationException = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members, baseConstructors = System.Exception.__meta(staticValues);
    local typeObject = System.Type('InvalidOperationException','System',baseTypeObject,0,nil,nil,interactionElement,'Class',112244); -- TODO: Fix type hash

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 8736,
        scope = 'Public',
        func = function(element, msg)
            (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_8736(msg);
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
            (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_8736("Operation is not valid due to the current state of the object.");
        end,
    });

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            [3] = {},
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        };  
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.NotImplementedException = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members, baseConstructors = System.Exception.__meta(staticValues);
    local typeObject = System.Type('NotImplementedException','System',baseTypeObject,0,nil,nil,interactionElement,'Class',92478); -- TODO: Fix type hash

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
            (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_8736("The method or operation is not implemented.");
        end,
    });

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            [3] = {},
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        };  
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.Object = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local typeObject = System.Type('Object','System',nil,0,nil,nil,interactionElement,'Class',4286);
    local members = {
        {
            -- Note: GetType is implemented as a shortcut inside DOT, to avoid additional looks through AM.
        },
    };

    _M.IM(members,'Equals',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = {typeObject},
        numMethodGenerics = 0,
        signatureHash = 8572,
        func = function(element, obj)
            return element == obj;
        end,
    });

    _M.IM(members,'ToString',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = {},
        numMethodGenerics = 0,
        signatureHash = 0,
        func = function(element)
            if type(element) == "table" then
                return ((element %_M.DOT).GetType() %_M).FullName;
            elseif type(element) == "boolean" then
                return element and "True" or "False";
            end

            return tostring(element);
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
        end,
    });

    local elementGenerator = function() 
        return {
            [1] = {},
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end

    return "Class", typeObject, members, constructors, elementGenerator;
end})
System.Predicate = _M.NE({["#"] = function(interactionElement, generics, staticValues)
    local typeObject = System.Type('Predicate','System',System.Object.__typeof,#(generics),generics,nil,interactionElement,'Class',10325);
    local level = 2;
    local members = {
        
    };

    _M.IM(members,'Invoke',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = generics,
        numMethodGenerics = 0,
        signatureHash = _M.SH(unpack(generics)),
        returnType = System.Boolean.__typeof,
        func = function(element,...)
            return (element[typeObject.level].innerAction % _M.DOT)(...);
        end,
    });

    --[[
    local constructors = {
        {
            types = {typeObject},
            func = function(element, innerAction) 
                element[typeObject.level].innerAction = innerAction;
            end,
        },
        {
            types = {Lua.Function.__typeof},
            func = function(element, innerAction) 
                element[typeObject.level].innerAction = innerAction;
            end,
        }
    }; --]]

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*typeObject.signatureHash,
        scope = 'Public',
        func = function(element, innerAction)
            element[typeObject.level].innerAction = innerAction;
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*Lua.Function.__typeof.signatureHash,
        scope = 'Public',
        func = function(element, innerAction)
            element[typeObject.level].innerAction = innerAction;
        end,
    });

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.Single = _M.NE({[0] = function(interactionElement, generics, staticValues) -- AKA float
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('Single','System',baseTypeObject,0,nil,nil,interactionElement,'Class',4253);

    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.String = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('String','System',baseTypeObject,0,nil,nil,interactionElement,'Class',4368);

    -- String compare
    local compare = function(strA, indexA, strB, indexB, length)
        for i=1,length do
            local ca = string.char(strA, indexA+i);
            local cb = string.char(strB, indexB+i);
            
            if ca > cb then
                return 1;
            elseif cb > ba then
                return -1;
            end
        end
        return 0;
    end
    
    _M.IM(members,'Compare',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 21840, -- String, String
        func = function(element, strA, strB)
            return compare(strA, 0, strB, 0, math.max(string.len(strA), string.len(strB)));
        end,
    });

    _M.IM(members,'Split',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = {typeObject},
        numMethodGenerics = 0,
        signatureHash = 10374,
        func = function(element, delimiter)
            local t = {string.split(delimiter, element)};
            t[0] = t[1];
            table.remove(t,1);
            return (System.Array[{typeObject}]._C_0_0()%_M.DOT).__Initialize(t);
        end,
    });

    _M.IM(members,'Contains',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = {typeObject},
        numMethodGenerics = 0,
        signatureHash = 8736,
        func = function(element, str)
            return not(string.find(element, str) == nil)
        end,
    });

    _M.IM(members,'Length',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        types = {},
        numMethodGenerics = 0,
        get = function(element)
            return string.len(element);
        end,
    });

    _M.IM(members,'IsNullOrEmpty',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = true,
        types = {typeObject},
        numMethodGenerics = 0,
        signatureHash = 8736,
        func = function(_, str)
            return str == nil or str == "";
        end,
    });

    _M.IM(members,'Equals',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = {typeObject},
        numMethodGenerics = 0,
        signatureHash = 8736,
        func = function(element, obj)
            return element == obj;
        end,
    });

    _M.IM(members,'Empty',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        types = {typeObject},
        static = true,
        get = function(element)
            return "";
        end,
    });
    
    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return "";
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
_M.ATN('System','ArgumentException', _M.NE({
    [0] = function(interactionElement, generics, staticValues)
        local genericsMapping = {};
        local typeObject = System.Type('ArgumentException','System', nil, 0, generics, nil, interactionElement, 'Class', 47153);
        local baseTypeObject, getBaseMembers, baseConstructors, baseElementGenerator, implements, baseInitialize = System.SystemException.__meta(staticValues);
        typeObject.baseType = baseTypeObject;
        typeObject.level = baseTypeObject.level + 1;
        typeObject.implements = implements;
        local elementGenerator = function()
            local element = baseElementGenerator();
            element.type = typeObject;
            element[typeObject.Level] = {
                Message = _M.DV(System.String.__typeof),
                ParamName = _M.DV(System.String.__typeof),
                m_paramName = _M.DV(System.String.__typeof),
            };
            return element;
        end
        staticValues[typeObject.Level] = {
        };
        local initialize = function(element, values)
            if baseInitialize then baseInitialize(element, values); end
            if not(values.Message == nil) then element[typeObject.Level].Message = values.Message; end
            if not(values.ParamName == nil) then element[typeObject.Level].ParamName = values.ParamName; end
            if not(values.m_paramName == nil) then element[typeObject.Level].m_paramName = values.m_paramName; end
        end
        local getMembers = function()
            local members = _M.RTEF(getBaseMembers);
            _M.IM(members, 'm_paramName', {
                level = typeObject.Level,
                memberType = 'Field',
                scope = 'Private',
                static = false,
            });
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                scope = 'Public',
                func = function(element)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_8736("Value does not fall within the expected range.");
                end,
            });
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8736,
                scope = 'Public',
                func = function(element, message)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_8736(message);
                end,
            });
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 41328,
                scope = 'Public',
                func = function(element, message, innerException)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_41328(message, innerException);
                end,
            });
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 76160,
                scope = 'Public',
                func = function(element, message, paramName, innerException)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_41328(message, innerException);
                    (element % _M.DOT_LVL(typeObject.Level)).m_paramName = paramName;
                end,
            });
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 21840,
                scope = 'Public',
                func = function(element, message, paramName)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_8736(message);
                    (element % _M.DOT_LVL(typeObject.Level)).m_paramName = paramName;
                end,
            });
            _M.IM(members, 'Message',{
                level = typeObject.Level,
                memberType = 'Property',
                scope = 'Public',
                static = false,
                returnType = System.String.__typeof;
                get = function(element)
                    local s = (element % _M.DOT_LVL(typeObject.Level - 1, true)).Message;
                    if (not(((System.String % _M.DOT).IsNullOrEmpty_M_0_8736 % _M.DOT)((element % _M.DOT_LVL(typeObject.Level)).m_paramName))) then
                        local resourcestring = "Parameter name: " +_M.Add+ (element % _M.DOT_LVL(typeObject.Level)).m_paramName;
                        return s +_M.Add+ "\n" +_M.Add+ resourcestring;
                    else
                    return s;
                    end
                end,
            });
            _M.IM(members, 'ParamName',{
                level = typeObject.Level,
                memberType = 'Property',
                scope = 'Public',
                static = false,
                returnType = System.String.__typeof;
                get = function(element)
                    return (element % _M.DOT_LVL(typeObject.Level)).m_paramName;
                end,
            });
            return members;
        end
        return 'Class', typeObject, getMembers, constructors, elementGenerator, nil, initialize;
    end,
}));
_M.ATN('System','ArgumentNullException', _M.NE({
    [0] = function(interactionElement, generics, staticValues)
        local genericsMapping = {};
        local typeObject = System.Type('ArgumentNullException','System', nil, 0, generics, nil, interactionElement, 'Class', 75548);
        local baseTypeObject, getBaseMembers, baseConstructors, baseElementGenerator, implements, baseInitialize = System.ArgumentException.__meta(staticValues);
        typeObject.baseType = baseTypeObject;
        typeObject.level = baseTypeObject.level + 1;
        typeObject.implements = implements;
        local elementGenerator = function()
            local element = baseElementGenerator();
            element.type = typeObject;
            element[typeObject.Level] = {
            };
            return element;
        end
        staticValues[typeObject.Level] = {
        };
        local initialize = function(element, values)
            if baseInitialize then baseInitialize(element, values); end
        end
        local getMembers = function()
            local members = _M.RTEF(getBaseMembers);
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                scope = 'Public',
                func = function(element)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_8736("Value cannot be null.");
                end,
            });
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8736,
                scope = 'Public',
                func = function(element, paramName)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_21840("Value cannot be null.", paramName);
                end,
            });
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 41328,
                scope = 'Public',
                func = function(element, paramName, innerException)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_41328(paramName, innerException);
                end,
            });
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 21840,
                scope = 'Public',
                func = function(element, paramName, message)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_21840(paramName, message);
                end,
            });
            return members;
        end
        return 'Class', typeObject, getMembers, constructors, elementGenerator, nil, initialize;
    end,
}));
_M.ATN('System','Environment', _M.NE({
    [0] = function(interactionElement, generics, staticValues)
        local genericsMapping = {};
        local typeObject = System.Type('Environment','System', nil, 0, generics, nil, interactionElement, 'Class', 17540);
        local baseTypeObject, getBaseMembers, baseConstructors, baseElementGenerator, implements, baseInitialize = System.Object.__meta(staticValues);
        typeObject.baseType = baseTypeObject;
        typeObject.level = baseTypeObject.level + 1;
        typeObject.implements = implements;
        local elementGenerator = function()
            local element = baseElementGenerator();
            element.type = typeObject;
            element[typeObject.Level] = {
            };
            return element;
        end
        staticValues[typeObject.Level] = {
            NewLine = _M.DV(System.String.__typeof),
        };
        local initialize = function(element, values)
            if baseInitialize then baseInitialize(element, values); end
            if not(values.NewLine == nil) then element[typeObject.Level].NewLine = values.NewLine; end
        end
        local getMembers = function()
            local members = _M.RTEF(getBaseMembers);
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                scope = 'Public',
                func = function(element)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_0();
                end,
            });
            _M.IM(members, 'NewLine',{
                level = typeObject.Level,
                memberType = 'Property',
                scope = 'Public',
                static = true,
                returnType = System.String.__typeof;
                get = function(element)
                    return "\n";
                end,
            });
            return members;
        end
        return 'Class', typeObject, getMembers, constructors, elementGenerator, nil, initialize;
    end,
}));
_M.ATN('System','IDisposable', _M.NE({
    [0] = function(interactionElement, generics, staticValues)
        local genericsMapping = {};
        local typeObject = System.Type('IDisposable','System', nil, 0, generics, nil, interactionElement, 'Interface',16670);
        local implements = {
        };
        typeObject.implements = implements;
        local getMembers = function()
            local members = {};
            _M.GAM(members, implements);
            _M.IM(members, 'Dispose', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = false,
                numMethodGenerics = 0,
                signatureHash = 0,
            });
            return members;
        end
        return 'Interface', typeObject, getMembers, nil, nil, nil, nil, attributes;
    end,
}));
_M.ATN('System','SystemException', _M.NE({
    [0] = function(interactionElement, generics, staticValues)
        local genericsMapping = {};
        local typeObject = System.Type('SystemException','System', nil, 0, generics, nil, interactionElement, 'Class', 35115);
        local baseTypeObject, getBaseMembers, baseConstructors, baseElementGenerator, implements, baseInitialize = System.Exception.__meta(staticValues);
        typeObject.baseType = baseTypeObject;
        typeObject.level = baseTypeObject.level + 1;
        typeObject.implements = implements;
        local elementGenerator = function()
            local element = baseElementGenerator();
            element.type = typeObject;
            element[typeObject.Level] = {
            };
            return element;
        end
        staticValues[typeObject.Level] = {
        };
        local initialize = function(element, values)
            if baseInitialize then baseInitialize(element, values); end
        end
        local getMembers = function()
            local members = _M.RTEF(getBaseMembers);
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                scope = 'Public',
                func = function(element)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_8736("System error.");
                end,
            });
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8736,
                scope = 'Public',
                func = function(element, message)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_8736(message);
                end,
            });
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 41328,
                scope = 'Public',
                func = function(element, message, innerException)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_41328(message, innerException);
                end,
            });
            return members;
        end
        return 'Class', typeObject, getMembers, constructors, elementGenerator, nil, initialize;
    end,
}));
_M.ATN('System.Collections','IEnumerable', _M.NE({
    [0] = function(interactionElement, generics, staticValues)
        local genericsMapping = {};
        local typeObject = System.Type('IEnumerable','System.Collections', nil, 0, generics, nil, interactionElement, 'Interface',16532);
        local implements = {
        };
        typeObject.implements = implements;
        local getMembers = function()
            local members = {};
            _M.GAM(members, implements);
            _M.IM(members, 'GetEnumerator', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = false,
                numMethodGenerics = 0,
                signatureHash = 0,
                returnType = function() return System.Collections.IEnumerator.__typeof end,
            });
            return members;
        end
        return 'Interface', typeObject, getMembers, nil, nil, nil, nil, attributes;
    end,
}));
_M.ATN('System.Collections','IEnumerator', _M.NE({
    [0] = function(interactionElement, generics, staticValues)
        local genericsMapping = {};
        local typeObject = System.Type('IEnumerator','System.Collections', nil, 0, generics, nil, interactionElement, 'Interface',17436);
        local implements = {
        };
        typeObject.implements = implements;
        local getMembers = function()
            local members = {};
            _M.GAM(members, implements);
            _M.IM(members, 'Current',{
                level = typeObject.Level,
                memberType = 'AutoProperty',
                scope = 'Public',
                static = false,
                returnType = System.Object.__typeof;
            });
            _M.IM(members, 'MoveNext', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = false,
                numMethodGenerics = 0,
                signatureHash = 0,
                returnType = function() return System.Boolean.__typeof end,
            });
            _M.IM(members, 'Reset', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = false,
                numMethodGenerics = 0,
                signatureHash = 0,
            });
            return members;
        end
        return 'Interface', typeObject, getMembers, nil, nil, nil, nil, attributes;
    end,
}));
_M.ATN('System.Collections.Generic','IEnumerable', _M.NE({
    [1] = function(interactionElement, generics, staticValues)
        local genericsMapping = {['T'] = 1};
        local typeObject = System.Type('IEnumerable','System.Collections.Generic', nil, 1, generics, nil, interactionElement, 'Interface',(33064*generics[genericsMapping['T']].signatureHash));
        local implements = {
            System.Collections.IEnumerable.__typeof,
        };
        typeObject.implements = implements;
        local getMembers = function()
            local members = {};
            _M.GAM(members, implements);
            _M.IM(members, 'GetEnumerator', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = false,
                numMethodGenerics = 0,
                signatureHash = 0,
                returnType = function() return System.Collections.Generic.IEnumerator[{generics[genericsMapping['T']]}].__typeof end,
            });
            return members;
        end
        return 'Interface', typeObject, getMembers, nil, nil, nil, nil, attributes;
    end,
}));
_M.ATN('System.Collections.Generic','IEnumerator', _M.NE({
    [1] = function(interactionElement, generics, staticValues)
        local genericsMapping = {['T'] = 1};
        local typeObject = System.Type('IEnumerator','System.Collections.Generic', nil, 1, generics, nil, interactionElement, 'Interface',(34872*generics[genericsMapping['T']].signatureHash));
        local implements = {
            System.IDisposable.__typeof,
            System.Collections.IEnumerator.__typeof,
        };
        typeObject.implements = implements;
        local getMembers = function()
            local members = {};
            _M.GAM(members, implements);
            _M.IM(members, 'Current',{
                level = typeObject.Level,
                memberType = 'AutoProperty',
                scope = 'Public',
                static = false,
                returnType = generics[genericsMapping['T']];
            });
            return members;
        end
        return 'Interface', typeObject, getMembers, nil, nil, nil, nil, attributes;
    end,
}));
_M.ATN('System.Linq','Enumerable', _M.NE({
    [0] = function(interactionElement, generics, staticValues)
        local genericsMapping = {};
        local typeObject = System.Type('Enumerable','System.Linq', nil, 0, generics, nil, interactionElement, 'Class', 13333);
        local baseTypeObject, getBaseMembers, baseConstructors, baseElementGenerator, implements, baseInitialize = System.Object.__meta(staticValues);
        typeObject.baseType = baseTypeObject;
        typeObject.level = baseTypeObject.level + 1;
        typeObject.implements = implements;
        local elementGenerator = function()
            local element = baseElementGenerator();
            element.type = typeObject;
            element[typeObject.Level] = {
            };
            return element;
        end
        staticValues[typeObject.Level] = {
        };
        local initialize = function(element, values)
            if baseInitialize then baseInitialize(element, values); end
        end
        local getMembers = function()
            local members = _M.RTEF(getBaseMembers);
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                scope = 'Public',
                func = function(element)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_0();
                end,
            });
            if true then
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Aggregate', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 118148,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, func)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TAccumulate'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Aggregate', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 152831,
                returnType = function() return methodGenerics[methodGenericsMapping['TAccumulate']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, seed, func)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TAccumulate'] = 2,['TResult'] = 3};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Aggregate', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 3,
                signatureHash = 213521,
                returnType = function() return methodGenerics[methodGenericsMapping['TResult']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, seed, func, resultSelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'All', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return System.Boolean.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Any', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return System.Boolean.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        return true;
                    end
                    return false;
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Any', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return System.Boolean.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    if (predicate == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("predicate"));
                    end
                    
            for _,v in (source % _M.DOT).GetEnumerator() do
                if ((predicate % _M.DOT)(v)) then
                    return true;
                end
            end
            return false; 
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'AsEnumerable', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 1470632578952,
                returnType = function() return System.Nullable[{System.Decimal.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93166322,
                returnType = function() return System.Decimal.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 129809264,
                returnType = function() return System.Double.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 2050726752672,
                returnType = function() return System.Nullable[{System.Double.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 132652768,
                returnType = function() return System.Double.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 2095648428864,
                returnType = function() return System.Nullable[{System.Double.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 281242384,
                returnType = function() return System.Single.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 280448848,
                returnType = function() return System.Double.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 4430530900704,
                returnType = function() return System.Nullable[{System.Double.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 394453520,
                returnType = function() return System.Decimal.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 6231576708960,
                returnType = function() return System.Nullable[{System.Decimal.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 30711110,
                returnType = function() return System.Double.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 483965139776,
                returnType = function() return System.Nullable[{System.Double.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 31382168,
                returnType = function() return System.Double.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 494566514060,
                returnType = function() return System.Nullable[{System.Double.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66448850,
                returnType = function() return System.Single.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 1048549956296,
                returnType = function() return System.Nullable[{System.Single.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66261578,
                returnType = function() return System.Double.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 1045591433240,
                returnType = function() return System.Nullable[{System.Double.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Average', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 4443067182432,
                returnType = function() return System.Nullable[{System.Single.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TResult'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Cast', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 33064,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Concat', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 165320,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, first, second)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Contains', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66131,
                returnType = function() return System.Boolean.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, value)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Contains', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 532101,
                returnType = function() return System.Boolean.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, value, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Count', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return System.Int32.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Count', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return System.Int32.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    local count = 0;
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        count = count + 1;
                    end
                    return count;
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'DefaultIfEmpty', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'DefaultIfEmpty', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66131,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, defaultValue)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Distinct', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 345710,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Distinct', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ElementAt', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 72017,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, index)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ElementAtOrDefault', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 72017,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, index)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TResult'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Empty', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 0,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Except', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 165320,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, first, second)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Except', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 631290,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, first, second, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'First', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    if (predicate == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("predicate"));
                    end
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        if ((predicate % _M.DOT)(value)) then
                            return value;
                        end
                    end
                    _M.Throw(((System.Linq.Error % _M.DOT).NoMatch_M_0_0 % _M.DOT)());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'First', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        return value;
                    end
                    _M.Throw(((System.Linq.Error % _M.DOT).NoElements_M_0_0 % _M.DOT)());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'FirstOrDefault', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    if (predicate == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("predicate"));
                    end
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        if ((predicate % _M.DOT)(value)) then
                            return value;
                        end
                    end
                    return _M.DV(methodGenerics[methodGenericsMapping['TSource']]);
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'FirstOrDefault', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        return value;
                    end
                    return _M.DV(methodGenerics[methodGenericsMapping['TSource']]);
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'GroupBy', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 92138,
                returnType = function() return System.Collections.Generic.IEnumerable[{System.Linq.IGrouping[{methodGenerics[methodGenericsMapping['TKey']], methodGenerics[methodGenericsMapping['TSource']]}].__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'GroupBy', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 558108,
                returnType = function() return System.Collections.Generic.IEnumerable[{System.Linq.IGrouping[{methodGenerics[methodGenericsMapping['TKey']], methodGenerics[methodGenericsMapping['TSource']]}].__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2,['TResult'] = 3};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'GroupBy', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 3,
                signatureHash = 860147468,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, resultSelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2,['TElement'] = 3,['TResult'] = 4};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'GroupBy', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 4,
                signatureHash = 1204212950,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, elementSelector, resultSelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2,['TResult'] = 3};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'GroupBy', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 3,
                signatureHash = 860799826,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, resultSelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            end
            if true then
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2,['TElement'] = 3,['TResult'] = 4};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'GroupBy', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 4,
                signatureHash = 1205238084,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, elementSelector, resultSelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2,['TElement'] = 3};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'GroupBy', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 3,
                signatureHash = 787846,
                returnType = function() return System.Collections.Generic.IEnumerable[{System.Linq.IGrouping[{methodGenerics[methodGenericsMapping['TKey']], methodGenerics[methodGenericsMapping['TElement']]}].__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, elementSelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2,['TElement'] = 3};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'GroupBy', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 3,
                signatureHash = 135488,
                returnType = function() return System.Collections.Generic.IEnumerable[{System.Linq.IGrouping[{methodGenerics[methodGenericsMapping['TKey']], methodGenerics[methodGenericsMapping['TElement']]}].__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, elementSelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TOuter'] = 1,['TInner'] = 2,['TKey'] = 3,['TResult'] = 4};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'GroupJoin', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 4,
                signatureHash = 1892391086,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, outer, inner, outerKeySelector, innerKeySelector, resultSelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TOuter'] = 1,['TInner'] = 2,['TKey'] = 3,['TResult'] = 4};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'GroupJoin', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 4,
                signatureHash = 1893602608,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, outer, inner, outerKeySelector, innerKeySelector, resultSelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Intersect', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 165320,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, first, second)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Intersect', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 631290,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, first, second, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TOuter'] = 1,['TInner'] = 2,['TKey'] = 3,['TResult'] = 4};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Join', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 4,
                signatureHash = 460100,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, outer, inner, outerKeySelector, innerKeySelector, resultSelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TOuter'] = 1,['TInner'] = 2,['TKey'] = 3,['TResult'] = 4};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Join', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 4,
                signatureHash = 1671622,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, outer, inner, outerKeySelector, innerKeySelector, resultSelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Last', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    if (predicate == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("predicate"));
                    end
                    local lastValue = nil;
                    local any = false;
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        if ((predicate % _M.DOT)(value)) then
                            lastValue = value;
                            any = true;
                        end
                    end
                    if (any == false) then
                        _M.Throw(((System.Linq.Error % _M.DOT).NoMatch_M_0_0 % _M.DOT)());
                    end
                    return lastValue;
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Last', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    local lastValue = nil;
                    local any = false;
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        lastValue = value;
                        any = true;
                    end
                    if (any == false) then
                        _M.Throw(((System.Linq.Error % _M.DOT).NoElements_M_0_0 % _M.DOT)());
                    end
                    return lastValue;
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'LastOrDefault', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    if (predicate == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("predicate"));
                    end
                    local lastValue = nil;
                    local any = false;
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        if ((predicate % _M.DOT)(value)) then
                            lastValue = value;
                            any = true;
                        end
                    end
                    if (any == false) then
                        return _M.DV(methodGenerics[methodGenericsMapping['TSource']]);
                    end
                    return lastValue;
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'LastOrDefault', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    local lastValue = nil;
                    local any = false;
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        lastValue = value;
                        any = true;
                    end
                    if (any == false) then
                        return _M.DV(methodGenerics[methodGenericsMapping['TSource']]);
                    end
                    return lastValue;
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'LongCount', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return System.Int64.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'LongCount', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return System.Int64.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 280448848,
                returnType = function() return System.Double.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 394453520,
                returnType = function() return System.Decimal.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 6231576708960,
                returnType = function() return System.Nullable[{System.Decimal.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93166322,
                returnType = function() return System.Decimal.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 1045591433240,
                returnType = function() return System.Nullable[{System.Double.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 129809264,
                returnType = function() return System.Int32.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66261578,
                returnType = function() return System.Double.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 1048549956296,
                returnType = function() return System.Nullable[{System.Single.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 2050726752672,
                returnType = function() return System.Nullable[{System.Int32.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 132652768,
                returnType = function() return System.Int64.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66448850,
                returnType = function() return System.Single.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 494566514060,
                returnType = function() return System.Nullable[{System.Int64.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 31382168,
                returnType = function() return System.Int64.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 483965139776,
                returnType = function() return System.Nullable[{System.Int32.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 30711110,
                returnType = function() return System.Int32.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 4443067182432,
                returnType = function() return System.Nullable[{System.Single.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 4430530900704,
                returnType = function() return System.Nullable[{System.Double.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 2095648428864,
                returnType = function() return System.Nullable[{System.Int64.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 281242384,
                returnType = function() return System.Single.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TResult'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 92138,
                returnType = function() return methodGenerics[methodGenericsMapping['TResult']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Max', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 1470632578952,
                returnType = function() return System.Nullable[{System.Decimal.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 2050726752672,
                returnType = function() return System.Nullable[{System.Int32.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 132652768,
                returnType = function() return System.Int64.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 2095648428864,
                returnType = function() return System.Nullable[{System.Int64.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 281242384,
                returnType = function() return System.Single.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 4443067182432,
                returnType = function() return System.Nullable[{System.Single.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 280448848,
                returnType = function() return System.Double.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 4430530900704,
                returnType = function() return System.Nullable[{System.Double.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 394453520,
                returnType = function() return System.Decimal.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 6231576708960,
                returnType = function() return System.Nullable[{System.Decimal.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 30711110,
                returnType = function() return System.Int32.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 483965139776,
                returnType = function() return System.Nullable[{System.Int32.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 31382168,
                returnType = function() return System.Int64.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            end
            if true then
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 494566514060,
                returnType = function() return System.Nullable[{System.Int64.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66448850,
                returnType = function() return System.Single.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 1048549956296,
                returnType = function() return System.Nullable[{System.Single.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66261578,
                returnType = function() return System.Double.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 1045591433240,
                returnType = function() return System.Nullable[{System.Double.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93166322,
                returnType = function() return System.Decimal.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 129809264,
                returnType = function() return System.Int32.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 1470632578952,
                returnType = function() return System.Nullable[{System.Decimal.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TResult'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Min', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 92138,
                returnType = function() return methodGenerics[methodGenericsMapping['TResult']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TResult'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'OfType', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 33064,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    
            local type = methodGenerics[1];
            local enumerator = (source % _M.DOT).GetEnumerator();
            return System.Linq.Iterator[{System.Object.__typeof}]._C_0_8786(function(_, prevKey)
                while (true) do
                    local key, value = enumerator(_, prevKey);
                    if (key == nil) or (type %_M.DOT).IsInstanceOfType(value) == true then
                        return key, value;
                    end
                    prevKey = key;
                end
            end);
            
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'OrderBy', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 198508,
                returnType = function() return System.Linq.IOrderedEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'OrderBy', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 92138,
                returnType = function() return System.Linq.IOrderedEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    if (keySelector == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("keySelector"));
                    end
                    
            local enumerator = (source % _M.DOT).GetEnumerator();
            local ordered;
            return System.Linq.Iterator[{methodGenerics[methodGenericsMapping['TSource']]}]._C_0_8786(function(_, prevKey)
                if prevKey == nil then
                    ordered  = {};
                    local key, value = nil, nil;
                    while (true) do
                        key, value = enumerator(_, key);
                        if (key == nil) then
                            break;
                        else
                            table.insert(ordered, {
                                sortValue = (keySelector %_M.DOT)(value),
                                value = value
                            });
                        end
                    end
                     
                    table.sort(ordered, function(a,b) return a.sortValue < b.sortValue; end);
                end

                local key = (prevKey or -1) + 1;
                if (ordered[key + 1] == nil) then
                    return nil, nil;
                end

                return key, ordered[key + 1].value;
            end);
            
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'OrderByDescending', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 198508,
                returnType = function() return System.Linq.IOrderedEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'OrderByDescending', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 92138,
                returnType = function() return System.Linq.IOrderedEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Range', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 9815,
                returnType = function() return System.Collections.Generic.IEnumerable[{System.Int32.__typeof}].__typeof end,
                func = function(element, start, count)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TResult'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Repeat', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 5891,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, element, count)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Reverse', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TResult'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Select', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 92138,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    if (selector == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("selector"));
                    end
                    
            local enumerator = (source % _M.DOT).GetEnumerator();
            return System.Linq.Iterator[{methodGenerics[methodGenericsMapping['TSource']]}]._C_0_8786(function(_, prevKey)
                local key, value = enumerator(_, prevKey);
                if (key == nil) then
                    return nil;
                end
                return key, (selector %_M.DOT)(value);
            end); 
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TResult'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Select', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 30737120,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    if (selector == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("selector"));
                    end
                    
            local enumerator = (source % _M.DOT).GetEnumerator();
            return System.Linq.Iterator[{methodGenerics[methodGenericsMapping['TSource']]}]._C_0_8786(function(_, prevKey)
                local key, value = enumerator(_, prevKey);
                if (key == nil) then
                    return nil;
                end
                return key, (selector %_M.DOT)(value, key);
            end); 
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TResult'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'SelectMany', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 516073316,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TCollection'] = 2,['TResult'] = 3};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'SelectMany', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 3,
                signatureHash = 516160016,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, collectionSelector, resultSelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TCollection'] = 2,['TResult'] = 3};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'SelectMany', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 3,
                signatureHash = 890792450,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, collectionSelector, resultSelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TResult'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'SelectMany', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 890705750,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'SequenceEqual', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 631290,
                returnType = function() return System.Boolean.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, first, second, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'SequenceEqual', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 165320,
                returnType = function() return System.Boolean.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, first, second)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Single', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    if (predicate == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("predicate"));
                    end
                    local first = true;
                    local singleValue = nil;
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        if ((predicate % _M.DOT)(value)) then
                            if (first) then
                                singleValue = value;
                                first = false;
                            else
                                _M.Throw(((System.Linq.Error % _M.DOT).MoreThanOneMatch_M_0_0 % _M.DOT)());
                            end
                        end
                    end
                    if (first) then
                        _M.Throw(((System.Linq.Error % _M.DOT).NoMatch_M_0_0 % _M.DOT)());
                    end
                    return singleValue;
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Single', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    local first = true;
                    local singleValue = nil;
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        if (first) then
                            singleValue = value;
                            first = false;
                        else
                            _M.Throw(((System.Linq.Error % _M.DOT).MoreThanOneElement_M_0_0 % _M.DOT)());
                        end
                    end
                    if (first) then
                        _M.Throw(((System.Linq.Error % _M.DOT).NoElements_M_0_0 % _M.DOT)());
                    end
                    return singleValue;
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'SingleOrDefault', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    local first = true;
                    local singleValue = nil;
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        if (first) then
                            singleValue = value;
                            first = false;
                        else
                            _M.Throw(((System.Linq.Error % _M.DOT).MoreThanOneElement_M_0_0 % _M.DOT)());
                        end
                    end
                    if (first) then
                        return _M.DV(methodGenerics[methodGenericsMapping['TSource']]);
                    end
                    return singleValue;
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'SingleOrDefault', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return methodGenerics[methodGenericsMapping['TSource']] end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    if (predicate == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("predicate"));
                    end
                    local first = true;
                    local singleValue = nil;
                    for _,value in (source % _M.DOT).GetEnumerator() do
                        if ((predicate % _M.DOT)(value)) then
                            if (first) then
                                singleValue = value;
                                first = false;
                            else
                                _M.Throw(((System.Linq.Error % _M.DOT).MoreThanOneMatch_M_0_0 % _M.DOT)());
                            end
                        end
                    end
                    if (first) then
                        return _M.DV(methodGenerics[methodGenericsMapping['TSource']]);
                    end
                    return singleValue;
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Skip', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 72017,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, count)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'SkipWhile', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'SkipWhile', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 187239290,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 483965139776,
                returnType = function() return System.Nullable[{System.Int32.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93166322,
                returnType = function() return System.Decimal.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 1470632578952,
                returnType = function() return System.Nullable[{System.Decimal.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 129809264,
                returnType = function() return System.Int32.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 2050726752672,
                returnType = function() return System.Nullable[{System.Int32.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 132652768,
                returnType = function() return System.Int64.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 2095648428864,
                returnType = function() return System.Nullable[{System.Int64.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 281242384,
                returnType = function() return System.Single.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 4443067182432,
                returnType = function() return System.Nullable[{System.Single.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 4430530900704,
                returnType = function() return System.Nullable[{System.Double.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 280448848,
                returnType = function() return System.Double.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 6231576708960,
                returnType = function() return System.Nullable[{System.Decimal.__typeof}].__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 30711110,
                returnType = function() return System.Int32.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 31382168,
                returnType = function() return System.Int64.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 494566514060,
                returnType = function() return System.Nullable[{System.Int64.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66448850,
                returnType = function() return System.Single.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 1048549956296,
                returnType = function() return System.Nullable[{System.Single.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66261578,
                returnType = function() return System.Double.__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            end
            if true then
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 1045591433240,
                returnType = function() return System.Nullable[{System.Double.__typeof}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, selector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            _M.IM(members, 'Sum', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 394453520,
                returnType = function() return System.Decimal.__typeof end,
                func = function(element, source)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Take', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 72017,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, count)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'TakeWhile', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'TakeWhile', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 187239290,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ThenBy', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 232526,
                returnType = function() return System.Linq.IOrderedEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ThenBy', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 338896,
                returnType = function() return System.Linq.IOrderedEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ThenByDescending', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 232526,
                returnType = function() return System.Linq.IOrderedEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ThenByDescending', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 338896,
                returnType = function() return System.Linq.IOrderedEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ToArray', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return System.Array[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    local array = (System.Array[{methodGenerics[methodGenericsMapping['TSource']]}]._C_0_0() % _M.DOT).__Initialize({});
                    local c = 0;
                    for _,element in (source % _M.DOT).GetEnumerator() do
                        (array % _M.DOT)[c] = element;
                        c = c + 1;
                    end
                    return array;
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2,['TElement'] = 3};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ToDictionary', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 3,
                signatureHash = 787846,
                returnType = function() return System.Collections.Generic.Dictionary[{methodGenerics[methodGenericsMapping['TKey']], methodGenerics[methodGenericsMapping['TElement']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, elementSelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2,['TElement'] = 3};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ToDictionary', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 3,
                signatureHash = 135488,
                returnType = function() return System.Collections.Generic.Dictionary[{methodGenerics[methodGenericsMapping['TKey']], methodGenerics[methodGenericsMapping['TElement']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, elementSelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ToDictionary', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 558108,
                returnType = function() return System.Collections.Generic.Dictionary[{methodGenerics[methodGenericsMapping['TKey']], methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ToDictionary', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 92138,
                returnType = function() return System.Collections.Generic.Dictionary[{methodGenerics[methodGenericsMapping['TKey']], methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ToList', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 66128,
                returnType = function() return System.Collections.Generic.List[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    return System.Collections.Generic.List[{methodGenerics[methodGenericsMapping['TSource']]}]['_C_0_'..(66128*methodGenerics[methodGenericsMapping['TSource']].signatureHash)](source);
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ToLookup', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 92138,
                returnType = function() return System.Linq.ILookup[{methodGenerics[methodGenericsMapping['TKey']], methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2,['TElement'] = 3};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ToLookup', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 3,
                signatureHash = 135488,
                returnType = function() return System.Linq.ILookup[{methodGenerics[methodGenericsMapping['TKey']], methodGenerics[methodGenericsMapping['TElement']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, elementSelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2,['TElement'] = 3};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ToLookup', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 3,
                signatureHash = 787846,
                returnType = function() return System.Linq.ILookup[{methodGenerics[methodGenericsMapping['TKey']], methodGenerics[methodGenericsMapping['TElement']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, elementSelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1,['TKey'] = 2};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'ToLookup', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 2,
                signatureHash = 558108,
                returnType = function() return System.Linq.ILookup[{methodGenerics[methodGenericsMapping['TKey']], methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, keySelector, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Union', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 631290,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, first, second, comparer)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Union', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 165320,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, first, second)
                    if (first == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("first"));
                    end
                    if (second == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("second"));
                    end
                    
            local firstSource = (first % _M.DOT).GetEnumerator();
            local secondSource = (second % _M.DOT).GetEnumerator();
            local currentSource, returned;
            return System.Linq.Iterator[{methodGenerics[methodGenericsMapping['TSource']]}]._C_0_8786(function(_, prevKey)
                if prevKey == nil then
                    currentSource = firstSource;
                    returned = {};
                end
                    
                while (true) do
                    local key, value = currentSource(_, prevKey);
                    if (key == nil) then
                        if currentSource == firstSource then
                            currentSource = secondSource;
                        else
                            return nil, nil;
                        end
                    else
                        if (currentSource == firstSource) then
                            table.insert(returned, value);
                            return key, value;
                        else
                            if not(tContains(returned, value)) then
                                return key, value;
                            end
                            prevKey = key;
                        end
                    end

                    prevKey = key;
                end
            end);
            
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Where', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 187239290,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    if (predicate == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("predicate"));
                    end
                    
            local enumerator = (source % _M.DOT).GetEnumerator();
            return System.Linq.Iterator[{methodGenerics[methodGenericsMapping['TSource']]}]._C_0_8786(function(_, prevKey)
                while (true) do
                    local key, value = enumerator(_, prevKey);
                    if (key == nil) or (predicate % _M.DOT)(value, key) == true then
                        return key, value;
                    end
                    prevKey = key;
                end
            end); 
                end
            });
            local methodGenericsMapping = {['TSource'] = 1};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Where', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 1,
                signatureHash = 93993440,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TSource']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, source, predicate)
                    if (source == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("source"));
                    end
                    if (predicate == nil) then
                    _M.Throw(((System.Linq.Error % _M.DOT).ArgumentNull_M_0_8736 % _M.DOT)("predicate"));
                    end
                    
            local enumerator = (source % _M.DOT).GetEnumerator();
            return System.Linq.Iterator[{methodGenerics[methodGenericsMapping['TSource']]}]._C_0_8786(function(_, prevKey)
                while (true) do
                    local key, value = enumerator(_, prevKey);
                    if (key == nil) or (predicate % _M.DOT)(value) == true then
                        return key, value;
                    end
                    prevKey = key;
                end
            end); 
                end
            });
            local methodGenericsMapping = {['TFirst'] = 1,['TSecond'] = 2,['TResult'] = 3};
            local methodGenerics = _M.MG(methodGenericsMapping);
            _M.IM(members, 'Zip', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = true,
                numMethodGenerics = 3,
                signatureHash = 252020,
                returnType = function() return System.Collections.Generic.IEnumerable[{methodGenerics[methodGenericsMapping['TResult']]}].__typeof end,
                generics = methodGenericsMapping,
                func = function(element, methodGenericsMapping, methodGenerics, first, second, resultSelector)
                    _M.Throw(System.NotImplementedException._C_0_0());
                end
            });
            end
            return members;
        end
        return 'Class', typeObject, getMembers, constructors, elementGenerator, nil, initialize;
    end,
}));
_M.ATN('System.Linq','Error', _M.NE({
    [0] = function(interactionElement, generics, staticValues)
        local genericsMapping = {};
        local typeObject = System.Type('Error','System.Linq', nil, 0, generics, nil, interactionElement, 'Class', 3081);
        local baseTypeObject, getBaseMembers, baseConstructors, baseElementGenerator, implements, baseInitialize = System.Object.__meta(staticValues);
        typeObject.baseType = baseTypeObject;
        typeObject.level = baseTypeObject.level + 1;
        typeObject.implements = implements;
        local elementGenerator = function()
            local element = baseElementGenerator();
            element.type = typeObject;
            element[typeObject.Level] = {
            };
            return element;
        end
        staticValues[typeObject.Level] = {
        };
        local initialize = function(element, values)
            if baseInitialize then baseInitialize(element, values); end
        end
        local getMembers = function()
            local members = _M.RTEF(getBaseMembers);
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                scope = 'Public',
                func = function(element)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_0();
                end,
            });
            _M.IM(members, 'ArgumentArrayHasTooManyElements', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8572,
                returnType = function() return System.Exception.__typeof end,
                func = function(element, p0)
                    return System.ArgumentException._C_0_8736(((element % _M.DOT_LVL(typeObject.Level)).F_M_0_47310 % _M.DOT)("Parameter {0} has too many elements", p0));
                end
            });
            _M.IM(members, 'ArgumentNotIEnumerableGeneric', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8572,
                returnType = function() return System.Exception.__typeof end,
                func = function(element, p0)
                    return System.ArgumentException._C_0_8736(((element % _M.DOT_LVL(typeObject.Level)).F_M_0_47310 % _M.DOT)("{0} is not IEnumerable<>;", p0));
                end
            });
            _M.IM(members, 'ArgumentNotSequence', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8572,
                returnType = function() return System.Exception.__typeof end,
                func = function(element, p0)
                    return System.ArgumentException._C_0_8736(((element % _M.DOT_LVL(typeObject.Level)).F_M_0_47310 % _M.DOT)("{0} is not a sequence", p0));
                end
            });
            _M.IM(members, 'ArgumentNotValid', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8572,
                returnType = function() return System.Exception.__typeof end,
                func = function(element, p0)
                    return System.ArgumentException._C_0_8736(((element % _M.DOT_LVL(typeObject.Level)).F_M_0_47310 % _M.DOT)("Argument {0} is not valid", p0));
                end
            });
            _M.IM(members, 'IncompatibleElementTypes', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                returnType = function() return System.Exception.__typeof end,
                func = function(element)
                    return System.ArgumentException._C_0_8736("The two sequences have incompatible element types");
                end
            });
            _M.IM(members, 'ArgumentNotLambda', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8572,
                returnType = function() return System.Exception.__typeof end,
                func = function(element, p0)
                    return System.ArgumentException._C_0_8736(((element % _M.DOT_LVL(typeObject.Level)).F_M_0_47310 % _M.DOT)("Argument {0} is not a LambdaExpression", p0));
                end
            });
            _M.IM(members, 'MoreThanOneElement', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                returnType = function() return System.Exception.__typeof end,
                func = function(element)
                    return System.InvalidOperationException._C_0_8736("Sequence contains more than one element");
                end
            });
            _M.IM(members, 'MoreThanOneMatch', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                returnType = function() return System.Exception.__typeof end,
                func = function(element)
                    return System.InvalidOperationException._C_0_8736("Sequence contains more than one matching element");
                end
            });
            _M.IM(members, 'NoArgumentMatchingMethodsInQueryable', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8572,
                returnType = function() return System.Exception.__typeof end,
                func = function(element, p0)
                    return System.InvalidOperationException._C_0_8736(((element % _M.DOT_LVL(typeObject.Level)).F_M_0_47310 % _M.DOT)("There is no method '{0}' on class System.Linq.Enumerable that matches the specified arguments", p0));
                end
            });
            _M.IM(members, 'NoElements', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                returnType = function() return System.Exception.__typeof end,
                func = function(element)
                    return System.InvalidOperationException._C_0_8736("Sequence contains no elements");
                end
            });
            _M.IM(members, 'NoMatch', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                returnType = function() return System.Exception.__typeof end,
                func = function(element)
                    return System.InvalidOperationException._C_0_8736("Sequence contains no matching element");
                end
            });
            _M.IM(members, 'NoMethodOnType', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 21430,
                returnType = function() return System.Exception.__typeof end,
                func = function(element, p0, p1)
                    return System.InvalidOperationException._C_0_8736(((element % _M.DOT_LVL(typeObject.Level)).F_M_0_47310 % _M.DOT)("There is no method '{0}' on type '{1}' that matches the specified arguments", p0, p1));
                end
            });
            _M.IM(members, 'NoMethodOnTypeMatchingArguments', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 21430,
                returnType = function() return System.Exception.__typeof end,
                func = function(element, p0, p1)
                    return System.InvalidOperationException._C_0_8736(((element % _M.DOT_LVL(typeObject.Level)).F_M_0_47310 % _M.DOT)("There is no method '{0}' on type '{1}' that matches the specified arguments", p0, p1));
                end
            });
            _M.IM(members, 'NoNameMatchingMethodsInQueryable', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8572,
                returnType = function() return System.Exception.__typeof end,
                func = function(element, p0)
                    return System.InvalidOperationException._C_0_8736(((element % _M.DOT_LVL(typeObject.Level)).F_M_0_47310 % _M.DOT)("There is no method '{0}' on class System.Linq.Queryable that matches the specified arguments", p0));
                end
            });
            _M.IM(members, 'ArgumentNull', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8736,
                returnType = function() return System.Exception.__typeof end,
                func = function(element, paramName)
                    return System.ArgumentNullException._C_0_8736(paramName);
                end
            });
            _M.IM(members, 'ArgumentOutOfRange', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8736,
                returnType = function() return System.Exception.__typeof end,
                func = function(element, paramName)
                    return System.ArgumentOutOfRangeException._C_0_8736(paramName);
                end
            });
            _M.IM(members, 'NotImplemented', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                returnType = function() return System.Exception.__typeof end,
                func = function(element)
                    return System.NotImplementedException._C_0_0();
                end
            });
            _M.IM(members, 'NotSupported', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Internal',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 0,
                returnType = function() return System.Exception.__typeof end,
                func = function(element)
                    return System.NotSupportedException._C_0_0();
                end
            });
            _M.IM(members, 'F', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Private',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 47310,
                isParams = true,
                returnType = function() return System.String.__typeof end,
                func = function(element, str, firstParam, ...)
                    local args = (System.Array[{System.Object.__typeof}]._C_0_0() % _M.DOT).__Initialize({[0] = firstParam, ...});
                    return ((System.String % _M.DOT).Format_M_0_47310 % _M.DOT)(str, args);
                end
            });
            return members;
        end
        return 'Class', typeObject, getMembers, constructors, elementGenerator, nil, initialize;
    end,
}));
_M.ATN('System.Linq','Iterator', _M.NE({
    [1] = function(interactionElement, generics, staticValues)
        local genericsMapping = {['T'] = 1};
        local typeObject = System.Type('Iterator','System.Linq', nil, 1, generics, nil, interactionElement, 'Class', (16850*generics[genericsMapping['T']].signatureHash));
        local baseTypeObject, getBaseMembers, baseConstructors, baseElementGenerator, implements, baseInitialize = System.Object.__meta(staticValues);
        table.insert(implements, System.Collections.IEnumerable.__typeof);
        table.insert(implements, System.Collections.Generic.IEnumerable[{generics[genericsMapping['T']]}].__typeof);
        typeObject.baseType = baseTypeObject;
        typeObject.level = baseTypeObject.level + 1;
        typeObject.implements = implements;
        local elementGenerator = function()
            local element = baseElementGenerator();
            element.type = typeObject;
            element[typeObject.Level] = {
                enumerator = _M.DV(System.Collections.Generic.IEnumerator[{generics[genericsMapping['T']]}].__typeof),
            };
            return element;
        end
        staticValues[typeObject.Level] = {
        };
        local initialize = function(element, values)
            if baseInitialize then baseInitialize(element, values); end
            if not(values.enumerator == nil) then element[typeObject.Level].enumerator = values.enumerator; end
        end
        local getMembers = function()
            local members = _M.RTEF(getBaseMembers);
            _M.IM(members, 'enumerator', {
                level = typeObject.Level,
                memberType = 'Field',
                scope = 'Private',
                static = false,
            });
            _M.IM(members, '', {
                level = typeObject.Level,
                memberType = 'Cstor',
                static = true,
                numMethodGenerics = 0,
                signatureHash = 8786,
                scope = 'Public',
                func = function(element, enumerator)
                    (element % _M.DOT_LVL(typeObject.Level - 1))._C_0_0();
                    (element % _M.DOT_LVL(typeObject.Level)).enumerator = enumerator;
                end,
            });
            _M.IM(members, 'GetEnumerator', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Public',
                static = false,
                numMethodGenerics = 0,
                signatureHash = 0,
                returnType = function() return System.Collections.Generic.IEnumerator[{generics[genericsMapping['T']]}].__typeof end,
                func = function(element)
                    return (element % _M.DOT_LVL(typeObject.Level)).enumerator;
                end
            });
            _M.IM(members, 'System.Collections.IEnumerable.GetEnumerator', {
                level = typeObject.Level,
                memberType = 'Method',
                scope = 'Private',
                static = false,
                numMethodGenerics = 0,
                signatureHash = 0,
                returnType = function() return System.Collections.IEnumerator.__typeof end,
                func = function(element)
                    return (element % _M.DOT_LVL(typeObject.Level)).enumerator;
                end
            });
            return members;
        end
        return 'Class', typeObject, getMembers, constructors, elementGenerator, nil, initialize;
    end,
}));
local hashString = function(str, hash)
    hash = hash or 7;
    for i=1, string.len(str) do
        hash = (math.mod or mod)(hash*31 + string.byte(str,i), 1000000);
    end
    return hash;
end

local typeType;
local objectType;

local GetMatchScore;
GetMatchScore = function(self, otherType, otherValue)
    if otherType.GetHashCode() == self.hash then
        return self.level;
    end
    
    if self.implements then
        local bestScore;
        for _,interfaceType in ipairs(self.implements) do
            local score = GetMatchScore(interfaceType, otherType, otherValue);
            if score then
                bestScore = bestScore and math.max(bestScore, score) or score;
            end
        end
        
        if bestScore then
            return math.min(bestScore, self.Level-1);
        end
    end
    
    if otherType.catagory == "Enum" and self.Equals(System.String.__typeof) then
        if (System.Enum % _M.DOT).Parse(otherType, otherValue) then
            return 0;
        end
    end

    if self.baseType then
        return self.baseType.GetMatchScore(otherType);
    end
    
    return nil;
end

local GetFullNameWithGenerics;
GetFullNameWithGenerics = function(self)
    if (self.altTypeName) then
        return self.altTypeName;
    end

    local generic = "";
    if self.numberOfGenerics > 0 then
        generic = "`" .. self.numberOfGenerics .. "[";
        for i,v in ipairs(self.generics) do
            if i > 1 then generic = generic .. ","; end
            generic = generic .. GetFullNameWithGenerics(v);
        end

        generic = generic .. "]";
    end

    return self.namespace .. "." ..  self.name .. generic;
end

local meta = {
    __index = function(self, index)
        if index == "__metaType" then
            return _M.MetaTypes.TypeObject;
        elseif index == "GetType" then
            return function()
                return typeType;
            end
        elseif index == "GetHashCode" then
            return function()
                return self.hash;
            end
        elseif index == "ToString" then
            return function()
                local fullName = self.namespace .. "." .. self.name;

                if self.generics then
                    local genericsNames = {};
                    for i,v in pairs(self.generics) do
                        genericsNames[i] = v.ToString();
                    end
                    return fullName..(#(genericsNames) > 0 and "<"..string.join(",", unpack(genericsNames))..">" or "");
                end
                return fullName;
            end;
        elseif index == "Equals" then
            return function(otherType)
                return self.hash == otherType.GetHashCode();
            end
        elseif index == "IsInstanceOfType" then
            return function(instance)
                local otherType = (instance % _M.DOT).GetType();
                if self.hash == otherType.hash then
                    return true;
                end

                if otherType.baseType and self.IsInstanceOfType({type = otherType.baseType}) then
                    return true;
                end

                for _,imp in ipairs(otherType.implements or {}) do
                    if self.IsInstanceOfType({type = imp}) then
                        return true;
                    end
                end
                return false;
            end
        elseif index == "Name" then
            return self.name;
        elseif index == "Namespace" then
            return self.namespace;
        elseif index == "BaseType" then
            return self.baseType;
        elseif index == "Level" then
            return self.level;
        elseif index == "Generics" then
            return self.generics;
        elseif index == "GetMatchScore" then
            return function(otherType, otherValue) return GetMatchScore(self, otherType, otherValue); end;
        elseif index == "InteractionElement" then
            return self.interactionElement;
        elseif index == "FullName" then
            local generic = "";
            if self.numberOfGenerics > 0 then
                generic = "´" .. self.numberOfGenerics;
            end

            return self.namespace .. "." .. self.name .. generic;
        elseif index == "GetFullNameWithGenerics" then
            return function() return GetFullNameWithGenerics(self); end
        elseif index == "IsEnum" then
            return self.catagory == "Enum";
        elseif index == "IsArray" then
            return self.name == "Array" and self.namespace == "System";
        elseif index == "type" then
            return typeType;
        elseif index == "__is" then
            return function(value) 
                return type(value) == "table" and (value % _M.DOT).GetType() == self; 
            end
        elseif index == "GetGenericArguments" then
            return function()
                local t = {};

                for i,v in pairs(self.generics) do
                    t[i-1] = v;
                end

                return t;
            end
        end
    end,
};

local getHash = function(name, namespace, numberOfGenerics, generics)
    local genericsHash = 1;
    if generics then
        for i,v in pairs(generics) do
            genericsHash = genericsHash  + (primes[i]* v.GetHashCode());
        end
    end

    return hashString(namespace .. "." .. name .. "´".. numberOfGenerics, genericsHash);
end

local typeCache = {};

local typeCall = function(name, namespace, baseType, numberOfGenerics, generics, implements, interactionElement, catagory, signatureHash, altTypeName)
    assert(interactionElement, "Type cannot be created without an interactionElement.");

    catagory = catagory or "Class";
    numberOfGenerics = numberOfGenerics or 0;
    local hash = getHash(name, namespace, numberOfGenerics, generics);
    if typeCache[hash] then 
        error("The type object "..tostring(name).." was already created.");
    end

    local self = interactionElement.__typeof or {};
    self.GetType = nil;

    self.catagory = catagory; 
    self.namespace = namespace;
    self.generics = generics;
    self.name = name; 
    self.numberOfGenerics = numberOfGenerics;
    self.hash = hash;
    self.generics = generics;
    self.baseType = baseType;
    self.level = (baseType and baseType.Level or 0) + 1;
    self.implements = implements;
    self.interactionElement = interactionElement;
    self.interactionElement.__typeof = self;
    self.altTypeName = altTypeName;
    local genericHash = _M.SH(unpack(generics or {}));
    if genericHash == 0 then genericHash = 1; end;
    self.signatureHash = signatureHash*genericHash;
    
    
    setmetatable(self, meta);
    typeCache[hash] = self;
    typeCache[self.GetFullNameWithGenerics()] = self;
    return self;
end

GetTypeFromHash = function(hash)
    return typeCache[hash];
end

GetTypeFromFullName = function(name)
    return typeCache[name];
end

--objectType = typeCall("Object", "System"); -- TODO: Initialize in a way that does not require the type cache
typeType = typeCall("Type", "System", nil, 0, nil, nil, {}, 'Class', 1798);

local meta = {
    __typeof = typeType,
    __is = function(value) return type(value) == "table" and type(value.GetType) == "function" and value.GetType() == typeType; end,
    __meta = function() return typeType; end,
};

local element = {};
setmetatable(element, { 
    __index = function(_, key)
        if meta[key] then 
            return meta[key];
        end
    end,
    __newindex = function(_, key, value)
    end,
    __call = function(_, ...)
        return typeCall(...);
    end,
});

System.Type = element;

System.Collections.ICollection = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local implements = {
        System.Collections.IEnumerable.__typeof,
    };
    local typeObject = System.Type('ICollection','System.Collections', nil, 0, generics, implements, interactionElement, 'Interface',17090);
    return 'Interface', typeObject, nil, nil, nil;
end})
System.Collections.IDictionary = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local implements = {
    };
    local typeObject = System.Type('IDictionary','System.Collections', nil, 0, generics, implements, interactionElement, 'Interface',17474);
    return 'Interface', typeObject, nil, nil, nil;
end})
System.Collections.IEnumerable = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local implements = {
    };
    local typeObject = System.Type('IEnumerable','System.Collections', nil, 0, generics, implements, interactionElement, 'Interface',16532);
    return 'Interface', typeObject, nil, nil, nil;
end})
System.Collections.IList = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local implements = {
        System.Collections.ICollection.__typeof,
        System.Collections.IEnumerable.__typeof,
    };
    local typeObject = System.Type('IList','System.Collections', nil, 0, generics, implements, interactionElement, 'Interface',2980);
    return 'Interface', typeObject, nil, nil, nil;
end})
System.Collections.Generic.Dictionary = _M.NE({[2] = function(interactionElement, generics, staticValues)
    local implements = {
        System.Collections.Generic.IDictionary[generics].__typeof,
        System.Collections.IDictionary.__typeof,
        System.Collections.ICollection.__typeof,
        System.Collections.Generic.ICollection[{System.Collections.Generic.KeyValuePair[generics].__typeof}].__typeof,
        System.Collections.IEnumerable.__typeof,
        System.Collections.Generic.IEnumerable[{System.Collections.Generic.KeyValuePair[generics].__typeof}].__typeof,
        System.Collections.Generic.IReadOnlyDictionary[generics].__typeof,
        System.Collections.Generic.IReadOnlyCollection[{System.Collections.Generic.KeyValuePair[generics].__typeof}].__typeof,
    };
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('Dictionary','System.Collections.Generic',baseTypeObject,2,generics,implements,interactionElement,'Class',14200);
    
    _M.IM(members,'Keys',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        get = function(element)
            return System.Collections.Generic.KeyCollection[generics]["_C_0_" .. (2*System.Collections.Generic.Dictionary[generics].__typeof.signatureHash)](element);
        end,
    });

    _M.IM(members,'Values',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        get = function(element)
            return System.Collections.Generic.ValueCollection[generics]["_C_0_" .. (2*System.Collections.Generic.Dictionary[generics].__typeof.signatureHash)](element);
        end,
    });

    _M.IM(members,'GetEnumerator',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = {},
        numMethodGenerics = 0,
        signatureHash = 0,
        func = function(element)
            local ith, t, s = pairs(element[2]);
            return function(_, prevKey)
                local k,v = ith(t , prevKey);
                if (k == nil) then
                    return nil;
                end

                return k, System.Collections.Generic.KeyValuePair[generics]["_C_0_" .. (2*generics[1].signatureHash + 3*generics[2].signatureHash)](k, v);
            end
        end,
    });

    _M.IM(members,'Add',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = {generics[1], generics[2]},
        signatureHash = 2*generics[1].signatureHash + 3*generics[2].signatureHash,
        numMethodGenerics = 0,
        func = function(element, key, value)
            element[2][key] = value;
        end,
    });

    _M.IM(members,'#',{
        level = typeObject.Level,
        memberType = 'Indexer',
        scope = 'Public',
        types = {generics[1], generics[2]},
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
        end,
    });

    local initialize = function(element, values)
        for i,v in pairs(values) do
            element[2][i] = v;
        end
    end

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end

    return "Class", typeObject, members, constructors, objectGenerator, implements, initialize;
end})

System.Collections.Generic.KeyCollection = _M.NE({[2] = function(interactionElement, generics, staticValues)
    local implements = {
        System.Collections.IEnumerable.__typeof,
        System.Collections.Generic.IEnumerable[{generics[1]}].__typeof,
        System.Collections.ICollection.__typeof,
        System.Collections.Generic.ICollection[{generics[1]}].__typeof,
    };
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('KeyCollection','System.Collections.Generic',baseTypeObject,#(generics),generics,implements,interactionElement,"Class", 25420);
    
    _M.IM(members,'GetEnumerator',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        signatureHash = 0,
        types = {},
        func = function(element)
            return pairs(element[2]);
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*System.Collections.Generic.Dictionary[generics].__typeof.signatureHash,
        scope = 'Public',
        func = function(element, dictionary)
            for key,_ in pairs(dictionary[2]) do
                table.insert(element[2],key);
            end
        end,
    });

    --[[
    local constructors = {
        {
            types = {System.Collections.Generic.Dictionary[generics].__typeof},
            func = function(element, dictionary) 
                for key,_ in pairs(dictionary[2]) do
                    table.insert(element[2],key);
                end
            end,
        }
    }; --]]

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end

    return "Class", typeObject, members, constructors, objectGenerator;
end})

System.Collections.Generic.ValueCollection = _M.NE({[2] = function(interactionElement, generics, staticValues)
    local implements = {
        System.Collections.IEnumerable.__typeof,
        System.Collections.Generic.IEnumerable[{generics[2]}].__typeof,
        System.Collections.ICollection.__typeof,
        System.Collections.Generic.ICollection[{generics[2]}].__typeof,
    };
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('ValueCollection','System.Collections.Generic',baseTypeObject,#(generics),generics,implements,interactionElement, "Class", 34765);
    
    _M.IM(members,'GetEnumerator',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        types = {},
        signatureHash = 2*generics[1].signatureHash,
        func = function(element)
            return pairs(element[2]);
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*System.Collections.Generic.Dictionary[generics].__typeof.signatureHash,
        scope = 'Public',
        func = function(element, dictionary)
            for _,value in pairs(dictionary[2]) do
                table.insert(element[2],value);
            end
        end,
    });

    --[[
    local constructors = {
        {
            types = {System.Collections.Generic.Dictionary[generics].__typeof},
            func = function(element, dictionary) 
                for _,value in pairs(dictionary[2]) do
                    table.insert(element[2],value);
                end
            end,
        }
    }; --]]

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end

    return "Class", typeObject, members, constructors, objectGenerator;
end})
System.Collections.Generic.ICollection = _M.NE({[1] = function(interactionElement, generics, staticValues)
    local implements = {
        System.Collections.IEnumerable.__typeof,
    };
    local typeObject = System.Type('ICollection','System.Collections.Generic', nil, 0, generics, implements, interactionElement, 'Interface',17090);
    return 'Interface', typeObject, nil, nil, nil;
end})
System.Collections.Generic.IDictionary = _M.NE({[2] = function(interactionElement, generics, staticValues)
    local implements = {
    };
    local typeObject = System.Type('IDictionary','System.Collections.Generic', nil, 2, generics, implements, interactionElement, 'Interface',17474);
    return 'Interface', typeObject, nil, nil, nil;
end})
System.Collections.Generic.IEnumerable = _M.NE({[1] = function(interactionElement, generics, staticValues)
    local implements = {
    };
    local typeObject = System.Type('IEnumerable','System.Collections.Generic', nil, 0, generics, implements, interactionElement, 'Interface',16532);
    return 'Interface', typeObject, nil, nil, nil;
end})
System.Collections.Generic.IList = _M.NE({[1] = function(interactionElement, generics, staticValues)
    local implements = {
        System.Collections.ICollection.__typeof,
        System.Collections.IEnumerable.__typeof,
    };
    local typeObject = System.Type('IList','System.Collections.Generic', nil, 0, generics, implements, interactionElement, 'Interface', 2980);
    return 'Interface', typeObject, nil, nil, nil;
end})
System.Collections.Generic.IReadOnlyCollection = _M.NE({[1] = function(interactionElement, generics, staticValues)
    local implements = {
    };
    local typeObject = System.Type('IReadOnlyCollection','System.Collections.Generic', nil, 0, generics, implements, interactionElement, 'Interface', 59696);
    return 'Interface', typeObject, nil, nil, nil;
end})
System.Collections.Generic.IReadOnlyDictionary = _M.NE({[2] = function(interactionElement, generics, staticValues)
    local implements = {
    };
    local typeObject = System.Type('IReadOnlyDictionary','System.Collections.Generic', nil, 2, generics, implements, interactionElement, 'Interface', 60400);
    return 'Interface', typeObject, nil, nil, nil;
end})
System.Collections.Generic.IReadOnlyList = _M.NE({[1] = function(interactionElement, generics, staticValues)
    local implements = {
    };
    local typeObject = System.Type('IReadOnlyList','System.Collections.Generic', nil, 0, generics, implements, interactionElement, 'Interface', 24878);
    return 'Interface', typeObject, nil, nil, nil;
end})
System.Collections.Generic.KeyValuePair = _M.NE({[2] = function(interactionElement, generics, staticValues)
    local implements = {
    };
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('KeyValuePair','System.Collections.Generic',baseTypeObject,2,generics,implements,interactionElement,'Class', 20165);
    
    _M.IM(members,'Key',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        types = {generics[1]},
        get = function(element)
            return element[typeObject.level].key;
        end,
    });

    _M.IM(members,'Value',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        types = {generics[2]},
        get = function(element)
            return element[typeObject.level].value;
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*generics[1].signatureHash + 3*generics[2].signatureHash,
        scope = 'Public',
        func = function(element, key, value)
            element[typeObject.level].key = key;
            element[typeObject.level].value = value;
        end,
    });

    --[[
    local constructors = {
        {
            types = {generics[1], generics[2]},
            func = function(element, key, value)
                element[typeObject.level].key = key;
                element[typeObject.level].value = value;
            end,
        }
    }; --]]

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end

    return "Class", typeObject, members, constructors, objectGenerator, implements, nil;
end})
System.Collections.Generic.List = _M.NE({[1] = function(interactionElement, generics, staticValues)
    local implements = {
        System.Collections.IList.__typeof,
        System.Collections.Generic.IList[generics].__typeof,
        System.Collections.ICollection.__typeof,
        System.Collections.Generic.ICollection[generics].__typeof,
        System.Collections.IEnumerable.__typeof,
        System.Collections.Generic.IEnumerable[generics].__typeof,
        System.Collections.Generic.IReadOnlyList[generics].__typeof,
        System.Collections.Generic.IReadOnlyCollection[generics].__typeof,
    };
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('List','System.Collections.Generic',baseTypeObject,1,generics,implements,interactionElement,'Class', 1854);

    local getCount = function(element)
        return not(element[typeObject.level][0] == nil) and (#(element[typeObject.level]) + 1) or 0;
    end

    _M.IM(members,'ForEach',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        signatureHash = 2*4393*2*generics[1].signatureHash,
        types = {System.Action[{generics[1]}].__typeof},
        func = function(element,action)
            for i = 0,getCount(element)-1 do
                (action%_M.DOT)(element[typeObject.level][i]);
            end
        end,
    });

    _M.IM(members,'Count',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        types = {},
        numMethodGenerics = 0,
        signatureHash = 0,
        get = function(element)
            return getCount(element);
        end,
    });

    _M.IM(members,'Capacity',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        types = {},
        numMethodGenerics = 0,
        get = function(element)
            local c = getCount(element);
            return c == 0 and c or math.max(4, c);
        end,
    });

    local ThrowIfIndexNotNumber = function(element, index)
        if not(type(index) == "number") then
            _M.Throw(System.Exception._C_0_8736("Attempted to index list with a non number index: "..tostring(index)));
        end
    end

    local ThrowIfOutOfRange = function(element, index)
        local c = getCount(element);
        if index < 0 or index >= c then
            _M.Throw(System.ArgumentOutOfRangeException._C_0_0());
        end
    end

    _M.IM(members,'#',{
        level = typeObject.Level,
        memberType = 'Indexer',
        scope = 'Public',
        --types = {generics[1]},
        get = function(element, index)
            ThrowIfIndexNotNumber(element, index);
            ThrowIfOutOfRange(element, index);
            return element[typeObject.level][index];
        end,
        set = function(element, index, value)
            ThrowIfIndexNotNumber(element, index);
            ThrowIfOutOfRange(element, index);
            element[typeObject.level][index] = value;
        end,
    });

    _M.IM(members,'Add',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        signatureHash = 2*generics[1].signatureHash;
        func = function(element,value)
            local c = getCount(element);
            element[typeObject.level][c] = value;
            return c;
        end,
    });

    _M.IM(members,'Add',{  --  IList.Add(system.object)
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        signatureHash = 8572;
        func = function(element,value)
            local c = getCount(element);
            element[typeObject.level][c] = value;
            return c;
        end,
    });
    
    _M.IM(members,'AddRange',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        signatureHash = 2*System.Collections.Generic.IEnumerable[generics].__typeof.signatureHash,
        numMethodGenerics = 0,
        func = function(element,value)
            local c = getCount(element);
            for _,v in (value  % _M.DOT).GetEnumerator() do
                element[typeObject.level][c] = v;
                c = c + 1;
            end
        end,
    });

    _M.IM(members,'GetEnumerator',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        types = {},
        numMethodGenerics = 0,
        signatureHash = 0,
        func = function(element)
            return function(_, prevKey) 
                local key;
                if prevKey == nil then
                    key = 0;
                else
                    key = prevKey + 1;
                end

                if key < getCount(element) then
                    return key, element[typeObject.level][key];
                end
                return nil, nil;
            end;
        end,
    });
    

    _M.IM(members,'IsFixedSize',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        types = {},
        get = function(element)
            return false;
        end,
    });

    _M.IM(members,'IsReadOnly',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        types = {},
        get = function(element)
            return false;
        end,
    });

    _M.IM(members,'IsSynchronized',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        types = {},
        get = function(element)
            return false;
        end,
    });

    _M.IM(members,'SyncRoot',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        types = {},
        get = function(element)
            return System.Object._C_0_0();
        end,
    });

    _M.IM(members,'Clear',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        signatureHash = 0;
        --types = {},
        func = function(element)
            element[typeObject.level] = {};
        end,
    });

    _M.IM(members,'Contains',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        --types = {generics[1]},
        signatureHash = 2*generics[1].signatureHash;
        func = function(element,value)
            for i = 0,getCount(element)-1 do
                if (element[typeObject.level][i] % _M.DOT).Equals_M_0_8572(value) then
                    return true;
                end
            end
            return false;
        end,
    });

    _M.IM(members,'Find',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        --types = {System.Predicate[generics].__typeof},
        signatureHash = 2*(System.Predicate[generics].__typeof).signatureHash,
        func = function(element,f)
            for i = 0,getCount(element)-1 do
                local v = element[typeObject.level][i];
                if (f % _M.DOT)(v) then
                    return v;
                end
            end
        end,
    });

    _M.IM(members,'FindIndex',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        --types = {System.Predicate[generics].__typeof},
        signatureHash = 2*(System.Predicate[generics].__typeof).signatureHash,
        func = function(element,f)
            for i = 0,getCount(element)-1 do
                local v = element[typeObject.level][i];
                if (f % _M.DOT)(v) then
                    return i;
                end
            end
        end,
    });

    _M.IM(members,'FindLast',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        --types = {System.Predicate[generics].__typeof},
        signatureHash = 2*(System.Predicate[generics].__typeof).signatureHash,
        func = function(element,f)
            for i = getCount(element)-1,0,-1 do
                local v = element[typeObject.level][i];
                if (f % _M.DOT)(v) then
                    return v;
                end
            end
        end,
    });

    _M.IM(members,'FindLastIndex',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        --types = {System.Predicate[generics].__typeof},
        signatureHash = 2*(System.Predicate[generics].__typeof).signatureHash,
        func = function(element,f)
            for i = getCount(element)-1,0,-1 do
                local v = element[typeObject.level][i];
                if (f % _M.DOT)(v) then
                    return i;
                end
            end
        end,
    });

    _M.IM(members,'FindAll',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        --types = {System.Predicate[generics].__typeof},
        signatureHash = 2*(System.Predicate[generics].__typeof).signatureHash,
        func = function(element,f)
            local list = System.Collections.Generic.List[generics]._C_0_0();
            for i = 0,getCount(element)-1 do
                local v = element[typeObject.level][i];
                if (f % _M.DOT)(v) then
                    (list % _M.DOT).Add_M_0_8572(v);
                end
            end
            return list;
        end,
    });

    _M.IM(members,'IndexOf',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        --types = {generics[1]},
        signatureHash = 2*generics[1].signatureHash,
        func = function(element,value)
            for i = 0,getCount(element)-1 do
                local v = element[typeObject.level][i];
                if (v % _M.DOT).Equals_M_0_8572(value) then
                    return i;
                end
            end
            return -1;
        end,
    });

    _M.IM(members,'LastIndexOf',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        --types = {generics[1]},
        signatureHash = 2*generics[1].signatureHash,
        func = function(element,value)
            for i = getCount(element)-1,0,-1 do
                local v = element[typeObject.level][i];
                if (v % _M.DOT).Equals_M_0_8572(value) then
                    return i;
                end
            end
        end,
    });

    _M.IM(members,'Insert',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        types = {System.Int.__typeof, generics[1]},
        signatureHash = 2*System.Int.__typeof.signatureHash + 3*generics[1].signatureHash,
        func = function(element,index,value)
            for i = getCount(element)-1,index,-1 do
                element[typeObject.level][i+1] = element[typeObject.level][i];
            end
            element[typeObject.level][index] = value;
        end,
    });

    _M.IM(members,'GetRange',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        --types = {System.Int.__typeof, System.Int.__typeof},
        signatureHash = 2*System.Int.__typeof.signatureHash + 3*System.Int.__typeof.signatureHash,
        func = function(element, start, num)
            local list = System.Collections.Generic.List[generics]._C_0_0();
            for i = start, start + num - 1 do
                (list % _M.DOT).Add_M_0_8572(element[typeObject.level][i]);
            end
            return list;
        end,
    });

    _M.IM(members,'InsertRange',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        --types = {System.Int.__typeof, System.Collections.Generic.IEnumerable[generics].__typeof},
        signatureHash = 2*System.Int.__typeof.signatureHash + 3*System.Collections.Generic.IEnumerable[generics].__typeof.signatureHash,
        func = function(element,start, value)
            local count = 0;
            for _,v in (value  % _M.DOT).GetEnumerator() do
                count = count + 1;
            end
            
            for i = getCount(element)-1,start,-1 do
                element[typeObject.level][i+count] = element[typeObject.level][i];
            end

            local c = start;
            for _,v in (value  % _M.DOT).GetEnumerator() do
                element[typeObject.level][c] = v;
                c = c + 1;
            end
        end,
    });

    _M.IM(members,'Remove',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        --types = {generics[1]},
        signatureHash = 2*generics[1].signatureHash,
        func = function(element, obj)
            local index = (element % _M.DOT).IndexOf(obj);
            if index < 0 then
                return false;
            end
            local count = getCount(element);
            for i = index, count do
                element[typeObject.level][i] = element[typeObject.level][i+1];
            end
            return true;
        end,
    });

    _M.IM(members,'RemoveRange',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        --types = {System.Int.__typeof, System.Int.__typeof},
        signatureHash = 2*System.Int.__typeof.signatureHash + 3*System.Int.__typeof.signatureHash,
        func = function(element, start, num)
            local count = getCount(element);
            for i = start, count do
                element[typeObject.level][i] = element[typeObject.level][i+num];
            end
        end,
    });

    _M.IM(members,'RemoveAt',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        numMethodGenerics = 0,
        signatureHash = 3926,
        func = function(element, index)
            ThrowIfIndexNotNumber(element, index);
            ThrowIfOutOfRange(element, index);
            local count = getCount(element);
            for i = index, count do
                element[typeObject.level][i] = element[typeObject.level][i+1];
            end
        end,
    });


    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*System.Collections.Generic.IEnumerable[{generics[1]}].__typeof.signatureHash,
        scope = 'Public',
        func = function(element, values)
            local c = 0;
            for _,v in (values %_M.DOT).GetEnumerator() do
                element[typeObject.level][c] = v;
                c = c + 1;
            end
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 2*Lua.Function.__typeof.signatureHash,
        scope = 'Public',
        func = function(element, values)
            local c = 0;
            for _,v in values do
                element[typeObject.level][c] = v;
                c = c + 1;
            end
        end,
    });

    local initialize = function(element, values)
        for i=1,#(values) do
            element[typeObject.level][i-1] = values[i];
        end
    end

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end

    return "Class", typeObject, members, constructors, objectGenerator, implements, initialize;
end})
CsLuaFramework = { __metaType = _M.MetaTypes.NameSpace };
CsLuaFramework.Environment = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('CsLuaFramework','Environment',baseTypeObject,0,nil,nil,interactionElement, "Class", 29943);

    _M.IM(members,'IsExecutingAsLua',{
        level = typeObject.Level,
        memberType = 'Property',
        scope = 'Public',
        static = true,
        types = {System.Boolean.__typeof},
        get = function(_, obj)
            return true;
        end,
    });

    _M.IM(members,'ExecuteLuaCode',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = true,
        types = {System.String.__typeof},
        numMethodGenerics = 0,
        signatureHash = 8736,
        func = function(_, lua)
            local func, err = loadstring(lua);
            return func();
        end,
    });

    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
CsLuaFramework.ISerializer = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local typeObject = System.Type('ISerializer','CsLuaFramework', nil, 0, generics, implements, interactionElement, 'Interface', 17214);
    return 'Interface', typeObject, nil, nil, nil;
end})
CsLuaFramework.Serializer = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('Serializer','CsLuaFramework',baseTypeObject,0,nil,nil,interactionElement, "Class", 13977);

    local replaceTypeRefs;
    replaceTypeRefs = function(obj)
        local t = {};
        for i,v in ipairs(obj) do
            for index, value in pairs(v) do
                local strPrefix = type(index) == "string" and i.."_" or i.."#_";

                if type(value) == "table" and value.__metaType == _M.MetaTypes.ClassObject then
                    t[strPrefix..index] = replaceTypeRefs(value);
                else
                    t[strPrefix..index] = value;
                end
            end
        end

        t.type = (obj.type %_M.DOT).GetFullNameWithGenerics();

        return t;
    end

    local replaceTypeNamesWithTypes;
    replaceTypeNamesWithTypes = function(obj)
        if type(obj) == "table" then
            local t = {[1] = {}};
            for i,v in pairs(obj) do
                if i == "type" and type(v) == "string" then
                    t[i] = GetTypeFromFullName(v);
                    t.__metaType = _M.MetaTypes.ClassObject;
                else
                    local level, isNum, index = string.match(i,"^(%d*)(#?)_(.*)");
                    level = tonumber(level);
                    index = not(isNum == nil) and tonumber(index) or index;
                    t[level] = t[level] or {};
                    t[level][index] = replaceTypeNamesWithTypes(v);
                end
            end
            return t;
        else
            return obj;
        end
    end

    _M.IM(members,'Serialize',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = false,
        numMethodGenerics = 1,
        signatureHash = 2,
        types = {System.Object.__typeof},
        func = function(_, obj)
            return replaceTypeRefs(obj);
        end,
    });

    _M.IM(members,'Deserialize',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = false,
        numMethodGenerics = 1,
        signatureHash = 55918,
        types = {System.Object.__typeof},
        func = function(_, obj)
            return replaceTypeNamesWithTypes(obj);
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
        end,
    });

    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
CsLuaFramework.Attributes = { __metaType = _M.MetaTypes.NameSpace };
CsLuaFramework.Attributes.ProvideSelfAttribute = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('CsLuaFramework.Attributes','ProvideSelfAttribute',baseTypeObject,0,nil,nil,interactionElement,"Class", 67183);


    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
CsLuaFramework.Wrapping = { __metaType = _M.MetaTypes.NameSpace };
CsLuaFramework.Wrapping.IMultipleValues = _M.NE({['#'] = function(interactionElement, generics, staticValues)
    local typeObject = System.Type('IMultipleValues','CsLuaFramework.Wrapping', nil, 0, generics, implements, interactionElement, 'Interface', 34680);
    return 'Interface', typeObject, nil, nil, nil;
end})
CsLuaFramework.Wrapping.IWrapper = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local typeObject = System.Type('IWrapper','CsLuaFramework.Wrapping', nil, 0, generics, implements, interactionElement, 'Interface', 8227);
    return 'Interface', typeObject, nil, nil, nil;
end})
CsLuaFramework.Wrapping.MultipleValues = _M.NE({['#'] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local implements = {
        CsLuaFramework.Wrapping.IMultipleValues[generics].__typeof,
    };
    local typeObject = System.Type('MultipleValues','CsLuaFramework.Wrapping',baseTypeObject,#(generics),generics,implements,interactionElement, "Class", 29777);
    
    for i=1,#(generics) do
        _M.IM(members,'Value'..i,{
            level = typeObject.Level,
            memberType = 'Property',
            scope = 'Public',
            types = {generics[i]},
            get = function(element)
                return element[typeObject.level]["Value"..i];
            end,
        });
    end
    
    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0, -- TODO: Replace with correct signature once signatures from N generics is solved.
        scope = 'Public',
        func = function(element, ...)
            for i = 1, #(generics) do
                element[typeObject.level]["Value"..i] = select(i, ...);
            end
        end,
    });

    --[[
    local constructors = {
        {
            types = generics,
            func = function(element, ...)
                for i = 1, #(generics) do
                    element[typeObject.level]["Value"..i] = select(i, ...);
                end
            end,
        },
    }; --]]
    
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    
    return "Class", typeObject, members, constructors, objectGenerator, implements, nil;
end})

local wrap = function(typeObj, typeTranslator, value, ...)
    if (typeObj == nil) then -- void
        return;
    end

    if (typeObj.FullName == "CsLuaFramework.Wrapping.IMultipleValues") then
        return CsLuaFramework.Wrapping.MultipleValues[typeObj.Generics]._C_0_0(value, ...);
    end
    
    if not(type(value) == "table") then
        return value;
    end

    if (type(value.type) == "table" and value.type.type == System.Type.__typeof) then
        return value;
    end

    if (typeObj.signatureHash == 4343 or typeObj.signatureHash == 4286) then -- Native lua table or object
        return value;
    end
    
    if (typeTranslator) then
        typeObj = (typeTranslator %_M.DOT)(value) or typeObj;
    end
    
    return CsLuaFramework.Wrapping.WrappedLuaTable[{typeObj}]["_C_0_"..(8686 + 3*System.Func[{Lua.NativeLuaTable.__typeof, System.Type.__typeof}].__typeof.signatureHash)](value, typeTranslator);
end

local unwrap = function(value)
    if type(value) == "table" and value.__metaType == "GenericMethod" then
        return function(...) return value(...); end
    elseif type(value) == "table" and type(value[2]) == "table" and type(value[2].luaTable) == "table" then
        return value[2].luaTable;
    elseif type(value) == "table" and type(value.type) == "table" and value.type.Namespace == "System" and (value.type.Name == "Func" or value.type.Name == "Action") then
        return value[2].innerAction;
    end

    return value;
end

local selectOn = function(t, e)
    local t2 = {};
    for i,v in pairs(t) do
        t2[i] = e(v);
    end
    return t2;
end

local insert = function(t, i, v)
    local t2 = {[i] = v};

    for index, v in pairs(t) do
        if type(index) == "number" and index >= i then
            t2[index + 1] = v;
        else
            t2[index] = v;
        end
    end

    return t2;
end

local hasProvideSelfAttribute = function(attributes)
    local selfAttribute = CsLuaFramework.Attributes.ProvideSelfAttribute.__typeof;

    for _,v in pairs(attributes or {}) do
        if v == selfAttribute then
            return true;
        end
    end

    return false;
end

CsLuaFramework.Wrapping.WrappedLuaTable = _M.NE({[1] = function(interactionElement, generics, staticValues)
    local interfaceType = generics[1];

    local implements = {
        interfaceType
    };

    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('WrappedLuaTable_'..interfaceType.name,'CsLuaFramework.Wrapping',baseTypeObject,#(generics),generics,implements,interactionElement,"Class", 37615);

    local _, interfaceMembers, _, _, _, _, attributes = interfaceType.interactionElement.__meta({});

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 8686,
        scope = 'Public',
        func = function(element, luaTable)
            element[typeObject.level].luaTable = luaTable
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 8686 + 3*System.Func[{Lua.NativeLuaTable.__typeof, System.Type.__typeof}].__typeof.signatureHash,
        scope = 'Public',
        func = function(element, luaTable, typeTranslator)
            element[typeObject.level].luaTable = luaTable;
            element[typeObject.level].typeTranslator = typeTranslator;
        end,
    });

    --[[
    local constructors = {
        {
            types = {Lua.NativeLuaTable.__typeof},
            func = function(element, luaTable) 
                element[typeObject.level].luaTable = luaTable
            end,
        },
        {
            types = {Lua.NativeLuaTable.__typeof, System.Func[{Lua.NativeLuaTable.__typeof, System.Type.__typeof}].__typeof},
            func = function(element, luaTable, typeTranslator) 
                element[typeObject.level].luaTable = luaTable;
                element[typeObject.level].typeTranslator = typeTranslator;
            end,
        }
    }; --]]

    for name,memberSet in pairs(interfaceMembers) do
        for _, member in pairs(memberSet) do
            local m = {
                level = typeObject.Level,
                memberType = member.memberType,
                scope = 'Public',
                static = false,
            };

            if member.memberType == "Property" or member.memberType == "AutoProperty" then
                m.memberType = "Property";
                m.get = function(element)
                    return wrap(member.returnType, element[typeObject.level].typeTranslator, element[typeObject.level].luaTable[name]);
                end;
                m.set = function(element, value)
                    element[typeObject.level].luaTable[name] = unwrap(value);
                end;
            elseif member.memberType == "Method" then
                m.types = member.types;
                m.numMethodGenerics = member.numMethodGenerics;
                m.signatureHash = member.signatureHash;
                m.func = function(element,...)
                    local args = selectOn({...}, unwrap);
                    if hasProvideSelfAttribute(attributes) then
                        args = insert(args, 1, element[typeObject.level].luaTable);
                    end
                    local returnType = nil;
                    if (not(member.returnType == nil)) then
                        returnType = member.returnType();
                    end
                    return wrap(returnType, element[typeObject.level].typeTranslator, element[typeObject.level].luaTable[name](unpack(args)));
                end;
            elseif member.memberType == "Indexer" then
                m.memberType = "Indexer";
                m.get = function(element, key)
                    return wrap(member.returnType, element[typeObject.level].typeTranslator, element[typeObject.level].luaTable[key]);
                end;
                m.set = function(element, key, value)
                    element[typeObject.level].luaTable[key] = unwrap(value);
                end;
            end

            _M.IM(members, name, m);
        end
    end

    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator, implements;
end})

CsLuaFramework.Wrapping.Wrapper = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local implements = { CsLuaFramework.Wrapping.IWrapper.__typeof };
    local typeObject = System.Type('Wrapper','CsLuaFramework.Wrapping',baseTypeObject,0,nil,implements,interactionElement, "Class", 6268);

    local methodGenericsMapping = {['T'] = 1};
    local methodGenerics = _M.MG(methodGenericsMapping);

    _M.IM(members,'Wrap',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = false,
        types = {System.String.__typeof},
        generics = methodGenericsMapping,
        numMethodGenerics = 1,
        signatureHash = 8736,
        func = function(element,methodGenericsMapping,methodGenerics,globalVarName)
            return CsLuaFramework.Wrapping.WrappedLuaTable[methodGenerics]._C_0_8686(_G[globalVarName]);
        end,
    });

    _M.IM(members,'Wrap',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = false,
        numMethodGenerics = 1,
        signatureHash = 318953760,
        types = {System.String.__typeof, System.Func[{Lua.NativeLuaTable.__typeof, System.Type.__typeof}].__typeof},
        generics = methodGenericsMapping,
        func = function(element,methodGenericsMapping,methodGenerics, globalVarName, typeTranslator)
            return CsLuaFramework.Wrapping.WrappedLuaTable[methodGenerics]._C_0_73252846(_G[globalVarName], typeTranslator);
        end,
    });

    _M.IM(members,'Wrap',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = false,
        types = {Lua.NativeLuaTable.__typeof},
        generics = methodGenericsMapping,
        numMethodGenerics = 1,
        signatureHash = 55918,
        func = function(element,methodGenericsMapping,methodGenerics,value)
            return CsLuaFramework.Wrapping.WrappedLuaTable[methodGenerics]._C_0_8686(value);
        end,
    });

    _M.IM(members,'Wrap',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = false,
        numMethodGenerics = 1,
        signatureHash = 319000942,
        types = {Lua.NativeLuaTable.__typeof, System.Func[{Lua.NativeLuaTable.__typeof, System.Type.__typeof}].__typeof},
        generics = methodGenericsMapping,
        func = function(element,methodGenericsMapping,methodGenerics,value, typeTranslator)
            return CsLuaFramework.Wrapping.WrappedLuaTable[methodGenerics]._C_0_73252846(value, typeTranslator);
        end,
    });

    _M.IM(members,'Unwrap',{
        level = typeObject.Level,
        memberType = 'Method',
        scope = 'Public',
        static = false,
        numMethodGenerics = 1,
        signatureHash = 2,
        generics = methodGenericsMapping,
        func = function(element,methodGenericsMapping,methodGenerics,value)
            return unwrap(value);
        end,
    });

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
        end,
    });

    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
Lua = Lua or { __metaType = _M.MetaTypes.NameSpace };
Lua.Function = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('Function','Lua',baseTypeObject,0,nil,nil,interactionElement,"Class", 8352);

    local constructors = {
        {
            types = {},
            func = function() 
                error("Lua.Function can not be constructed");
            end,
        }
    };
    local objectGenerator = function() 
        return {
            [1] = {},
            [2] = {}, 
            ["type"] = typeObject,
            __metaType = _M.MetaTypes.ClassObject,
        }; 
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end})
_M.RE("System.Action", "#", function(generics)
    return {
        {
            name = "ToLuaFunction",
            numMethodGenerics = 0,
            signatureHash = 0,
            func = function(element)
                return element[2].innerAction
            end
        },
    };
end);

_M.RE("System.Func", "#", function(generics)
    return {
        {
            name = "ToLuaFunction",
            numMethodGenerics = 0,
            signatureHash = 0,
            func = function(element)
                return element[2].innerAction
            end
        },
    };
end);

table.Foreach = foreach;
table.contains = tcontains;

_G.__isNamespace = true;
Lua = Lua or {};
Lua.__isNamespace = true;
Lua.Core = _G;
Lua.Strings = _G;
Lua.LuaMath = _G;


    --NativeLuaTable = function() return {__Cstor = function() return {}; end}; end,    


Lua.Strings.format = function(str,...)
    -- TODO: replace {0} with %1$s
    str =  gsub(str,"{(%d)}", function(n) return "%"..(tonumber(n)+1).."$s" end);
    return string.format(str,...)
end

strsplittotable = function(d, str)
    return {strsplit(d, str)};
end
strjoinfromtable = function(d, t)
    return strjoin(d, unpack(t));
end
function strsubutf8(str, a, b) -- modified from http://wowprogramming.com/snippets/UTF-8_aware_stringsub_7
    assert(type(str) == "string" and type(a) == "number", "incorrect input strsubutf8");
    assert(not (b) or (type(b) == "number" and b <= strlenutf8(str)), "end pos larger than string lenght", b, strlenutf8(str));

    b = (b or strlenutf8(str));


    local start, _end = #str + 1, #str + 1;
    local currentIndex = 1
    local numChars = 0;
    if a <= 1 then
        start = a;
    end
    if b <= 1 then
        _end = b;
    end

    while currentIndex <= #str do
        local char = string.byte(str, currentIndex)
        if char > 240 then
            currentIndex = currentIndex + 4
        elseif char > 225 then
            currentIndex = currentIndex + 3
        elseif char > 192 then
            currentIndex = currentIndex + 2
        else    
            currentIndex = currentIndex + 1
        end

        numChars = numChars + 1;

        if numChars == a - 1 then
            start = currentIndex;
        end
        if numChars == b then
            _end = currentIndex - 1;
        end
    end
    return str:sub(start, _end)
end

function IsStringNullOrEmpty(str)
    return str == nil or str == "";
end
Lua.NativeLuaTable = _M.NE({[0] = function(interactionElement, generics, staticValues)
    local baseTypeObject, members = System.Object.__meta(staticValues);
    local typeObject = System.Type('NativeLuaTable','Lua',baseTypeObject,0,nil,nil,interactionElement,'Class',4343);

    _M.IM(members, '', {
        level = typeObject.Level,
        memberType = 'Cstor',
        static = true,
        numMethodGenerics = 0,
        signatureHash = 0,
        scope = 'Public',
        func = function(element)
        end,
    });

    local constructors = {
        {
            types = {},
            func = function() end,
        }
    };
    local objectGenerator = function() 
        return {};
    end
    return "Class", typeObject, members, constructors, objectGenerator;
end});


Lua.Table = {
    getn = table.getn,
    Foreach = function(t, iterator) return table.Foreach(t, iterator[2].innerAction); end,
    foreachi = function(t, iterator) return table.Foreach(t, iterator[2].innerAction); end,
    sort = function(t, iterator)
        if iterator then
            return table.Foreach(t, iterator[2].innerAction); 
        end
        return table.Foreach(t); 
    end,
    contains = table.contains,
    insert = table.insert,
    remove = table.remove,
    wipe = table.wipe,
};
