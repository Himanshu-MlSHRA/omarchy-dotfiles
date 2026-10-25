-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Panacea pill (github.com/EnsixD/Panacea) instead of the island, if it was on.
-- Switch with: panacea-mode on | off
o.launch_on_start(os.getenv("HOME") .. "/.local/bin/panacea-mode autostart")
