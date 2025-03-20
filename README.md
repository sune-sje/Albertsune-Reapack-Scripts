# Albertsune's Reapack Scripts

Hi! This is where you find my reascripts. Most are probably meant to be used for Trombone Champ charting, if you don't know what that is ~~_why are you even here_~~ there's probably not much of interest here, but feel free to look around.

---

## 📦 Installation

These scripts are distributed via **ReaPack**, REAPER’s package manager. If you haven’t installed it yet, follow the instructions here: [ReaPack Installation Guide](https://reapack.com/)

Once that’s set up, add my repository by importing this link into ReaPack:

```
https://raw.githubusercontent.com/sune-sje/Albertsune-Reapack-Scripts/master/index.xml
```

After that, you can find and install my scripts directly through **ReaPack**. Just search for the one you need, install it, and run it from the action menu—or bind it to a hotkey if that’s your style.

⚠ **Some scripts require additional dependencies!**  
These are all available in ReaPack’s default repository. If a script needs anything extra, it’ll be noted in the script descriptions below. You may need to restart REAPER after installing dependencies.

---

## 🎼 Scripts

### **Autospacing**

Automatically spaces all notes in selected MIDI takes. It might not be perfect, especially for longer notes, but it's a great head start.

**Features:**  
✅ Does all your spacing for you  
✅ Doesn't touch your slides  

#### **Usage:**  
Select the MIDI takes you want to adjust, then run the script. It will analyze the note positions and update their lengths to hopefully achieve better spacing.  

### **BonerViewer**

📌 _Requires:_ `js_ReaScriptAPI` and `ReaImGui` from the default ReaTeam Extensions repository

Tired of manually exporting MIDI, converting to TMB, and only then previewing your chart? **BonerViewer** lets you preview your chart **inside REAPER**—no conversions needed.

**Features:**  
✅ Live in-game-style preview of your chart  
✅ Edit and store TMB metadata within the REAPER project  
✅ Import metadata from an existing TMB file  
✅ Export TMB directly from reaper, directly to where you'd like it

#### **Usage:**  
BonerViewer will open a window that previews all unmuted MIDI takes as they would appear in-game. This mimics the usual process of exporting the project MIDI, converting, and playing.  

In this window, you can also configure **TMB settings** and export the TMB file. If you prefer to skip the preview, these functions are also available separately in the action menu as:  
- `tmbSettings.lua` (for setting TMB metadata)  
- `ExportTmb.lua` (for exporting the TMB file)  

---

## 💬 Feedback

Please do shoot a message if you find any bugs (rip dms), the more detailed explanation the better.

Happy charting! 🎺🎶

---

~~I definitely did not get chatgpt to write this for me~~
