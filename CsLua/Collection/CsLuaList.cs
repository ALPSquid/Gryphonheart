﻿namespace CsLua.Collection
{
    using System;
    using System.Collections;
    using System.Collections.Generic;
    using System.Linq;
    using Lua;

    [Serializable]
    public class CsLuaList<T> : IList<T>
    {
        protected IList<T> list;

        public CsLuaList()
        {
            this.list = new List<T>();
        }

        protected CsLuaList(NativeLuaTable table)
        {
            throw new NotImplementedException();
        }

        protected CsLuaList(IList<T> innerList)
        {
            this.list = innerList;
        }

        public int IndexOf(T item)
        {
            return this.list.IndexOf(item);
        }

        public void Insert(int index, T item)
        {
            this.list.Insert(index, item);
        }

        public void RemoveAt(int index)
        {
            this.list.RemoveAt(index);
        }

        public T this[int index]
        {
            get
            {
                return this.list[index];
            }
            set
            {
                this.list[index] = value;
            }
        }

        public void Add(T value)
        {
            this.list.Add(value);
        }

        public void Clear()
        {
            this.list.Clear();
        }

        public bool Contains(T item)
        {
            return this.list.Contains(item);
        }

        public void CopyTo(T[] array, int arrayIndex)
        {
            this.list.CopyTo(array, arrayIndex);
        }

        public bool Remove(T item)
        {
            return this.list.Remove(item);
        }

        public int Count
        {
            get { return this.list.Count; }
        }

        public bool IsReadOnly { get; private set; }

        public IEnumerator<T> GetEnumerator()
        {
            return this.list.GetEnumerator();
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return this.list.GetEnumerator();
        }

        public NativeLuaTable ToNativeLuaTable()
        {
            throw new NotImplementedException();
        }

        public CsLuaList<T> Take(int i)
        {
            return new CsLuaList<T>(this.list.Take(i).ToList());
        }

        public CsLuaList<T> Skip(int i)
        {
            return new CsLuaList<T>(this.list.Skip(i).ToList());
        }

        public CsLuaList<T> Where(Func<T, bool> condition)
        {
            return new CsLuaList<T>(this.list.Where(condition).ToList());
        }

        public CsLuaList<TResult> Select<TResult>(Func<T, TResult> selector)
        {
            return new CsLuaList<TResult>(this.list.Select(selector).ToList());
        }

        public bool Any()
        {
            return this.list.Any();
        }

        public bool Any(Func<T, bool> condition)
        {
            return this.list.Any(condition);
        }

        public CsLuaList<T> AddRange(CsLuaList<T> range)
        {
            throw new NotImplementedException();
        }

        public T First()
        {
            return this.list.First();
        }

        public T First(Func<T, bool> condition)
        {
            return this.list.First(condition);
        }

        public T FirstOrDefault()
        {
            return this.list.FirstOrDefault();
        }

        public T FirstOrDefault(Func<T, bool> condition)
        {
            return this.list.FirstOrDefault(condition);
        }

        public T Last()
        {
            return this.list.Last();
        }

        public T Last(Func<T, bool> condition)
        {
            return this.list.Last(condition);
        }

        public T LastOrDefault()
        {
            return this.list.LastOrDefault();
        }

        public T LastOrDefault(Func<T, bool> condition)
        {
            return this.list.LastOrDefault(condition);
        }

        public T Single()
        {
            return this.list.Single();
        }

        public T Single(Func<T, bool> condition)
        {
            return this.list.Single(condition);
        }

        public void Foreach(Action<T> action)
        {
            foreach (var item in this.list)
            {
                action(item);
            }
        }

        public double Max(Func<T, double> selector)
        {
            return this.list.Max(selector);
        }

        public double Min(Func<T, double> selector)
        {
            return this.list.Max(selector);
        }

        public double Sum(Func<T, double> selector)
        {
            return this.list.Sum(selector);
        }
    }
}