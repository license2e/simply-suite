require 'bcrypt'

class User < Sequel::Model
  plugin :timestamps, update_on_create: true

  def self.authenticate(login, password)
    user = first(login: login)
    return nil unless user
    return nil unless BCrypt::Password.new(user.hashed_password) == password
    user
  end

  def password=(new_password)
    self.hashed_password = BCrypt::Password.create(new_password).to_s
  end
end
