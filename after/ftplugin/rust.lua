-- The rust ftplugin binds ]] and [[ buffer-locally to rust#Jump (jump between
-- {} blocks), which shadows the global quickfix-review maps set in init.lua.
-- Drop them so ]] / [[ review the quickfix list in rust buffers too.
pcall(vim.keymap.del, 'n', ']]', { buffer = 0 })
pcall(vim.keymap.del, 'n', '[[', { buffer = 0 })
