require 'digest/sha1'

module Sinatra
  module SessionAuth
    module ModelHelpers
      def self.included(klass)
        klass.send :include, InstanceMethods
        klass.send :extend, ClassMethods
      end 

      module InstanceMethods
        def password=(pass)
          @password = pass
          self.salt = self.class.random_string(10) unless self.salt
          self.hashed_password = self.class.encrypt(@password, self.salt)
        end
      end

      module ClassMethods
        def encrypt(pass, salt)
          Digest::SHA1.hexdigest(pass + salt)
        end

        def authenticate(args={})
          raise ArgumentError, ":login argument expected" if args[:login] == nil
          raise ArgumentError, ":password argument expected" if args[:password] == nil
          login, pass = args[:login], args[:password]
          u = self.first(:login => login)
          return nil if u.nil?
          if self.encrypt(pass, u.salt) == u.hashed_password then
            return u
          end
          nil
        end

        def random_string(len)
          chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
          str = ""
          1.upto(len) { |i| str << chars[rand(chars.size-1)] }
          return str
        end
      end
    end
    
    module Helpers
      def login_url_redirect
        return '/protected/login'
      end
      
      def inactivity?
        if session[:auth_invalid] == true then
          session[:auth_invalid] = nil
          return true
        end
        return false
      end
      
      def authorized?
        if session[:auth_token] && Time.now.to_i < session[:auth_timeout] then
          # extend for another 20 mins
          session[:auth_timeout] = (Time.now+(20*60)).to_i
          return true 
        end
        if session[:auth_token] != false then
          session[:auth_invalid] = true
          logout!
        end
        return false
      end

      def authorize!
        login_url = "#{self.login_url_redirect}?r=#{request.path}"
        redirect login_url unless authorized?
      end
      
      def authenticate(klass, login, password)
        u = klass.authenticate({:login => login, :password => password})
        if u != nil then
          if u.attributes.key?(:lastlogin_at) then
            u.update({
              :lastlogin_at => DateTime.now
            })
          end
          session[:auth_token] = u.class.encrypt(u.login+u.class.random_string(12)+Time.now.to_s, u.salt)
          session[:auth_timeout] = (Time.now+(20*60)).to_i
          session[:auth_user_id] = u.id
          session[:auth_user] = {}
          set_user_data(u)
          return true
        end
        return false
      end

      def set_user_data(u)
        session[:auth_user][:id] = u.id
      end

      def logout!
        session[:auth_timeout] = nil
        session[:auth_token] = false
        session[:auth_user_id] = nil
      end
      
      def self.registered(klass)
        #klass.helpers SessionAuth::Helpers
      end
    end
  end

  register SessionAuth
end