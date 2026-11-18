using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace Frostpane
{
    internal enum WeatherSchedule { Manual, Random, Season, Local }
    internal sealed class WeatherController
    {
        private readonly Action<WeatherMode,string> apply;
        private readonly Random random=new Random();
        private DateTime next;
        private int generation;
        private WeatherMode lastRandom;
        private WeatherSchedule mode;
        private string place="";
        internal bool Southern;
        internal WeatherController(Action<WeatherMode,string> applyWeather) {apply=applyWeather;}
        internal void Configure(WeatherSchedule value,string location)
        {
            mode=value; place=(location??"").Trim(); next=DateTime.MinValue; generation++; Tick();
        }
        internal void Tick()
        {
            if (mode==WeatherSchedule.Manual || DateTime.UtcNow<next) return;
            int month=DateTime.Now.Month;
            if (mode==WeatherSchedule.Random) {
                var options=new[]{WeatherMode.Snow,WeatherMode.HeavySnow,WeatherMode.Rain,WeatherMode.Sakura,WeatherMode.Leaves,WeatherMode.Fireflies,WeatherMode.Starfall};
                WeatherMode pick=options[random.Next(options.Length)];
                if (pick==lastRandom) pick=options[(Array.IndexOf(options,pick)+1)%options.Length];
                lastRandom=pick; next=DateTime.UtcNow.AddMinutes(15); apply(pick,"Random weather changes every 15 minutes."); return;
            }
            if (mode==WeatherSchedule.Season) {
                next=DateTime.UtcNow.AddHours(1);
                apply(Season(Southern?(month+5)%12+1:month),Southern?"Following the southern hemisphere seasons.":"Following the northern hemisphere seasons.");return;
            }
            next=DateTime.UtcNow.AddMinutes(30);
            if (place.Length!=0) Fetch(place,generation);
        }
        private static WeatherMode Season(int month)
        {
            return month==12 || month<3?WeatherMode.Snow:month<6?WeatherMode.Sakura:month<9?WeatherMode.Fireflies:WeatherMode.Leaves;
        }
        private async void Fetch(string location,int requestId)
        {
            try {
                var result=await Task.Run(delegate { return Lookup(location); });
                if (requestId==generation) apply(result.Key,result.Value);
            } catch (Exception e) {
                if (requestId==generation) apply((WeatherMode)(-1),e is ArgumentException ? e.Message : "Weather unavailable. The current effect will continue.");
            }
        }
        private static Dictionary<string,object> ReadJson(string uri)
        {
            var request=(HttpWebRequest)WebRequest.Create(uri);
            request.Timeout=8000; request.ReadWriteTimeout=8000; request.UserAgent="JakeFrost/3";
            using(var response=request.GetResponse()) using(var stream=response.GetResponseStream())
            using(var reader=new StreamReader(stream,Encoding.UTF8)) {
                char[] data=new char[32768]; int used=0,count;
                while (used<data.Length && (count=reader.Read(data,used,data.Length-used))>0) used+=count;
                if(used==data.Length) throw new InvalidDataException();
                return new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(new string(data,0,used));
            }
        }
        private static KeyValuePair<WeatherMode,string> Lookup(string location)
        {
            var culture=CultureInfo.InvariantCulture; double lat=0,lon=0;
            string label=location; string[] pair=location.Split(',');
            if (pair.Length!=2 || !Double.TryParse(pair[0],NumberStyles.Float,culture,out lat) ||
                !Double.TryParse(pair[1],NumberStyles.Float,culture,out lon) || !(Math.Abs(lat)<=90 && Math.Abs(lon)<=180)) {
                var geo=ReadJson("https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name="+Uri.EscapeDataString(location));
                object hits;
                var list=geo.TryGetValue("results",out hits)?hits as System.Collections.IList:null;
                if (list==null || list.Count==0) throw new ArgumentException("City not found. Try a city, region, or latitude, longitude.");
                var city=(Dictionary<string,object>)list[0];lat=Convert.ToDouble(city["latitude"],culture);lon=Convert.ToDouble(city["longitude"],culture);
                label=Convert.ToString(city["name"],culture)+(city.ContainsKey("country_code")?", "+city["country_code"]:"");
            }
            var json=ReadJson("https://api.open-meteo.com/v1/forecast?latitude="+lat.ToString("0.####",culture)+"&longitude="+lon.ToString("0.####",culture)+"&current=weather_code,is_day&forecast_days=1");
            var current=(Dictionary<string,object>)json["current"];
            int code=Convert.ToInt32(current["weather_code"],culture);
            WeatherMode result; string description;
            if(code==75 || code==86) {result=WeatherMode.HeavySnow;description="heavy snow";}
            else if(code==71 || code==73 || code==77 || code==85) {result=WeatherMode.Snow;description="snow";}
            else if(code>=51) {result=WeatherMode.Rain;description="rain or showers";}
            else {result=WeatherMode.Off;description=code>=45?"fog":code>=2?"clouds":"clear skies";}
            return new KeyValuePair<WeatherMode,string>(result,label+" · "+description+" · Open-Meteo");
        }
    }
}
