Start the Simply Suite development server in the background using foreman, which runs puma (via rerun for auto-reload) and the Tailwind CSS watcher in parallel.

Steps:
1. Run `bundle exec foreman start` with run_in_background=true from the project root (/home/doublenot/sites/doublenot/simply-suite)
2. Tell the user the server is starting on port 9393 and that rerun will reload it automatically when Ruby or template files change
3. Let them know they can continue working — changes will hot-reload without restarting foreman
