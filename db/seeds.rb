require 'dotenv'
Dotenv.load

require 'sequel'
require 'bcrypt'

DB = Sequel.connect(ENV.fetch('DATABASE_URL'))

require_relative '../models/user'
require_relative '../models/models'

puts "\n=== Company setup ==="
print "Company name: "
co_name = $stdin.gets.chomp
print "Contact name: "
co_contact = $stdin.gets.chomp
print "Email: "
co_email = $stdin.gets.chomp
print "Street address: "
co_street = $stdin.gets.chomp
print "City: "
co_city = $stdin.gets.chomp
print "State: "
co_state = $stdin.gets.chomp
print "ZIP: "
co_zip = $stdin.gets.chomp

Company.create(
  name: co_name, contact: co_contact, email: co_email,
  street: co_street, city: co_city, state: co_state, zip: co_zip,
  created_at: Time.now, updated_at: Time.now
)
puts "Company '#{co_name}' created."

puts "\n=== Admin user setup ==="
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
