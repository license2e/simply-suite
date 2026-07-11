Start or stop the Simply Suite web server and Tailwind CSS watcher.

If the argument is "stop":
1. Run `fuser -k 9393/tcp 2>/dev/null; kill $(ps aux | grep "rerun" | grep -v grep | awk '{print $2}') 2>/dev/null` — ignore errors if nothing is running
2. Tell the user the server has been stopped

Otherwise (no argument or any other argument), start the server:
1. Kill any process already on port 9393: run `fuser -k 9393/tcp 2>/dev/null; sleep 1` from the project root
2. Kill any lingering rerun processes: run `kill $(ps aux | grep "rerun" | grep -v grep | awk '{print $2}') 2>/dev/null; sleep 1` — ignore errors if none are running
3. Build Tailwind CSS immediately (blocking): run `./tailwindcss -i public/css/input.css -o public/css/tailwind.css` from the project root and wait for it to finish
4. Run `bundle exec rerun --no-notify -- bundle exec puma -p 9393 2>&1 | grep -v "stty:"` with run_in_background=true from the project root (/home/doublenot/sites/doublenot/simply-suite)
5. Run `bundle exec rerun --no-notify --pattern "views/**/*.erb,app/**/*.rb,public/css/input.css" -- ./tailwindcss -i public/css/input.css -o public/css/tailwind.css 2>&1 | grep -v "stty:"` with run_in_background=true from the project root (/home/doublenot/sites/doublenot/simply-suite)
6. Wait 3 seconds, then read the web server output file to confirm puma started (look for "Listening on")
7. Tell the user the server is running on http://localhost:9393, rerun auto-reloads puma when .rb or .erb files change, and Tailwind rebuilds automatically when views or input.css change
