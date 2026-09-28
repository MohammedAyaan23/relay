# Relay helper shortcuts

macOS has no public API for screen brightness or Do Not Disturb, so Relay uses three tiny shortcuts built
from the Shortcuts app's own actions. Relay shows these steps in its panel the first time you need them.

| Shortcut | Build it like this |
|---|---|
| **Relay Brightness** | New shortcut → add **Set Brightness** → click the brightness value → choose **Shortcut Input** |
| **Relay Focus On** | New shortcut → add **Set Focus** → set it to turn **Do Not Disturb On** |
| **Relay Focus Off** | New shortcut → add **Set Focus** → set it to turn **Do Not Disturb Off** |

The names must match exactly. Relay runs them with `shortcuts run "<name>"`; brightness is passed as a
fraction such as `0.70`.

**Optional one-click setup:** export each finished shortcut from the Shortcuts app (File → Export, "Anyone")
into `Resources/Shortcuts/<name>.shortcut`. `make app` then bundles them and Relay's panel offers
**Add Shortcut** instead of the steps.
