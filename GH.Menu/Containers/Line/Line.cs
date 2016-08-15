﻿namespace GH.Menu.Containers.Line
{
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using BlizzardApi.WidgetEnums;
    using BlizzardApi.WidgetInterfaces;
    using CsLuaFramework.Wrapping;
    using Lua;
    using GH.Menu.Containers;
    using GH.Menu.Containers.AlignedBlock;
    using GH.Menu.Objects;
    using GH.Menu.Theme;

    public class Line : BaseContainer<IAlignedBlock, LineProfile>, ILine
    {
        private IAlignedBlock leftBlock;
        private IAlignedBlock centerBlock;
        private IAlignedBlock rightBlock;

        public Line(IWrapper wrapper) : base("Line", wrapper)
        {

        }


        public override void Prepare(IElementProfile profile, IMenuHandler handler)
        {
            base.Prepare(null, handler);
            
            var lineProfile = (LineProfile)profile;
            this.leftBlock = GenerateAndPrepareBlock(lineProfile, ObjectAlign.l, handler);
            this.centerBlock = GenerateAndPrepareBlock(lineProfile, ObjectAlign.c, handler);
            this.rightBlock = GenerateAndPrepareBlock(lineProfile, ObjectAlign.r, handler);
            this.Content = new List<IAlignedBlock>() {this.leftBlock, this.centerBlock, this.rightBlock};
        }

        private static IAlignedBlock GenerateAndPrepareBlock(LineProfile profile, ObjectAlign align,
            IMenuHandler handler)
        {
            var blockProfile = GenerateAlignedProfile(profile, align);
            return (IAlignedBlock)handler.CreateRegion(blockProfile, false, typeof(AlignedBlock));
        }

        private static LineProfile GenerateAlignedProfile(LineProfile profile, ObjectAlign align)
        {
            var newProfile = new LineProfile();
            newProfile.AddRange(profile.Where(p => p.align == align));
            return newProfile;
        }

        public void SetPosition(IFrame parent, double xOff, double yOff, double width, double height)
        {
            throw new NotImplementedException();
        }

        public double? GetPreferredWidth()
        {
            throw new NotImplementedException();
        }

        public double? GetPreferredHeight()
        {
            throw new NotImplementedException();
        }
    }
}