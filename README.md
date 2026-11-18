# Jake Frost

Jake Frost brings snow to your Windows desktop. Flakes settle on open window edges, you can roll and throw snowballs, and a tiny elf train delivers gifts from friends.

## Download and run

1. [Download Jake Frost for Windows](https://github.com/jacobbabula/jake-frost/releases/latest/download/Jake-Frost-Windows.zip).
2. Right-click the ZIP in File Explorer and choose **Extract All**.
3. Open the extracted **Jake-Frost** folder and double-click **JakeFrost.exe**. Keep the included **JakeFrost.exe.config** beside it.

The portable app requires Windows with .NET Framework 4.8. The executable is unsigned. If you're upgrading from Frostpane, quit the earlier app before you open Jake Frost.

Click the snowflake in the system tray to reopen settings. The **×** hides settings and **Quit** exits the app.

## Send your first gift

Each person needs a copy of Jake Frost. The recipient sees their gift when they run the app with a desktop display enabled.

**Send a gift file.** Open **Friends**, enter your name, choose **Note**, and write a message. Click **Save gift file…** and send the resulting `.fpgift` to your friend as an attachment. They open **Friends → Open gift file…** and select the attachment. Their gift train brings your message onto the desktop. You can also right-click a dressed tree or snowman to send a copy.

**Use a shared folder for repeat deliveries.** Set up a folder that both PCs can read and write. A shared network folder or the same folder synced locally to both PCs works. On each PC, enter a display name in **Friends**, click **Connect shared folder…**, and select that folder. Once your friend appears under **Send to**, choose a gift and click **Send to friend**. Jake Frost picks up incoming gifts when the recipient's app can access the folder. Everyone with access to the shared folder can read the gifts.

## Play on the desktop

- Grab snow on a window ledge or above the taskbar. Drag it to roll a ball, flick to throw, or gently stack three balls to build a snowman.
- Open **Workshop** to puff snow, pile up a hill, or push a sled down it. **Done** or **Esc** ends desktop editing.
- In **Decorate**, choose a decoration and place it on your desktop. **Workshop → Arrange** lets you select it again. Drag the corner to resize or the circular arrow to rotate. Drag the ends of a light string to tilt it and its middle to adjust the sag.
- **Workshop → Visitor sizes** adjusts the snowplow, Yeti, Santa and reindeer, elf train, and visiting snowmen individually.

**Weather** includes snow, rain, sakura blossoms, leaves, fireflies and starfall. **My weather** looks up the city or coordinates you enter using [Open-Meteo](https://open-meteo.com/).

## Build from source

On Windows with .NET Framework 4.8, open PowerShell in the repository root and run the build script.

```powershell
.\Build.ps1
```

The script uses the Windows .NET Framework C# compiler and builds **JakeFrost.exe** and its configuration file in the repository root. Settings, saved decorations, and local gift records live in `%LOCALAPPDATA%\Frostpane` for compatibility with earlier releases.
