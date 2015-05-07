﻿
namespace GH.Presenter.ClusterButtonAnimation
{
    using System.Collections.Generic;
    using BlizzardApi.WidgetEnums;
    using BlizzardApi.WidgetInterfaces;

    public class InstantAnimation : AnimationBase, IClusterButtonAnimation
    {
        public InstantAnimation(double r) : base(r)
        {
            
        }

        public void AnimateButtons(IButton parent, IList<IButton> buttons, bool show)
        {
            for (var i = 0; i < buttons.Count; i++)
            {
                var button = buttons[i];
                if (show)
                {                 
                    var coordinates = this.GetCoordinates(i);
                    button.SetPoint(FramePoint.CENTER, parent, FramePoint.CENTER, coordinates[0], coordinates[1]);
                    button.Show();
                }
                else
                {
                    button.Hide();
                }
            }
        }
    }
}