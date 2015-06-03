﻿namespace CsLuaTest.Interfaces
{
    using General;

    class InterfacesTests : BaseTest
    {
        public InterfacesTests()
        {
            this.Tests["InheritiedInterfaceShouldBeloadedInSignature"] = InheritiedInterfaceShouldBeloadedInSignature;
            this.Tests["ImplementedInterfaceWithGenerics"] = ImplementedInterfaceWithGenerics;
        }

        private static void InheritiedInterfaceShouldBeloadedInSignature()
        {
            var theClass = new InheritingInterfaceImplementation();
            InheritingInterfaceImplementation.AMethodTakingBaseInterface(theClass);
            Assert("OK", Output);
        }

        private static void ImplementedInterfaceWithGenerics()
        {
            var theClass = new ClassA<int, string>();
            theClass.Method("test");
        }

    }
}