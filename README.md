# wsl related issues
internal error, please report: running "firefox" failed: cannot find installed snap "firefox" at revision 6738: missing file /snap/firefox/6738/meta/snap.yaml
# Use this if you specifically want the snap version of Firefox in WSL.
# Enable systemd inside WSL
`code`echo -e "[boot]\nsystemd=true" | sudo tee /etc/wsl.conf

# Now from Windows PowerShell
wsl --shutdown

# Reopen your distro, then:
sudo apt update
sudo apt install -y snapd xdg-utils
sudo systemctl enable --now snapd.socket
sudo ln -s /var/lib/snapd/snap /snap 2>/dev/null || true

# Clean stale firefox snap state
sudo snap remove firefox 2>/dev/null || true
sudo rm -rf /var/lib/snapd/snaps/firefox_*.snap /snap/firefox 2>/dev/null || true

# Reinstall
sudo snap install core
sudo snap install firefox
firefox &

## Systemd-in-WSL is officially supported; this is the recommended path when you need snaps. The “missing snap.yaml” error is a known symptom when snapd isn’t actually managing those mounts.


