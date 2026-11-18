using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace Frostpane
{
    // Each invite is shared privately out of band. Its encryption key never travels
    // to the relay. Labels distinguish names, directions and individual gifts.
    internal static class FriendEnvelope
    {
        private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);
        internal static string Token()
        {
            byte[] bytes = new byte[32];
            using (var random = RandomNumberGenerator.Create()) random.GetBytes(bytes);
            return Url(bytes);
        }
        private static string Url(byte[] bytes) { return Convert.ToBase64String(bytes).TrimEnd('=').Replace('+','-').Replace('/','_'); }
        internal static byte[] Key(string token)
        {
            if (token == null || token.Length != 43) throw new InvalidDataException("Check the invitation code.");
            byte[] raw;
            try { raw = Convert.FromBase64String(token.Replace('-','+').Replace('_','/') + "="); }
            catch (FormatException) { throw new InvalidDataException("Check the invitation code."); }
            if (raw.Length != 32 || Url(raw) != token) throw new InvalidDataException("Check the invitation code.");
            return raw;
        }
        private static byte[] Derive(string secret, string label)
        {
            using (var h = new HMACSHA256(Key(secret))) return h.ComputeHash(Utf8.GetBytes("JakeFrostPost/1/" + label));
        }
        internal static string Id(string secret) { return BitConverter.ToString(Derive(secret,"address"),0,16).Replace("-","").ToLowerInvariant(); }
        internal static string Proof(string secret) { return Url(Derive(secret,"claim")); }

        internal static string Seal(string secret,string label,string value)
        {
            using(var aes=Aes.Create()) {
                aes.Key=Derive(secret,"encrypt/" + label);
                aes.GenerateIV();
                byte[] input=Utf8.GetBytes(value), cipher;
                using(var encoder=aes.CreateEncryptor()) cipher=encoder.TransformFinalBlock(input,0,input.Length);
                byte[] envelope=new byte[16+cipher.Length+32];
                Buffer.BlockCopy(aes.IV,0,envelope,0,16);
                Buffer.BlockCopy(cipher,0,envelope,16,cipher.Length);
                using(var mac=new HMACSHA256(Derive(secret,"authenticate/"+label)))
                    Buffer.BlockCopy(mac.ComputeHash(envelope,0,envelope.Length-32),0,envelope,envelope.Length-32,32);
                return Convert.ToBase64String(envelope);
            }
        }
        internal static string Open(string secret,string label,string encoded)
        {
            if(encoded==null || encoded.Length>28000)throw new InvalidDataException("Invalid encrypted gift.");
            byte[] envelope=Convert.FromBase64String(encoded);
            if(envelope.Length<64 || envelope.Length%16!=0)throw new InvalidDataException("Invalid encrypted gift.");
            using(var mac=new HMACSHA256(Derive(secret,"authenticate/"+label))) {
                byte[] expected=mac.ComputeHash(envelope,0,envelope.Length-32);
                int mismatch=0;
                for(int i=0;i<32;i++)mismatch|=expected[i]^envelope[envelope.Length-32+i];
                if(mismatch!=0)throw new InvalidDataException("This gift could not be authenticated.");
            }
            using(var aes=Aes.Create()) {
                aes.Key=Derive(secret,"encrypt/"+label);
                byte[] iv=new byte[16];Buffer.BlockCopy(envelope,0,iv,0,16);aes.IV=iv;
                using(var decoder=aes.CreateDecryptor()) return Utf8.GetString(decoder.TransformFinalBlock(envelope,16,envelope.Length-48));
            }
        }
    }
}
