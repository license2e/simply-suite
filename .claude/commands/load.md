Load invoice data from a JSON file into the Simply Suite database.

Usage: /load [path/to/file.json]
Default file: docs/invoice-template.json

Steps:
1. Run `bundle exec ruby db/load_json.rb $ARGUMENTS` from the project root (/home/doublenot/sites/doublenot/simply-suite) — if no argument was given, run without arguments so it defaults to docs/invoice-template.json
2. Show the output to the user
