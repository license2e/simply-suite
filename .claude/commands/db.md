Query the Simply Suite SQLite database directly using Ruby and Sequel.

Usage:
  /db <SQL or Ruby expression>

The database is at db/development.sqlite3 (from DATABASE_URL in .env).

Steps:
1. Build a Ruby one-liner that connects to the DB and runs the given query:
   bundle exec ruby -e "
     require 'dotenv'; Dotenv.load;
     require 'sequel';
     DB = Sequel.connect(ENV.fetch('DATABASE_URL'));
     require 'pp';
     pp DB[$ARGUMENTS.to_sym].all
   "
   OR for raw SQL, use:
   bundle exec ruby -e "
     require 'dotenv'; Dotenv.load;
     require 'sequel';
     DB = Sequel.connect(ENV.fetch('DATABASE_URL'));
     DB.fetch('$ARGUMENTS').each { |r| puts r.inspect }
   "
   Run from /home/doublenot/sites/doublenot/simply-suite

2. For general queries (SELECT ...), use DB.fetch with the raw SQL.
   For table listing, use: DB.tables.inspect
   Format output clearly for the user.

3. Show the full results to the user.

If no argument was given, list all tables using:
   bundle exec ruby -e "require 'dotenv'; Dotenv.load; require 'sequel'; DB = Sequel.connect(ENV.fetch('DATABASE_URL')); puts DB.tables.inspect"
