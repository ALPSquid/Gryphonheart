﻿
namespace WoWSimulator.UISimulation
{
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using BlizzardApi.Global;
    using BlizzardApi.WidgetEnums;
    using BlizzardApi.WidgetInterfaces;
    using Lua;
    using Moq;
    using XMLHandler;
    using ObjFrameType = FrameType;

    public class SimulatorFrameProvider : ISimulatorFrameProvider
    {
        private readonly UiInitUtil util;
        private readonly FrameActor actor;
        private readonly List<string> xmlFiles;


        public SimulatorFrameProvider(UiInitUtil util, FrameActor actor)
        {
            this.util = util;
            this.actor = actor;
            this.xmlFiles = new List<string>();
        }

        public IUIObject CreateFrame(FrameType frameType)
        {
            return this.CreateFrame(frameType, null, null, null);
        }

        public IUIObject CreateFrame(FrameType frameType, string name)
        {
            return this.CreateFrame(frameType, name, null, null);
        }

        public IUIObject CreateFrame(FrameType frameType, string name, IFrame parent)
        {
            return this.CreateFrame(frameType, name, parent, null);
        }

        public IUIObject CreateFrame(FrameType frameType, string name, IFrame parent, string inherits)
        {
            LayoutFrameType xml;
            switch (frameType)
            {
                case FrameType.Frame:
                    xml = new ObjFrameType();
                    break;
                case FrameType.Button:
                    xml = new ButtonType();
                    break;
                case FrameType.EditBox:
                    xml = new EditBoxType();
                    break;
                default:
                    throw new UiSimuationException(string.Format("Unhandled frame type {0}.", frameType));
            }
            xml.inherits = inherits;
            xml.name = name;
            xml.Items = new object[]{};
            return this.util.CreateObject(xml, parent);
        }

        
        public IUIObject GetMouseFocus()
        {
            throw new NotImplementedException();
        }
        public void EasyMenu(NativeLuaTable menuList, IFrame frame, IFrame anchor, double x, double y, string displayMode, double autoHideDelay)
        {
            this.actor.ShowEasyMenu(menuList);
        }

        public void EasyMenu(NativeLuaTable menuList, IFrame frame, string anchor, double x, double y, string displayMode, double autoHideDelay)
        {
            this.EasyMenu(menuList, frame, this.util.GetObjectByName(anchor) as IFrame, x, y, displayMode, autoHideDelay);
        }

        public void EasyMenu(NativeLuaTable menuList, IFrame frame, IFrame anchor, double x, double y, string displayMode)
        {
            this.EasyMenu(menuList, frame, anchor, x, y, displayMode, 0);
        }

        public void EasyMenu(NativeLuaTable menuList, IFrame frame, string anchor, double x, double y, string displayMode)
        {
            this.EasyMenu(menuList, frame, this.util.GetObjectByName(anchor) as IFrame, x, y, displayMode, 0);
        }


        public void LoadXmlFile(string path)
        {
            this.xmlFiles.Add(path);
        }

        public void LoadXmlFiles()
        {
            foreach (var xmlFilePath in this.xmlFiles)
            {
                var ui = XmlUiLoader.Load(xmlFilePath);
                var items = ui.Items.OfType<LayoutFrameType>().ToList();

                foreach (var obj in items.Where(item => item.@virtual))
                {
                    this.util.AddTempate(obj);
                }


                foreach (var obj in items.Where(item => !item.@virtual))
                {
                    this.util.CreateObject(obj);
                }
            }
        }

        public void TriggerEvent(object eventName, params object[] eventArgs)
        {
            this.util.TriggerEvent(eventName.ToString(), eventArgs);
        }

        public void TriggerHandler(object handler, params object[] args)
        {
            throw new NotImplementedException();
        }


        public void Click(string text)
        {
            
        }
    }
}