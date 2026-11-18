# Jake Frost for the Microsoft Store

Choose **MSIX or PWA app** and reserve **Jake Frost** in Partner Center. In **Product management → Product identity**, copy the package name, publisher and publisher display name exactly. [Microsoft’s submission guide](https://learn.microsoft.com/windows/apps/package-and-deploy/publish-first-app)

Build a submission from the release source with .NET Framework 4.8 and the Windows SDK installed.

```powershell
.\Build.ps1 -OutputDirectory .\dist\app
.\installer\store\BuildStore.ps1 -AppDirectory .\dist\app -OutputDirectory .\dist\store -IdentityName 'RESERVED-PACKAGE-NAME' -Publisher 'CN=ASSIGNED-PUBLISHER-ID' -PublisherDisplayName 'YOUR PUBLISHER DISPLAY NAME'
```

Upload **Jake-Frost-Store.msixupload** in **Packages**. The script uses MakeAppx to validate the manifest and checks the extracted executable against the built app. The **Identity-Preview** archive produced with `-Preview` uses a local test identity. Microsoft must assign the identity before you submit the production build. Store signing happens during certification.

## Store listing

**Name** — Jake Frost  
**Category** — Personalization  
**Price** — Free  
**Short description** — Make it snow on your open windows. Build snowmen, decorate trees, and send gifts by elf train.

**Description**

Catch the snow on a window ledge and roll it into a ball. Toss it with the mouse, stack three balls into your own snowman, or send a plough to clear a path. Wake your snowmen for a snowball fight. A direct hit sends powder into the air and leaves loose snow where the pieces land. Send a little Yeti to chop a tree or start a Blizzard to see Yetis run through wind-driven snow.

Decorate your desktop with adjustable light strings, ornaments and trees. Let the lights twinkle or keep them steady. Choose drifting clouds, rain with optional lightning, cherry blossoms, leaves, fireflies or falling stars. Two original painted landscapes follow your local clock from daylight into night. Choose the lighting yourself or turn the motion off at any time.

Keep in touch with gifts. Share a note, snowman or decorated tree and an elf train delivers it on your friend's desktop.

**Privacy** — [Jake Frost privacy policy](https://jake-frost-mail.netlify.app/privacy.html)  
**Support** — [Jake Frost support](https://github.com/jacobbabula/jake-frost/issues)  
**Logo** — Use the generated `StoreListingLogo.png`.  
**Screenshots** — Use the original 16:9 Jake Frost Windows scene captures from the release's scene-gallery artifact.

## Certification notes

The app uses the native Win32 desktop through the desktop-bridge `runFullTrust` capability. It draws click-through WPF snow on monitor and window edges, hosts optional painted backgrounds behind Explorer's desktop icons, and provides a notification-area menu. It runs at the user's ordinary privilege level. The .fpgift association opens a gift file on the recipient's desktop. A tester can use the workshop, weather and decorations offline or pair two Windows profiles to test online gift delivery. The app exits through **Quit** in the panel or tray. Complete the Store's age-rating and account declarations using the publisher's information before submitting.
