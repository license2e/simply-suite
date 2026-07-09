require 'dotenv'
Dotenv.load

require 'sequel'
DB = Sequel.connect(ENV.fetch('DATABASE_URL'))
Sequel.extension :migration
Sequel::Migrator.run(DB, File.expand_path('migrations', __dir__))
puts "Migrations complete."
