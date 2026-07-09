require 'bcrypt'

module SessionAuth
  module Helpers
    def authorized?
      !!(session[:auth_user] && session[:auth_user][:id])
    end

    def authorize!
      unless authorized?
        session[:return_to] = request.path
        redirect login_url_redirect
      end
    end

    def authenticate(login, password)
      user = User.authenticate(login, password)
      if user
        session[:auth_user] = { id: user.id, is_admin: user.is_admin }
        session[:last_active_at] = Time.now.to_i
        true
      else
        false
      end
    end

    def logout!
      session.clear
    end

    def inactivity?(timeout = 3600)
      return false unless session[:last_active_at]
      Time.now.to_i - session[:last_active_at] > timeout
    end

    def current_user
      return nil unless authorized?
      User[session[:auth_user][:id]]
    end
  end
end
