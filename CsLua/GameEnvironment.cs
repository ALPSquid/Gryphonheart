﻿namespace CsLua
{
    using System;

    public static class GameEnvironment
    {
        public static bool IsExecutingInGame {
            get {
                return false;
            }
        }

        public static void ExecuteLuaCode(string code)
        {
            throw new CsException("Lua code an only be executed in-game.");
        }
    }
}