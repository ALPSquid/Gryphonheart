﻿namespace WoWSimulator
{
    using System;
    using System.Collections.Generic;
    using BlizzardApi.EventEnums;
    using BlizzardApi.Global;
    using Lua;
    using Moq;
    using SavedData;
    using UISimulation;
    using CsLua.Wrapping;
    using CsLua;

    public class Session : ISession
    {
        private Dictionary<string, Action> addOns;
        private float fps;
        private SavedDataHandler savedDataHandler;
        private IWrapper wrapper;

        public Session(Mock<IApi> apiMock, IFrames globalFrames, UiInitUtil util, FrameActor actor, ISimulatorFrameProvider frameProvider, Dictionary<string, Action> addOns, float fps, SavedDataHandler savedDataHandler, IWrapper wrapper)
        {
            this.ApiMock = apiMock;
            this.Frames = globalFrames;
            this.FrameProvider = frameProvider;
            this.addOns = addOns;
            this.fps = fps;
            this.savedDataHandler = savedDataHandler;
            this.Util = util;
            this.Actor = actor;
            this.wrapper = wrapper;
        }

        public UiInitUtil Util { get; private set; }

        private void SetSessionToGlobal()
        {
            Global.Api = this.ApiMock.Object;
            Global.FrameProvider = this.FrameProvider;
            Global.Frames = this.Frames;
            CsLuaStatic.Wrapper = this.wrapper;
        }

        public void RunStartup()
        {
            this.SetSessionToGlobal();
            foreach (var addon in this.addOns)
            {
                addon.Value();
                this.Util.TriggerEvent(SystemEvent.ADDON_LOADED, addon.Key);
            }

            this.Util.TriggerEvent(SystemEvent.VARIABLES_LOADED, null);
        }

        public void RunUpdate()
        {
            this.SetSessionToGlobal();

            this.Util.UpdateTick(1/this.fps);
            Core.mockTime = Core.time() + 1 / this.fps;
        }

        public void RunUpdateForDuration(TimeSpan time)
        {
            this.SetSessionToGlobal();
            var updates = time.TotalSeconds*this.fps;

            var c = 0;
            while (c < updates)
            {
                this.Util.UpdateTick(1 / this.fps);
                Core.mockTime = Core.time() + 1/this.fps;
                c++;
            }
        }

        public void RunUpdateForDuration(TimeSpan time, int fps)
        {
            this.SetSessionToGlobal();
            throw new NotImplementedException();
        }

        private Mock<IApi> ApiMock { get; set; }

        private IFrames Frames { get; set; }

        public ISimulatorFrameProvider FrameProvider { get; private set; }

        public IFrameActor Actor { get; private set; }

        public NativeLuaTable GetSavedVariables()
        {
            return this.savedDataHandler.GetSavedVariables();
        }

        public T GetGlobal<T>(string name)
        {
            return (T) this.ApiMock.Object.GetGlobal(name);
        }

        public void SetGlobal(string name, object obj)
        {
            this.ApiMock.Object.SetGlobal(name, obj);
        }
    }
}