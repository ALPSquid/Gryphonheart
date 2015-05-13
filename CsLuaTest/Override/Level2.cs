﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace CsLuaTest.Override
{
    class Level2 : Level1
    {
        public override void M()
        {
            OverrideTest.Output += "Level2M,";
        }

        public void Level2Base()
        {
            base.M();
        }

        public void Level2Self()
        {
            this.M();
        }
    }
}
