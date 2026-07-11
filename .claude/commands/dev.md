Start the Simply Suite web server in the background using rerun for auto-reload.

Steps:
1. Run `bundle exec rerun --no-notify -- bundle exec puma -p 9393` with run_in_background=true from the project root (/home/doublenot/sites/doublenot/simply-suite)
2. Wait 3 seconds, then read the output file to confirm puma started successfully (look for "Listening on")
3. Tell the user the server is running on http://localhost:9393 and that rerun will reload it automatically when .rb or .erb files change
4. Let them know they can continue working — if they also need Tailwind CSS watching, they can run `./tailwindcss -i public/css/input.css -o public/css/tailwind.css --watch` in a separate terminal
