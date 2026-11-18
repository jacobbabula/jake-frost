# Jake Frost

Snow falls on your open windows. Grab a drift, roll a snowball, or send a friend a tiny elf train carrying a note, a tree, or a snowman. Jake Frost is free to download.

## Install Jake Frost

| Computer | Download | Get started |
| --- | --- | --- |
| Windows 10 or 11 | [Download Windows setup](https://github.com/jacobbabula/jake-frost/releases/latest/download/Jake-Frost-Setup.exe) | Quit an older running copy of Jake Frost, open the installer, and click **Install**. Snow starts when setup finishes. |
| Mac with Apple silicon or Intel, macOS 12 or later | [Download the Mac preview](https://github.com/jacobbabula/jake-frost/releases/latest/download/Jake-Frost-Mac.dmg) | Open the disk image, drag **Jake Frost** onto **Applications**, then open it from Applications. |

Use the snowflake in the Windows system tray or Mac menu bar to change snowfall or quit. The Windows installer also adds Jake Frost to the Start menu. It installs for your user account and needs .NET Framework 4.8. A [portable Windows ZIP](https://github.com/jacobbabula/jake-frost/releases/latest/download/Jake-Frost-Windows.zip) is available too. Extract it and open **JakeFrost.exe**.

The Windows installer is unsigned, so Windows may show a publisher warning. The Mac preview uses an ad-hoc signature and does not have Apple notarization. Gatekeeper may block its first launch. [Apple’s guide to opening downloaded apps](https://support.apple.com/en-us/102445).

## Send your first gift

Install Jake Frost on both computers. A Windows user can send to a Mac user and vice versa. All you need to share is a small gift file.

1. **On Windows**, open **Friends**, choose your gift, and select **Copy gift to send**. Paste it into a chat that accepts files, or choose **Save gift file…** and attach the file. **On Mac**, open the snowflake menu, choose **Send a Gift…**, then **Share…** or **Save Gift File…**.
2. **Your friend** downloads the `.fpgift` attachment and double-clicks it. The elf train delivers it on their desktop. They can also open the file from inside Jake Frost, including when using the portable Windows ZIP.

For automatic deliveries between two Windows PCs, expand **Friends → Shared-folder delivery** on both and connect the same shared or synced folder. Enter a display name on each PC. Once the other person appears under **Send to**, choose a gift and click **Send to friend**. Everyone with access to that folder can read its gifts.

## Play on the desktop

**Mac preview.** Flakes settle on exposed window ledges and above the Dock. Drag a drift to roll a ball, then flick and release to throw it. The snowflake menu offers three snowfall levels, pause, clear, and gifts.

**Windows.** The full workshop includes decorations, visitors, sleds and seasonal weather.

- Grab snow on a window ledge or above the taskbar. Drag it to roll a ball, flick to throw, or gently stack three balls to build a snowman.
- Open **Workshop** to puff snow, pile up a hill, or push a sled down it. **Done** or **Esc** ends desktop editing.
- In **Decorate**, choose a decoration and place it on your desktop. **Workshop → Arrange** lets you select it again. Drag the corner to resize or the circular arrow to rotate. Drag the ends of a light string to tilt it and its middle to adjust the sag.
- **Workshop → Visitor sizes** adjusts the snowplow, Yeti, Santa and reindeer, elf train, and visiting snowmen individually.

**Weather** includes snow, rain, sakura blossoms, leaves, fireflies and starfall. **My weather** looks up the city or coordinates you enter using [Open-Meteo](https://open-meteo.com/).

### Hang lights and arrange decorations

1. Choose **Decorate → String lights**. Drag between two points on the desktop for a custom strand. Clicking a ledge hangs a strand along it.
2. Drag either white end to change the length or angle. Drag the center chevron down to increase the sag or up to pull the wire taut.
3. Click the colored-dot button to change that strand’s palette. Scroll over the strand to resize its bulbs. **Workshop → New light strings** chooses the starting palette for future strands.
4. Choose any other decoration to place it. Drop a hat or ornament near the snow to rest it on its visible edge, or drag an ornament onto a tree to hang it. Use **Workshop → Arrange** to select an existing piece. Drag the circular-arrow handle to rotate it freely, or hold **Shift** and scroll over it to turn in 15° increments. The corner handle and plain scroll resize trees and ornaments. Sleds have a rotation handle too.

The gallery includes Christmas trees, lights, candles, red and gold baubles, stars, wreaths, stockings, candy canes, gifts, bells, gingerbread, holly, Santa hats, snow globes, cocoa and boats. **Remember decorations and snowmen** restores saved arrangements per display.

### Weather and visitors

In **Weather**, choose Snow, Heavy snow, Rain, Sakura, Leaves, Fireflies, Starfall or Off. Adjust snowfall volume, wind, accumulation depth and window ice. **Display and seasonal options** controls which monitors show effects, whether snow settles on window edges, and whether effects appear behind open windows. **My weather** looks up the city or coordinates you enter and refreshes about every 30 minutes. Weather and geocoding data come from [Open-Meteo](https://open-meteo.com/).

Send a Yeti, Santa, snowmen or a snowplough from Workshop. Expand **Visitor sizes** to set each visitor from 50% to 250%, including Santa’s sleigh and reindeer and the elf train. Each starts at 100%. Size changes take effect during a visit, and the app remembers each setting. **Visitor speed** has Leisurely, Steady and Brisk settings. It also controls the gift train. The train parks while its note is on screen.

## Build from source

On Windows with .NET Framework 4.8, open PowerShell in the repository root and run the build script.

```powershell
.\Build.ps1
```

The script uses the Windows .NET Framework C# compiler and builds **JakeFrost.exe** and its configuration file in the repository root. Settings, saved decorations, and local gift records live in `%LOCALAPPDATA%\Frostpane` for compatibility with earlier releases.

To build the Windows installer as well, install Inno Setup 6.7 or later and run `.\BuildSetup.ps1`.

On a Mac with the Xcode Command Line Tools installed, run the following from the repository root. It compiles for Apple silicon and Intel, runs the native scene and app checks, and creates **Jake Frost.app** under **macOS/dist**.

```sh
bash macOS/build.sh
```
