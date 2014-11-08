class User
  include DataMapper::Resource
  include Sinatra::SessionAuth::ModelHelpers
  
  property :id, Serial
  property :login, String
  property :salt, String
  property :hashed_password, String
  property :first_name, String
  property :last_name, String
  property :is_admin, Boolean, :default => false
  property :lastlogin_at, DateTime
  
  property :created_at, DateTime
  property :created_on, Date
  property :updated_at, DateTime
  property :updated_on, Date
end
#User.auto_migrate! #unless User.storage_exists?
