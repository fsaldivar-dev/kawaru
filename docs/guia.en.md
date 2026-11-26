[Español](guia.md) · **English** · [Português](guia.pt-BR.md) · [Français](guia.fr.md) · [日本語](guia.ja.md) · [简体中文](guia.zh-Hans.md) · [한국어](guia.ko.md)

# Kawaru User Guide

Everything you need to get the most out of it, from installation to your first call.

- [Install](#install)
- [The welcome tutorial](#the-welcome-tutorial)
- [Using it in a call](#using-it-in-a-call)
- [Effects](#effects)
- [Captions](#captions)
- [Gestures](#gestures)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [The menu bar and running in the background](#the-menu-bar-and-running-in-the-background)
- [Capturing the background](#capturing-the-background)
- [If something goes wrong](#if-something-goes-wrong)
- [Privacy](#privacy)

## Install

1. Download `Kawaru-0.2.0.dmg` from the [releases page](https://github.com/fsaldivar-dev/kawaru/releases/latest).
2. Open it and drag **Kawaru** to the **Applications** folder. It has to be there: macOS only lets
   apps in that folder install a virtual camera.
3. Open Kawaru from Applications.

You need macOS 14 or later. Kawaru uses your Mac's language: Spanish, English, Portuguese, French, Japanese,
Simplified Chinese, or Korean.

## The welcome tutorial

![The welcome tutorial](img/app-tutorial.jpg)

The first time you open it, Kawaru walks you through five steps:

1. **What it is.** A quick look at what it does.
2. **Your camera.** Click "Allow Camera" and accept the macOS prompt.
3. **The virtual camera.** Click "Install Virtual Camera". macOS will ask you to approve it: open
   System Settings › General › Login Items & Extensions › Camera Extensions, and turn on Kawaru.
4. **Your first gesture.** Give a thumbs up in front of the camera and hold it for half a second. You'll see
   the points Kawaru reads on your hand, and three marks that fill in each time it recognizes the gesture.
5. **Done.** A summary of how to use it in your calls.

When you finish, a **guided tour** points out each part of the window and tells you what it's for.

![The guided tour](img/app-recorrido.jpg)

You can replay both whenever you like from the **Help** menu.

## Using it in a call

In Meet, Zoom, Teams, or any video app, open the camera settings and choose **Kawaru**.
From then on, others see your picture with whatever you turn on.

You don't need to keep the Kawaru window open: it's enough for the app to be in the menu bar.

> Meet and Zoom show you a mirrored view of yourself, so your own captions will look backwards to you.
> Everyone else reads them just fine. If it bothers you, turn off "Mirror my video" in your call app's settings.

## Effects

![The Effects section](img/app-efectos.jpg)

The **Effects** section has a card for each one. When you select a card, the right side shows a video of
the real effect and what you can adjust:

- **Try It Live:** turns it on over your camera, in the Live section.
- **Hand Pose:** the gesture that triggers it. "None" leaves it shortcut only.
- **Your Own Pose:** record a gesture of your own (see [Gestures](#gestures)).
- **Text or duration**, for the effects that have them: the two lines on the sign, the two in the bubble,
  the confetti word, and the minutes for the break.

The same gesture that turns an effect on turns it off. Confetti and Break go away on their own when they finish.

| Effect | What it does |
|---|---|
| Substitution | You vanish in a puff of smoke, leaving a log behind. Needs a [captured background](#capturing-the-background). |
| Clones | Copies of you appear on either side. |
| Away Sign | Covers the picture with a sign showing your text. |
| Question Bubble | A speech bubble next to you. |
| Confetti | A shower of confetti and a word. |
| Break | A full-screen countdown. |
| Spotlight | You in color, the background in gray. |

## Captions

![The Captions section](img/app-rotulos.jpg)

Captions are text over your picture. Unlike effects, you can have **several at once**.

### Creating one

Click **New Caption** and choose the type:

- **Lower Third:** your name and title.
- **Banner:** a headline, at the top or bottom.
- **Badge:** a short tag in a corner.
- **Full Card:** a full-screen message.
- **Social:** the network's logo and your handle.

### Making it yours

In the editor on the right:

- **Text:** what it says.
- **Theme:** Minimal, Corporate, Neon, Wood, or **Custom**. With Custom you choose the background, text,
  and accent colors, one of seven fonts, and how rounded the corners are.
- **Position:** one of the corners, or **drag on the preview** to put it wherever you like.
  "Reset" sends it back to the corner.
- **Size.**
- **Entrance:** Slide, Fade In, Bounce, or Reveal. "Play Animation" plays it back.
- **Stays:** until you remove it, or from 5 seconds to 1 minute.

On a social caption, **Choose Image…** swaps the logo for an image of your own.

### Several at once

Captions that share a corner stack in the order you turn them on, without covering each other. The ones
you placed by dragging stay where you put them.

### Showing and hiding it

With **Put On Air**, with its gesture, with its shortcut, or from the menu bar.

## Gestures

A gesture is triggered by holding it for a little over **half a second**. To use it again you have to
**lower your hand** first: as long as it stays in the same pose, it won't repeat.

### The built-in ones

Two Fingers to Forehead, Salute, Two Fingers Up, Open Palm, Thumbs Up, and Two-Handed Seal.

### Recording your own

1. On an effect or a caption, click **Record…** next to "Your Own Pose".
2. You have three seconds to pose your hand. You'll see the points Kawaru reads: if they don't show up, it can't see your hand.
3. Hold still while it records.
4. **Repeat it three times**, lowering your hand in between. You don't have to copy it exactly: those
   repetitions teach it how you really make the pose.

A photo of you making the gesture is saved, to help you remember it.

### Tips for gestures that read well

- Make each gesture **clearly different** from the others. If two look alike, Kawaru lets you know.
- One hand reads better than two. If you use two, make sure they **don't touch**: together they look like one.
- Good light from the front, and your hand inside the frame.
- **Practice Gesture** lets you try it out without triggering anything.

## Keyboard shortcuts

They work even when your call app is in front.

| Shortcut | What it triggers |
|---|---|
| ⌃⌥1 … ⌃⌥7 | The effects, in gallery order |
| ⌃⌥⇧1 … ⌃⌥⇧9 | Your captions, in list order |

## The menu bar and running in the background

Kawaru puts an icon in the menu bar. From there you can:

- Turn any effect or caption on or off with one click.
- Pause **Hand Gestures** (shortcuts and buttons keep working).
- Turn on **Open at Login**.
- Open the window, or quit.

Closing the window doesn't quit the app. With the window closed, your camera turns on only when a
call is using the "Kawaru" camera.

## Capturing the background

The effects that remove you from the picture need to know what's behind you. In **Camera**, click
**Capture Background** and step out of frame: three seconds later it takes a photo of the empty background. It lives in
memory only. Take it again if you move the camera.

## If something goes wrong

**The "Kawaru" camera doesn't show up in my call app.**
Check that the Camera section says "Virtual camera active". If you installed it while the call app
was already open, quit the app and open it again. In Chrome, you sometimes have to quit the whole browser.

**The call app shows a card that says "Abre la app Kawaru" (open the Kawaru app).**
Kawaru isn't running. Open it; it can stay in the menu bar.

**A gesture isn't recognized.**
Use "Practice Gesture" and watch the points on your hand. If they don't show up, there isn't enough light or your hand is
out of frame. If they show up but it doesn't count, record the gesture again.

**A gesture triggers something else.**
Two of your gestures look too much alike. Record a different one.

**Meet or Chrome gives me a background I didn't choose.**
That background comes from the browser, not Kawaru. Check the video effects in Chrome itself and in macOS
(the green camera icon in the menu bar).

**The Kawaru icon looks gray.**
That's the macOS icon style (System Settings › Appearance). It affects every app.

## Privacy

- Your camera's picture is processed on your Mac. Kawaru doesn't send it anywhere.
- There are no accounts and no analytics.
- The photos of the gestures you record and the icons you choose for your captions are saved in
  `~/Library/Application Support/Kawaru`. Delete them whenever you like.
