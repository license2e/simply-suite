require 'dotenv'
Dotenv.load

require 'sequel'
require 'bcrypt'

DB = Sequel.connect(ENV.fetch('DATABASE_URL'))

require_relative '../models/user'

print "Login (email or username): "
login = $stdin.gets.chomp
print "Password: "
password = $stdin.gets.chomp
print "First name: "
first_name = $stdin.gets.chomp
print "Last name: "
last_name = $stdin.gets.chomp

User.create(
  login: login,
  hashed_password: BCrypt::Password.create(password).to_s,
  first_name: first_name,
  last_name: last_name,
  is_admin: true,
  created_at: Time.now,
  updated_at: Time.now
)

puts "Admin user '#{login}' created."
