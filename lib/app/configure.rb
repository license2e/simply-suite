# Email
ActionMailer::Base.delivery_method = :smtp
ActionMailer::Base.perform_deliveries = true
ActionMailer::Base.smtp_settings = {
    :address => "smtp.gmail.com",
    :port => "587",
    :domain => "gmail.com",
    :enable_starttls_auto => true,
    :authentication => :login,
    :user_name => "username",
    :password => "password"
}
ActionMailer::Base.raise_delivery_errors = true

# Database
DataMapper::Property::String.length(255)
DataMapper::setup(:default, ENV['DATABASE_URL'])
