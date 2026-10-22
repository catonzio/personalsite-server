# Kiosk on the laptop screen

The laptop runs with the lid closed; when opened, the screen shows the Monitor
tab of the infra dashboard in full screen. Firefox ESR reads the dashboard
directly on `127.0.0.1:8090` (no Traefik, no basicAuth).

## Install (GNOME session of user `dcatone`)

```sh
mkdir -p ~/.config/autostart
cp infra/dashboard/kiosk/server-dashboard.desktop ~/.config/autostart/
```

It starts at the next login. To start it now without logging out, run the `Exec`
command from a terminal inside the GNOME session. To quit kiosk mode, press
`Alt+F4`. To uninstall, delete the file from `~/.config/autostart/`.

Change the live refresh (seconds) and the history range in the URL inside the
`.desktop` file: `?refresh=5&range=24h` (ranges: 1h, 6h, 24h, 7d, 30d, 180d).

## GNOME settings (run inside the session)

- Keep idle blanking (saves power with the lid closed). Opening the lid or
  pressing a key wakes the screen.
- The page polls Glances only while it is visible; a blanked screen may still
  count as visible, so the kiosk keeps polling at the chosen interval.
- The lock screen would hide the dashboard. Disabling it means anyone with
  physical access to the laptop gets the logged-in session:
  `gsettings set org.gnome.desktop.screensaver lock-enabled false`
