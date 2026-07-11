Start the Simply Suite web server and Tailwind CSS watcher in the background.

Steps:
1. Run `bundle exec rerun --no-notify -- bundle exec puma -p 9393 2>&1 | grep -v "stty:"` with run_in_background=true from the project root (/home/doublenot/sites/doublenot/simply-suite)
2. Run `bundle exec rerun --no-notify --pattern "views/**/*.erb,app/**/*.rb,public/css/input.css" -- ./tailwindcss -i public/css/input.css -o public/css/tailwind.css 2>&1 | grep -v "stty:"` with run_in_background=true from the project root (/home/doublenot/sites/doublenot/simply-suite)
3. Wait 3 seconds, then read the web server output file to confirm puma started (look for "Listening on")
4. Tell the user the server is running on http://localhost:9393, rerun auto-reloads puma when .rb or .erb files change, and Tailwind rebuilds automatically when views or input.css change
