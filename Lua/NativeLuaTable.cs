﻿
namespace Lua
{
    using System.Collections.Generic;

    public class NativeLuaTable
    {
        private readonly Dictionary<object, object> innerDictionary = new Dictionary<object, object>();

        public int __Count()
        {
            var i = 1;
            while (this.innerDictionary.ContainsKey(i) && this.innerDictionary[i] != null)
            {
                i++;
            }
            return i - 1;
        }

        public object this[object key]
        {
            get { return this.innerDictionary[key]; }
            set { this.innerDictionary[key] = value; }
        }
    }
}
