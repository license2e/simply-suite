require 'spec_helper'

RSpec.describe User do
  describe '.authenticate' do
    before do
      User.create(
        login: 'test@example.com',
        hashed_password: BCrypt::Password.create('secret').to_s,
        first_name: 'Test', last_name: 'User',
        created_at: Time.now, updated_at: Time.now
      )
    end

    it 'returns the user with correct credentials' do
      user = User.authenticate('test@example.com', 'secret')
      expect(user).not_to be_nil
      expect(user.login).to eq('test@example.com')
    end

    it 'returns nil with wrong password' do
      expect(User.authenticate('test@example.com', 'wrong')).to be_nil
    end

    it 'returns nil with unknown login' do
      expect(User.authenticate('nobody@example.com', 'secret')).to be_nil
    end
  end
end
